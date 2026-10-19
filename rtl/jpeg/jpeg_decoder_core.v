//-----------------------------------------------------------------------------
// File: jpeg_decoder_core.v
// Description: Baseline JPEG Decoder Engine for 256x144 YCbCr 4:2:0 images
// Decodes byte stream from SOI (0xFFD8) to EOI (0xFFD9).
// Integrates:
//   - Marker Parser (SOI, DQT, SOF0, DHT, SOS, EOI)
//   - DQT Quantization Table Store
//   - Huffman Variable-Length Decoder (DC and AC for Luma & Chroma)
//   - Run-length Decoder & Dequantizer with Zigzag mapping
//   - 8x8 2D IDCT
//   - 4:2:0 YCbCr -> RGB565 Converter
// Standard: Verilog-2001
//-----------------------------------------------------------------------------

`timescale 1ns / 1ps

module jpeg_decoder_core (
    input  wire        clk,
    input  wire        rst_n,

    // Stream byte input
    input  wire        in_valid,
    output wire        in_ready,
    input  wire [7:0]  in_data,

    // Pixel output to Framebuffer write port
    output wire        pixel_valid,
    output wire [7:0]  pixel_x,
    output wire [7:0]  pixel_y,
    output wire [15:0] pixel_rgb565,
    output reg         frame_done,

    // Status / Error
    output wire [3:0]  decoder_state,
    output wire [15:0] decoded_mcu_count
);

    // Standard Zigzag to Row-Major (8x8) mapping function
    function [5:0] zigzag;
        input [5:0] idx;
        begin
            case (idx)
                6'd0:  zigzag = 6'd0;   6'd1:  zigzag = 6'd1;   6'd2:  zigzag = 6'd8;   6'd3:  zigzag = 6'd16;
                6'd4:  zigzag = 6'd9;   6'd5:  zigzag = 6'd2;   6'd6:  zigzag = 6'd3;   6'd7:  zigzag = 6'd10;
                6'd8:  zigzag = 6'd17;  6'd9:  zigzag = 6'd24;  6'd10: zigzag = 6'd32;  6'd11: zigzag = 6'd25;
                6'd12: zigzag = 6'd18;  6'd13: zigzag = 6'd11;  6'd14: zigzag = 6'd4;   6'd15: zigzag = 6'd5;
                6'd16: zigzag = 6'd12;  6'd17: zigzag = 6'd19;  6'd18: zigzag = 6'd26;  6'd19: zigzag = 6'd33;
                6'd20: zigzag = 6'd40;  6'd21: zigzag = 6'd48;  6'd22: zigzag = 6'd41;  6'd23: zigzag = 6'd34;
                6'd24: zigzag = 6'd27;  6'd25: zigzag = 6'd20;  6'd26: zigzag = 6'd13;  6'd27: zigzag = 6'd6;
                6'd28: zigzag = 6'd7;   6'd29: zigzag = 6'd14;  6'd30: zigzag = 6'd21;  6'd31: zigzag = 6'd28;
                6'd32: zigzag = 6'd35;  6'd33: zigzag = 6'd42;  6'd34: zigzag = 6'd49;  6'd35: zigzag = 6'd56;
                6'd36: zigzag = 6'd57;  6'd37: zigzag = 6'd50;  6'd38: zigzag = 6'd43;  6'd39: zigzag = 6'd36;
                6'd40: zigzag = 6'd29;  6'd41: zigzag = 6'd22;  6'd42: zigzag = 6'd15;  6'd43: zigzag = 6'd23;
                6'd44: zigzag = 6'd30;  6'd45: zigzag = 6'd37;  6'd46: zigzag = 6'd44;  6'd47: zigzag = 6'd51;
                6'd48: zigzag = 6'd58;  6'd49: zigzag = 6'd59;  6'd50: zigzag = 6'd52;  6'd51: zigzag = 6'd45;
                6'd52: zigzag = 6'd38;  6'd53: zigzag = 6'd31;  6'd54: zigzag = 6'd39;  6'd55: zigzag = 6'd46;
                6'd56: zigzag = 6'd53;  6'd57: zigzag = 6'd60;  6'd58: zigzag = 6'd61;  6'd59: zigzag = 6'd54;
                6'd60: zigzag = 6'd47;  6'd61: zigzag = 6'd55;  6'd62: zigzag = 6'd62;  6'd63: zigzag = 6'd63;
                default: zigzag = 6'd0;
            endcase
        end
    endfunction

    // Main Decoder FSM
    localparam [4:0] ST_IDLE             = 5'd0;
    localparam [4:0] ST_MARKER_SCAN      = 5'd1;
    localparam [4:0] ST_SKIP_MARKER      = 5'd2;
    localparam [4:0] ST_PARSE_DQT        = 5'd3;
    localparam [4:0] ST_PARSE_SOF0       = 5'd4;
    localparam [4:0] ST_PARSE_DHT        = 5'd5;
    localparam [4:0] ST_PARSE_SOS        = 5'd6;
    localparam [4:0] ST_DECODE_DC        = 5'd7;
    localparam [4:0] ST_DECODE_DC_EXEC   = 5'd8;
    localparam [4:0] ST_DECODE_DC_UPDATE = 5'd9;
    localparam [4:0] ST_DECODE_AC        = 5'd10;
    localparam [4:0] ST_DECODE_AC_EXEC   = 5'd11;
    localparam [4:0] ST_DECODE_AC_STORE  = 5'd12;
    localparam [4:0] ST_RUN_IDCT         = 5'd13;
    localparam [4:0] ST_WAIT_IDCT        = 5'd14;
    localparam [4:0] ST_CONVERT_MCU      = 5'd15;
    localparam [4:0] ST_WAIT_MCU         = 5'd16;
    localparam [4:0] ST_FRAME_COMPLETE   = 5'd17;

    reg [4:0] state;
    assign decoder_state = state[3:0];

    // Bitstream buffer instance
    reg        bitbuf_flush;
    reg        bitbuf_consume_en;
    reg [4:0]  bitbuf_consume_count;
    wire [31:0] bit_window;
    wire [6:0]  bits_valid;
    wire        bitbuf_eoi;
    wire        bitbuf_in_ready;

    wire in_entropy_scan = (state == ST_DECODE_DC) || (state == ST_DECODE_DC_EXEC) || (state == ST_DECODE_DC_UPDATE) ||
                           (state == ST_DECODE_AC) || (state == ST_DECODE_AC_EXEC) || (state == ST_DECODE_AC_STORE) ||
                           (state == ST_RUN_IDCT)  || (state == ST_WAIT_IDCT) ||
                           (state == ST_CONVERT_MCU)|| (state == ST_WAIT_MCU);

    wire bitbuf_in_valid = in_valid && in_entropy_scan;

    jpeg_bit_buffer u_bitbuf (
        .clk           (clk),
        .rst_n         (rst_n),
        .flush         (bitbuf_flush),
        .in_valid      (bitbuf_in_valid),
        .in_ready      (bitbuf_in_ready),
        .in_data       (in_data),
        .consume_en    (bitbuf_consume_en),
        .consume_count (bitbuf_consume_count),
        .bit_window    (bit_window),
        .bits_valid    (bits_valid),
        .eoi_detected  (bitbuf_eoi)
    );

    // MCU and Block counters
    reg [4:0]  mcu_x;         // 0..15 (16 horizontal MCUs)
    reg [3:0]  mcu_y;         // 0..8  (9 vertical MCUs)
    reg [2:0]  block_idx;     // 0..5 (Y0, Y1, Y2, Y3, Cb, Cr)
    reg [6:0]  coeff_idx;     // 0..64 inside 8x8 block

    // DC predictors
    reg signed [15:0] dc_pred_y;
    reg signed [15:0] dc_pred_cb;
    reg signed [15:0] dc_pred_cr;
    reg signed [15:0] dc_diff_reg;
    reg signed [15:0] ac_val_reg;
    reg [3:0]         ac_run_reg;

    // Intermediate block storage (DC separate from AC to decouple write multiplexers)
    reg signed [15:0] block_dc_coeff;
    reg signed [15:0] block_coeffs [1:63];

    // Dequantized 8x8 block inputs to IDCT (64 * 16 bits = 1024 bits)
    reg [1023:0]      idct_in;
    reg               idct_start;
    wire              idct_done;
    wire [511:0]      idct_out;

    // Spatial block storage for current MCU (64 * 8 bits = 512 bits each)
    reg [511:0] mcu_y0;
    reg [511:0] mcu_y1;
    reg [511:0] mcu_y2;
    reg [511:0] mcu_y3;
    reg [511:0] mcu_cb;
    reg [511:0] mcu_cr;

    // Color converter interface
    reg  start_mcu_conv;
    wire conv_pixel_valid;
    wire [7:0] conv_pixel_x;
    wire [7:0] conv_pixel_y;
    wire [15:0] conv_rgb565;
    wire conv_mcu_done;

    assign pixel_valid  = conv_pixel_valid;
    assign pixel_x      = conv_pixel_x;
    assign pixel_y      = conv_pixel_y;
    assign pixel_rgb565 = conv_rgb565;

    // Marker Parsing Variables
    reg [15:0] marker_len;
    reg [15:0] marker_cnt;

    // Quantization Table Memory
    wire        q_wr_en   = in_valid && (state == ST_PARSE_DQT) && (marker_cnt >= 16'd3) && (marker_cnt < 16'd67);
    wire [5:0]  q_addr_wr = marker_cnt[5:0] - 6'd3;
    wire [7:0]  q_data_wr = in_data;
    reg         q_table_sel_wr;
    wire        q_table_sel_rd;
    wire [5:0]  q_addr_rd;
    wire [7:0]  q_data_rd;
    wire [511:0] q_table_out;

    jpeg_qtable_mem u_qmem (
        .clk          (clk),
        .rst_n        (rst_n),
        .wr_en        (q_wr_en),
        .table_sel_wr (q_table_sel_wr),
        .addr_wr      (q_addr_wr),
        .q_data_wr    (q_data_wr),
        .table_sel_rd (q_table_sel_rd),
        .addr_rd      (q_addr_rd),
        .q_data_rd    (q_data_rd),
        .q_table_out  (q_table_out)
    );

    // Huffman Variable-Length Decoder LUT
    wire        lut_is_chroma = (block_idx >= 3'd4);
    wire        lut_is_ac     = (state == ST_DECODE_AC) || (state == ST_DECODE_AC_EXEC);
    wire [15:0] lut_bit_window = bit_window[31:16];
    wire [4:0]  lut_code_len;
    wire [7:0]  lut_symbol;

    reg [4:0] huff_code_len;
    reg [7:0] huff_symbol;

    jpeg_huffman_lut u_hlut (
        .is_chroma  (lut_is_chroma),
        .is_ac      (lut_is_ac),
        .bit_window (lut_bit_window),
        .code_len   (lut_code_len),
        .symbol     (lut_symbol)
    );

    // 2D IDCT Instance
    jpeg_idct_2d u_idct (
        .clk        (clk),
        .rst_n      (rst_n),
        .start      (idct_start),
        .coeff_in   (idct_in),
        .done       (idct_done),
        .pixels_out (idct_out)
    );

    // Color Converter Instance
    jpeg_ycbcr_to_rgb u_conv (
        .clk          (clk),
        .rst_n        (rst_n),
        .start_mcu    (start_mcu_conv),
        .mcu_x        (mcu_x),
        .mcu_y        (mcu_y),
        .block_y0     (mcu_y0),
        .block_y1     (mcu_y1),
        .block_y2     (mcu_y2),
        .block_y3     (mcu_y3),
        .block_cb     (mcu_cb),
        .block_cr     (mcu_cr),
        .pixel_valid  (conv_pixel_valid),
        .pixel_x      (conv_pixel_x),
        .pixel_y      (conv_pixel_y),
        .pixel_rgb565 (conv_rgb565),
        .mcu_done     (conv_mcu_done)
    );

    reg [7:0]  prev_byte;
    reg [15:0] mcu_total_cnt;
    assign decoded_mcu_count = mcu_total_cnt;

    // Dequantizer table select: blocks 0..3 (Y) use table 0; blocks 4..5 (Cb, Cr) use table 1
    assign q_table_sel_rd = (block_idx >= 3'd4);
    assign q_addr_rd      = coeff_idx[5:0];

    function [15:0] get_mask;
        input [3:0] s_len;
        begin
            case (s_len)
                4'd0:    get_mask = 16'h0000;
                4'd1:    get_mask = 16'h0001;
                4'd2:    get_mask = 16'h0003;
                4'd3:    get_mask = 16'h0007;
                4'd4:    get_mask = 16'h000F;
                4'd5:    get_mask = 16'h001F;
                4'd6:    get_mask = 16'h003F;
                4'd7:    get_mask = 16'h007F;
                4'd8:    get_mask = 16'h00FF;
                4'd9:    get_mask = 16'h01FF;
                4'd10:   get_mask = 16'h03FF;
                4'd11:   get_mask = 16'h07FF;
                default: get_mask = 16'h0FFF;
            endcase
        end
    endfunction

    // Bit-extraction helper: get signed value from S bits
    function signed [15:0] get_signed_val;
        input [15:0] bits;
        input [3:0]  s_len;
        reg   [15:0] mask;
        begin
            mask = get_mask(s_len);
            if (s_len == 4'd0)
                get_signed_val = 16'sd0;
            else if (bits[s_len - 1'b1])
                get_signed_val = $signed(bits & mask);
            else
                get_signed_val = $signed(bits) - $signed(mask);
        end
    endfunction

    // Input flow control
    assign in_ready = (state == ST_FRAME_COMPLETE) ? 1'b0 :
                      (in_entropy_scan ? bitbuf_in_ready : 1'b1);

    integer j;
    reg [3:0]  dc_size;
    reg [4:0]  code_len;
    reg [5:0]  shift_amt;
    reg [15:0] raw_diff_bits;

    reg [3:0]  run;
    reg [3:0]  size;
    reg [4:0]  ac_code_len;
    reg [5:0]  ac_shift_amt;
    reg [15:0] raw_ac_bits;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state                <= ST_IDLE;
            bitbuf_flush         <= 1'b0;
            bitbuf_consume_en    <= 1'b0;
            bitbuf_consume_count <= 5'd0;
            prev_byte            <= 8'd0;
            mcu_x                <= 5'd0;
            mcu_y                <= 4'd0;
            block_idx            <= 3'd0;
            coeff_idx            <= 7'd0;
            dc_pred_y            <= 16'sd0;
            dc_pred_cb           <= 16'sd0;
            dc_pred_cr           <= 16'sd0;
            dc_diff_reg          <= 16'sd0;
            ac_val_reg           <= 16'sd0;
            ac_run_reg           <= 4'd0;
            frame_done           <= 1'b0;
            q_table_sel_wr       <= 1'b0;
            idct_start           <= 1'b0;
            start_mcu_conv       <= 1'b0;
            marker_len           <= 16'd0;
            marker_cnt           <= 16'd0;
            mcu_total_cnt        <= 16'd0;
            huff_code_len        <= 5'd0;
            huff_symbol          <= 8'd0;

            block_dc_coeff <= 16'sd0;
            for (j = 1; j < 64; j = j + 1) begin
                block_coeffs[j] <= 16'sd0;
            end
            idct_in <= 1024'd0;
            mcu_y0  <= {64{8'd128}};
            mcu_y1  <= {64{8'd128}};
            mcu_y2  <= {64{8'd128}};
            mcu_y3  <= {64{8'd128}};
            mcu_cb  <= {64{8'd128}};
            mcu_cr  <= {64{8'd128}};
        end else begin
            frame_done           <= 1'b0;
            idct_start           <= 1'b0;
            start_mcu_conv       <= 1'b0;
            bitbuf_flush         <= 1'b0;
            bitbuf_consume_en    <= 1'b0;
            bitbuf_consume_count <= 5'd0;

            case (state)
                ST_IDLE: begin
                    if (in_valid) begin
                        if (prev_byte == 8'hFF) begin
                            if (in_data == 8'hD8) begin // SOI
                                state         <= ST_MARKER_SCAN;
                                dc_pred_y     <= 16'sd0;
                                dc_pred_cb    <= 16'sd0;
                                dc_pred_cr    <= 16'sd0;
                                mcu_x         <= 5'd0;
                                mcu_y         <= 4'd0;
                                block_idx     <= 3'd0;
                                coeff_idx     <= 7'd0;
                                mcu_total_cnt <= 16'd0;
                                prev_byte     <= 8'd0;
                                bitbuf_flush  <= 1'b1;
                            end else if (in_data == 8'hFF) begin
                                prev_byte <= 8'hFF;
                            end else begin
                                prev_byte <= 8'd0;
                            end
                        end else if (in_data == 8'hFF) begin
                            prev_byte <= 8'hFF;
                        end
                    end
                end

                ST_MARKER_SCAN: begin
                    if (in_valid) begin
                        if (prev_byte == 8'hFF) begin
                            prev_byte <= 8'd0;
                            case (in_data)
                                8'hDB: begin // DQT
                                    state      <= ST_PARSE_DQT;
                                    marker_cnt <= 16'd0;
                                end
                                8'hC0: begin // SOF0
                                    state      <= ST_PARSE_SOF0;
                                    marker_cnt <= 16'd0;
                                end
                                8'hC4: begin // DHT
                                    state      <= ST_PARSE_DHT;
                                    marker_cnt <= 16'd0;
                                end
                                8'hDA: begin // SOS
                                    state      <= ST_PARSE_SOS;
                                    marker_cnt <= 16'd0;
                                end
                                8'hD9: begin // EOI
                                    state <= ST_FRAME_COMPLETE;
                                end
                                default: begin // APPn or COM or unknown: skip
                                    state      <= ST_SKIP_MARKER;
                                    marker_cnt <= 16'd0;
                                end
                            endcase
                        end else if (in_data == 8'hFF) begin
                            prev_byte <= 8'hFF;
                        end
                    end
                end

                ST_SKIP_MARKER: begin
                    if (in_valid) begin
                        if (marker_cnt == 16'd0) begin
                            marker_len[15:8] <= in_data;
                            marker_cnt       <= 16'd1;
                        end else if (marker_cnt == 16'd1) begin
                            marker_len[7:0] <= in_data;
                            marker_cnt      <= 16'd2;
                        end else begin
                            if (marker_cnt + 16'd1 >= marker_len) begin
                                state <= ST_MARKER_SCAN;
                            end else begin
                                marker_cnt <= marker_cnt + 16'd1;
                            end
                        end
                    end
                end

                ST_PARSE_DQT: begin
                    // Parse quantization table (Length, ID, 64 bytes)
                    if (in_valid) begin
                        if (marker_cnt == 16'd0) begin
                            marker_len[15:8] <= in_data;
                            marker_cnt       <= 16'd1;
                        end else if (marker_cnt == 16'd1) begin
                            marker_len[7:0] <= in_data;
                            marker_cnt      <= 16'd2;
                        end else if (marker_cnt == 16'd2) begin
                            // Table info (low nibble = ID)
                            q_table_sel_wr <= in_data[0];
                            marker_cnt     <= 16'd3;
                        end else begin
                            marker_cnt <= marker_cnt + 16'd1;
                            if (marker_cnt + 16'd1 >= marker_len) begin
                                state <= ST_MARKER_SCAN;
                            end
                        end
                    end
                end

                ST_PARSE_SOF0: begin
                    if (in_valid) begin
                        if (marker_cnt == 16'd0) begin
                            marker_len[15:8] <= in_data;
                            marker_cnt       <= 16'd1;
                        end else if (marker_cnt == 16'd1) begin
                            marker_len[7:0] <= in_data;
                            marker_cnt      <= 16'd2;
                        end else begin
                            if (marker_cnt + 16'd1 >= marker_len) begin
                                state <= ST_MARKER_SCAN;
                            end else begin
                                marker_cnt <= marker_cnt + 16'd1;
                            end
                        end
                    end
                end

                ST_PARSE_DHT: begin
                    if (in_valid) begin
                        if (marker_cnt == 16'd0) begin
                            marker_len[15:8] <= in_data;
                            marker_cnt       <= 16'd1;
                        end else if (marker_cnt == 16'd1) begin
                            marker_len[7:0] <= in_data;
                            marker_cnt      <= 16'd2;
                        end else begin
                            if (marker_cnt + 16'd1 >= marker_len) begin
                                state <= ST_MARKER_SCAN;
                            end else begin
                                marker_cnt <= marker_cnt + 16'd1;
                            end
                        end
                    end
                end

                ST_PARSE_SOS: begin
                    if (in_valid) begin
                        if (marker_cnt == 16'd0) begin
                            marker_len[15:8] <= in_data;
                            marker_cnt       <= 16'd1;
                        end else if (marker_cnt == 16'd1) begin
                            marker_len[7:0] <= in_data;
                            marker_cnt      <= 16'd2;
                        end else begin
                            if (marker_cnt + 16'd1 >= marker_len) begin
                                // Start of entropy scan
                                state     <= ST_DECODE_DC;
                                block_idx <= 3'd0;
                                coeff_idx <= 7'd0;
                            end else begin
                                marker_cnt <= marker_cnt + 16'd1;
                            end
                        end
                    end
                end

                ST_DECODE_DC: begin
                    if (!bitbuf_consume_en && bits_valid >= 7'd27) begin
                        huff_code_len <= lut_code_len;
                        huff_symbol   <= lut_symbol;
                        state         <= ST_DECODE_DC_EXEC;
                    end
                end

                ST_DECODE_DC_EXEC: begin
                    dc_size  = huff_symbol[3:0];
                    code_len = huff_code_len;

                    if (dc_size == 4'd0) begin
                        dc_diff_reg          <= 16'sd0;
                        bitbuf_consume_en    <= 1'b1;
                        bitbuf_consume_count <= code_len;
                    end else begin
                        shift_amt            = 6'd32 - {1'b0, code_len} - {2'd0, dc_size};
                        raw_diff_bits        = (bit_window >> shift_amt) & {16'd0, get_mask(dc_size)};
                        dc_diff_reg          <= get_signed_val(raw_diff_bits, dc_size);
                        bitbuf_consume_en    <= 1'b1;
                        bitbuf_consume_count <= code_len + {1'b0, dc_size};
                    end

                    state <= ST_DECODE_DC_UPDATE;
                end

                ST_DECODE_DC_UPDATE: begin
                    // Update predictor & store DC coefficient
                    if (block_idx < 3'd4) begin
                        dc_pred_y      <= dc_pred_y + dc_diff_reg;
                        block_dc_coeff <= dc_pred_y + dc_diff_reg;
                    end else if (block_idx == 3'd4) begin
                        dc_pred_cb     <= dc_pred_cb + dc_diff_reg;
                        block_dc_coeff <= dc_pred_cb + dc_diff_reg;
                    end else begin
                        dc_pred_cr     <= dc_pred_cr + dc_diff_reg;
                        block_dc_coeff <= dc_pred_cr + dc_diff_reg;
                    end

                    // Clear AC coefficients
                    for (j = 1; j < 64; j = j + 1) begin
                        block_coeffs[j] <= 16'sd0;
                    end

                    coeff_idx <= 7'd1;
                    state     <= ST_DECODE_AC;
                end

                ST_DECODE_AC: begin
                    if (coeff_idx >= 7'd64) begin
                        state <= ST_RUN_IDCT;
                    end else if (!bitbuf_consume_en && bits_valid >= 7'd27) begin
                        huff_code_len <= lut_code_len;
                        huff_symbol   <= lut_symbol;
                        state         <= ST_DECODE_AC_EXEC;
                    end
                end

                ST_DECODE_AC_EXEC: begin
                    run         = huff_symbol[7:4];
                    size        = huff_symbol[3:0];
                    ac_code_len = huff_code_len;

                    if (huff_symbol == 8'h00) begin // EOB
                        for (j = 1; j < 64; j = j + 1) begin
                            if (j >= coeff_idx)
                                block_coeffs[j] <= 16'sd0;
                        end
                        bitbuf_consume_en    <= 1'b1;
                        bitbuf_consume_count <= ac_code_len;
                        state                <= ST_RUN_IDCT;
                    end else if (huff_symbol == 8'hF0) begin // ZRL
                        for (j = 0; j < 16; j = j + 1) begin
                            if (coeff_idx + j < 7'd64)
                                block_coeffs[coeff_idx + j] <= 16'sd0;
                        end
                        coeff_idx            <= coeff_idx + 7'd16;
                        bitbuf_consume_en    <= 1'b1;
                        bitbuf_consume_count <= ac_code_len;
                        state                <= ST_DECODE_AC;
                    end else begin
                        ac_shift_amt = 6'd32 - {1'b0, ac_code_len} - {2'd0, size};
                        raw_ac_bits  = (bit_window >> ac_shift_amt) & {16'd0, get_mask(size)};
                        ac_val_reg   <= get_signed_val(raw_ac_bits, size);
                        ac_run_reg   <= run;

                        bitbuf_consume_en    <= 1'b1;
                        bitbuf_consume_count <= ac_code_len + {1'b0, size};
                        state                <= ST_DECODE_AC_STORE;
                    end
                end

                ST_DECODE_AC_STORE: begin
                    for (j = 0; j < 15; j = j + 1) begin
                        if (j < ac_run_reg && (coeff_idx + j < 7'd64))
                            block_coeffs[coeff_idx + j] <= 16'sd0;
                    end

                    if (coeff_idx + {3'd0, ac_run_reg} < 7'd64) begin
                        block_coeffs[coeff_idx + {3'd0, ac_run_reg}] <= ac_val_reg;
                    end

                    coeff_idx <= coeff_idx + {3'd0, ac_run_reg} + 7'd1;
                    state     <= ST_DECODE_AC;
                end

                ST_RUN_IDCT: begin
                    // Multiply coefficients by Q-table and reorder with Zigzag
                    idct_in[zigzag(6'd0)*16 +: 16] <= block_dc_coeff * $signed({8'd0, q_table_out[0*8 +: 8]});
                    for (j = 1; j < 64; j = j + 1) begin
                        idct_in[zigzag(j[5:0])*16 +: 16] <= block_coeffs[j] * $signed({8'd0, q_table_out[j*8 +: 8]});
                    end

                    idct_start <= 1'b1;
                    state      <= ST_WAIT_IDCT;
                end

                ST_WAIT_IDCT: begin
                    if (idct_done) begin
                        // Save spatial 8x8 block into MCU buffer
                        case (block_idx)
                            3'd0: mcu_y0 <= idct_out;
                            3'd1: mcu_y1 <= idct_out;
                            3'd2: mcu_y2 <= idct_out;
                            3'd3: mcu_y3 <= idct_out;
                            3'd4: mcu_cb <= idct_out;
                            3'd5: mcu_cr <= idct_out;
                            default: ;
                        endcase

                        if (block_idx == 3'd5) begin
                            // Full MCU (all 6 blocks) finished! Start color conversion
                            state <= ST_CONVERT_MCU;
                        end else begin
                            block_idx <= block_idx + 3'd1;
                            coeff_idx <= 7'd0;
                            state     <= ST_DECODE_DC;
                        end
                    end
                end

                ST_CONVERT_MCU: begin
                    start_mcu_conv <= 1'b1;
                    state          <= ST_WAIT_MCU;
                end

                ST_WAIT_MCU: begin
                    if (conv_mcu_done) begin
                        mcu_total_cnt <= mcu_total_cnt + 16'd1;
                        // Advance MCU coordinate
                        if (mcu_x == 5'd15) begin
                            mcu_x <= 5'd0;
                            if (mcu_y == 4'd8) begin
                                mcu_y <= 4'd0;
                                state <= ST_FRAME_COMPLETE;
                            end else begin
                                mcu_y     <= mcu_y + 4'd1;
                                block_idx <= 3'd0;
                                coeff_idx <= 7'd0;
                                state     <= ST_DECODE_DC;
                            end
                        end else begin
                            mcu_x     <= mcu_x + 5'd1;
                            block_idx <= 3'd0;
                            coeff_idx <= 7'd0;
                            state     <= ST_DECODE_DC;
                        end
                    end
                end

                ST_FRAME_COMPLETE: begin
                    frame_done   <= 1'b1;
                    prev_byte    <= 8'd0;
                    bitbuf_flush <= 1'b1;
                    state        <= ST_IDLE;
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule
