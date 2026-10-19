//-----------------------------------------------------------------------------
// File: jpeg_ycbcr_to_rgb.v
// Description: Color space converter from 4:2:0 YCbCr MCU to RGB565 pixels
// An MCU contains 4 Y blocks (Y0, Y1, Y2, Y3), 1 Cb block, 1 Cr block.
// Converts 256 spatial samples (16x16) into RGB565 stream with pixel coordinates.
// Pipelined into a 2-stage architecture for high-frequency timing closure.
// Standard: Verilog-2001
//-----------------------------------------------------------------------------

`timescale 1ns / 1ps

module jpeg_ycbcr_to_rgb (
    input  wire        clk,
    input  wire        rst_n,

    // Trigger to convert current MCU
    input  wire        start_mcu,
    input  wire [4:0]  mcu_x, // 0..15 for 256 width
    input  wire [3:0]  mcu_y, // 0..8 for 144 height

    // 6 input 8x8 blocks for current MCU (64 bytes = 512 bits each)
    input  wire [511:0] block_y0,
    input  wire [511:0] block_y1,
    input  wire [511:0] block_y2,
    input  wire [511:0] block_y3,
    input  wire [511:0] block_cb,
    input  wire [511:0] block_cr,

    // Output pixel stream to framebuffer write port
    output reg         pixel_valid,
    output reg  [7:0]  pixel_x,
    output reg  [7:0]  pixel_y,
    output reg  [15:0] pixel_rgb565,
    output reg         mcu_done
);

    // =========================================================================
    // Stage 1: Spatial Sample Selection & Coordinate Generation
    // =========================================================================
    reg [8:0] pixel_cnt; // 0..255
    reg       busy;

    wire [3:0] local_x = pixel_cnt[3:0]; // 0..15 within MCU
    wire [3:0] local_y = pixel_cnt[7:4]; // 0..15 within MCU

    // Select Y sample
    reg [7:0] y_sample;
    wire [2:0] sub_x = local_x[2:0];
    wire [2:0] sub_y = local_y[2:0];
    wire [5:0] sub_idx = {sub_y, sub_x};

    always @* begin
        case ({local_y[3], local_x[3]})
            2'b00: y_sample = block_y0[sub_idx*8 +: 8]; // Top-Left
            2'b01: y_sample = block_y1[sub_idx*8 +: 8]; // Top-Right
            2'b10: y_sample = block_y2[sub_idx*8 +: 8]; // Bottom-Left
            2'b11: y_sample = block_y3[sub_idx*8 +: 8]; // Bottom-Right
        endcase
    end

    // 4:2:0 Chroma subsampling: chroma is 8x8, sampled at (local_y/2, local_x/2)
    wire [2:0] chroma_x = local_x[3:1];
    wire [2:0] chroma_y = local_y[3:1];
    wire [5:0] chroma_idx = {chroma_y, chroma_x};

    wire [7:0] cb_sample = block_cb[chroma_idx*8 +: 8];
    wire [7:0] cr_sample = block_cr[chroma_idx*8 +: 8];

    // Frame coordinates for current sample
    wire [7:0] cur_out_x = {mcu_x[3:0], 4'd0} + {4'd0, local_x};
    wire [7:0] cur_out_y = {mcu_y[3:0], 4'd0} + {4'd0, local_y};

    // Stage 1 Registers
    reg [7:0] y_reg;
    reg [7:0] cb_reg;
    reg [7:0] cr_reg;
    reg [7:0] x_reg;
    reg [7:0] y_coord_reg;
    reg       valid_st1;
    reg       done_st1;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pixel_cnt   <= 9'd0;
            busy        <= 1'b0;
            valid_st1   <= 1'b0;
            done_st1    <= 1'b0;
            y_reg       <= 8'd0;
            cb_reg      <= 8'd0;
            cr_reg      <= 8'd0;
            x_reg       <= 8'd0;
            y_coord_reg <= 8'd0;
        end else begin
            done_st1 <= 1'b0;

            if (start_mcu && !busy) begin
                busy      <= 1'b1;
                pixel_cnt <= 9'd0;
                valid_st1 <= 1'b0;
            end else if (busy) begin
                valid_st1   <= 1'b1;
                y_reg       <= y_sample;
                cb_reg      <= cb_sample;
                cr_reg      <= cr_sample;
                x_reg       <= cur_out_x;
                y_coord_reg <= cur_out_y;

                if (pixel_cnt == 9'd255) begin
                    busy     <= 1'b0;
                    done_st1 <= 1'b1;
                end else begin
                    pixel_cnt <= pixel_cnt + 9'd1;
                end
            end else begin
                valid_st1 <= 1'b0;
            end
        end
    end

    // =========================================================================
    // Stage 2: Fixed-Point DSP Multiplications (Registered Outputs)
    // =========================================================================
    wire signed [31:0] cb_diff_32 = $signed({24'd0, cb_reg}) - 32'sd128;
    wire signed [31:0] cr_diff_32 = $signed({24'd0, cr_reg}) - 32'sd128;

    reg signed [31:0] y_scaled_st2;
    reg signed [31:0] r_term_st2;
    reg signed [31:0] g_term_cb_st2;
    reg signed [31:0] g_term_cr_st2;
    reg signed [31:0] b_term_st2;
    reg [7:0]         x_st2;
    reg [7:0]         y_coord_st2;
    reg               valid_st2;
    reg               done_st2;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_st2     <= 1'b0;
            done_st2      <= 1'b0;
            x_st2         <= 8'd0;
            y_coord_st2   <= 8'd0;
            y_scaled_st2  <= 32'sd0;
            r_term_st2    <= 32'sd0;
            g_term_cb_st2 <= 32'sd0;
            g_term_cr_st2 <= 32'sd0;
            b_term_st2    <= 32'sd0;
        end else begin
            valid_st2     <= valid_st1;
            done_st2      <= done_st1;
            x_st2         <= x_reg;
            y_coord_st2   <= y_coord_reg;
            y_scaled_st2  <= $signed({8'd0, y_reg, 16'd0});
            r_term_st2    <= 32'sd91881 * cr_diff_32;
            g_term_cb_st2 <= 32'sd22554 * cb_diff_32;
            g_term_cr_st2 <= 32'sd46802 * cr_diff_32;
            b_term_st2    <= 32'sd116130 * cb_diff_32;
        end
    end

    // =========================================================================
    // Stage 3: Term Accumulation, Clamping & RGB565 Packing
    // =========================================================================
    wire signed [31:0] r_calc = y_scaled_st2 + r_term_st2;
    wire signed [31:0] g_calc = y_scaled_st2 - g_term_cb_st2 - g_term_cr_st2;
    wire signed [31:0] b_calc = y_scaled_st2 + b_term_st2;

    wire signed [31:0] r_val = (r_calc + 32'sd32768) >>> 16;
    wire signed [31:0] g_val = (g_calc + 32'sd32768) >>> 16;
    wire signed [31:0] b_val = (b_calc + 32'sd32768) >>> 16;

    // Saturation clamping to [0..255]
    function [7:0] clamp8;
        input signed [31:0] v;
        begin
            if (v < 32'sd0)
                clamp8 = 8'd0;
            else if (v > 32'sd255)
                clamp8 = 8'd255;
            else
                clamp8 = v[7:0];
        end
    endfunction

    wire [7:0] r_clamped = clamp8(r_val);
    wire [7:0] g_clamped = clamp8(g_val);
    wire [7:0] b_clamped = clamp8(b_val);

    // Pack RGB565: {R[7:3], G[7:2], B[7:3]}
    wire [15:0] rgb565 = {r_clamped[7:3], g_clamped[7:2], b_clamped[7:3]};

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pixel_valid  <= 1'b0;
            pixel_x      <= 8'd0;
            pixel_y      <= 8'd0;
            pixel_rgb565 <= 16'd0;
            mcu_done     <= 1'b0;
        end else begin
            pixel_valid <= valid_st2;
            mcu_done    <= done_st2;

            if (valid_st2) begin
                pixel_x      <= x_st2;
                pixel_y      <= y_coord_st2;
                pixel_rgb565 <= rgb565;
            end
        end
    end

endmodule
