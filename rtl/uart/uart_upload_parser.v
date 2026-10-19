`timescale 1ns / 1ps
// ============================================================================
// Module: uart_upload_parser
// Description: UART Video Stream Receiver, QSPI Flash Programmer, and 
//              Readback Verifier with FIFO interface.
// Standard: Verilog-2001
// ============================================================================

module uart_upload_parser #(
    parameter [23:0] VIDEO_BASE_ADDR = 24'h400000 // Default 4 MB offset in Flash
) (
    input  wire        clk,
    input  wire        rst_n,

    // UART RX Interface
    input  wire [7:0]  rx_data,
    input  wire        rx_valid,
    output wire        rx_ready,

    // UART TX Interface (for status reports and ACK/NAK)
    output reg         tx_start,
    output reg  [7:0]  tx_data,
    input  wire        tx_busy,

    // QSPI Controller Command Interface
    output reg  [2:0]  qspi_cmd_op,
    output reg  [23:0] qspi_cmd_addr,
    output reg  [8:0]  qspi_cmd_byte_len,
    output reg         qspi_cmd_start,
    input  wire        qspi_cmd_busy,
    input  wire        qspi_cmd_done,
    input  wire [7:0]  flash_status_reg,

    // QSPI Controller Write Interface
    output reg  [7:0]  qspi_wr_data,
    output reg         qspi_wr_valid,
    input  wire        qspi_wr_ready,

    // QSPI Controller Read Interface (for readback verification)
    input  wire [7:0]  qspi_rd_data,
    input  wire        qspi_rd_valid,
    output reg         qspi_rd_ready,
    output reg         qspi_stream_mode,
    output reg         qspi_stream_stop,

    // Video Storage Status to Playback Engine
    output wire [23:0] video_start_addr,
    output wire [31:0] video_file_size,
    output reg         upload_active,
    output reg         upload_done,
    output reg         upload_success
);

    // Command Opcodes for QSPI controller
    localparam [2:0] OP_READ         = 3'd0;
    localparam [2:0] OP_PAGE_PROG    = 3'd1;
    localparam [2:0] OP_SECTOR_ERASE = 3'd2;
    localparam [2:0] OP_WREN         = 3'd4;
    localparam [2:0] OP_RDSR         = 3'd5;

    // Protocol Constants
    localparam [31:0] PROTOCOL_MAGIC = 32'h4D4A5047; // ASCII "MJPG"
    localparam [31:0] PROTOCOL_END   = 32'h454E4421; // ASCII "END!"

    // Standard IEEE 802.3 CRC32 byte function
    function [31:0] crc32_byte;
        input [31:0] current_crc;
        input [7:0]  data_byte;
        reg   [31:0] c;
        integer      i;
        begin
            c = current_crc ^ {24'h0, data_byte};
            for (i = 0; i < 8; i = i + 1) begin
                if (c[0])
                    c = (c >> 1) ^ 32'hEDB88320;
                else
                    c = c >> 1;
            end
            crc32_byte = c;
        end
    endfunction

    // Parser States
    localparam [4:0] ST_IDLE             = 5'd0;
    localparam [4:0] ST_HDR_MAGIC        = 5'd1;
    localparam [4:0] ST_HDR_SIZE         = 5'd2;
    localparam [4:0] ST_HDR_META         = 5'd3;
    localparam [4:0] ST_ERASE_WREN       = 5'd4;
    localparam [4:0] ST_ERASE_WREN_WAIT  = 5'd5;
    localparam [4:0] ST_ERASE_CMD_WAIT   = 5'd6;
    localparam [4:0] ST_ERASE_POLL_START = 5'd7;
    localparam [4:0] ST_ERASE_POLL_WAIT  = 5'd8;
    localparam [4:0] ST_RCV_PAYLOAD      = 5'd9;
    localparam [4:0] ST_PAGE_WREN        = 5'd10;
    localparam [4:0] ST_PAGE_WREN_WAIT   = 5'd11;
    localparam [4:0] ST_PAGE_WRITE       = 5'd12;
    localparam [4:0] ST_PAGE_POLL_START  = 5'd13;
    localparam [4:0] ST_PAGE_POLL_WAIT   = 5'd14;
    localparam [4:0] ST_RCV_CRC          = 5'd15;
    localparam [4:0] ST_RCV_END          = 5'd16;
    localparam [4:0] ST_VERIFY_START     = 5'd17;
    localparam [4:0] ST_VERIFY_READ      = 5'd18;
    localparam [4:0] ST_VERIFY_EVAL      = 5'd19;
    localparam [4:0] ST_SEND_REPORT      = 5'd20;
    localparam [4:0] ST_WAIT_TX          = 5'd21;
    localparam [4:0] ST_DONE             = 5'd22;

    reg [4:0] state;

    // 256-byte page buffer for QSPI page programming (Inferred as Distributed LUT-RAM)
    reg [7:0] page_buffer [0:255];
    reg [8:0] page_buf_count;
    reg [8:0] page_buf_rd_idx;

    wire page_buf_wr_en = (state == ST_RCV_PAYLOAD) && rx_valid;
    always @(posedge clk) begin
        if (page_buf_wr_en) begin
            page_buffer[page_buf_count[7:0]] <= rx_data;
        end
    end

    reg [15:0] video_width;
    reg [15:0] video_height;
    reg [7:0]  video_fps;

    // Upload & Video Registers
    reg [31:0] expected_file_size;
    reg [31:0] expected_crc;
    reg [31:0] running_rx_crc;
    reg [31:0] running_rb_crc;
    reg [31:0] bytes_received;
    reg [31:0] bytes_programmed;
    reg [31:0] bytes_verified;

    // Flash address pointer
    reg [23:0] current_flash_addr;
    reg [23:0] erase_flash_addr;
    reg [15:0] sectors_to_erase;
    reg [15:0] sector_erase_idx;

    assign video_start_addr = VIDEO_BASE_ADDR;
    assign video_file_size  = expected_file_size;

    reg [3:0] sub_idx;
    reg [7:0] report_code;

    assign rx_ready = (state == ST_IDLE) || (state == ST_HDR_MAGIC) || 
                      (state == ST_HDR_SIZE) || (state == ST_HDR_META) || 
                      (state == ST_RCV_PAYLOAD) || (state == ST_RCV_CRC) || 
                      (state == ST_RCV_END);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state              <= ST_IDLE;
            sub_idx            <= 4'd0;
            expected_file_size <= 32'd0;
            video_width        <= 16'd0;
            video_height       <= 16'd0;
            video_fps          <= 8'd0;
            expected_crc       <= 32'd0;
            running_rx_crc     <= 32'hFFFFFFFF;
            running_rb_crc     <= 32'hFFFFFFFF;
            bytes_received     <= 32'd0;
            bytes_programmed   <= 32'd0;
            bytes_verified     <= 32'd0;
            current_flash_addr <= VIDEO_BASE_ADDR;
            erase_flash_addr   <= VIDEO_BASE_ADDR;
            sectors_to_erase   <= 16'd0;
            sector_erase_idx   <= 16'd0;
            page_buf_count     <= 9'd0;
            page_buf_rd_idx    <= 9'd0;
            qspi_cmd_start     <= 1'b0;
            qspi_cmd_op        <= 3'd0;
            qspi_cmd_addr      <= 24'd0;
            qspi_cmd_byte_len  <= 9'd0;
            qspi_wr_valid      <= 1'b0;
            qspi_wr_data       <= 8'd0;
            qspi_rd_ready      <= 1'b0;
            qspi_stream_mode   <= 1'b0;
            qspi_stream_stop   <= 1'b0;
            tx_start           <= 1'b0;
            tx_data            <= 8'd0;
            upload_active      <= 1'b0;
            upload_done        <= 1'b0;
            upload_success     <= 1'b0;
            report_code        <= 8'h00;
        end else begin
            qspi_cmd_start <= 1'b0;
            tx_start       <= 1'b0;
            upload_done    <= 1'b0;

            case (state)
                ST_IDLE: begin
                    upload_active      <= 1'b0;
                    sub_idx            <= 4'd0;
                    bytes_received     <= 32'd0;
                    bytes_programmed   <= 32'd0;
                    bytes_verified     <= 32'd0;
                    running_rx_crc     <= 32'hFFFFFFFF;
                    running_rb_crc     <= 32'hFFFFFFFF;
                    current_flash_addr <= VIDEO_BASE_ADDR;
                    report_code        <= 8'h00;
                    erase_flash_addr   <= VIDEO_BASE_ADDR;
                    page_buf_count     <= 9'd0;
                    qspi_stream_mode   <= 1'b0;
                    qspi_stream_stop   <= 1'b0;

                    if (rx_valid) begin
                        if (rx_data == PROTOCOL_MAGIC[31:24]) begin // 'M'
                            sub_idx <= 4'd1;
                            state   <= ST_HDR_MAGIC;
                        end
                    end
                end

                ST_HDR_MAGIC: begin
                    upload_active <= 1'b1;
                    if (rx_valid) begin
                        case (sub_idx)
                            4'd1: begin
                                if (rx_data == PROTOCOL_MAGIC[23:16]) sub_idx <= 4'd2; // 'J'
                                else state <= ST_IDLE;
                            end
                            4'd2: begin
                                if (rx_data == PROTOCOL_MAGIC[15:8]) sub_idx <= 4'd3;  // 'P'
                                else state <= ST_IDLE;
                            end
                            4'd3: begin
                                if (rx_data == PROTOCOL_MAGIC[7:0]) begin // 'G'
                                    sub_idx <= 4'd0;
                                    state   <= ST_HDR_SIZE;
                                end else begin
                                    state <= ST_IDLE;
                                end
                            end
                            default: state <= ST_IDLE;
                        endcase
                    end
                end

                ST_HDR_SIZE: begin
                    if (rx_valid) begin
                        expected_file_size <= {expected_file_size[23:0], rx_data};
                        if (sub_idx == 4'd3) begin
                            sub_idx <= 4'd0;
                            state   <= ST_HDR_META;
                        end else begin
                            sub_idx <= sub_idx + 4'd1;
                        end
                    end
                end

                ST_HDR_META: begin
                    if (rx_valid) begin
                        case (sub_idx)
                            4'd0: video_width[15:8]  <= rx_data;
                            4'd1: video_width[7:0]   <= rx_data;
                            4'd2: video_height[15:8] <= rx_data;
                            4'd3: video_height[7:0]  <= rx_data;
                            4'd4: video_fps          <= rx_data;
                            4'd5: begin
                                // End of metadata: calculate sectors to erase (4 KB per sector, full 32-bit math)
                                sectors_to_erase <= (expected_file_size + 32'd4095) >> 12;
                                sector_erase_idx <= 16'd0;
                                erase_flash_addr <= VIDEO_BASE_ADDR;
                                sub_idx          <= 4'd0;
                                state            <= ST_ERASE_WREN;
                            end
                            default: ;
                        endcase
                        if (sub_idx < 4'd5) sub_idx <= sub_idx + 4'd1;
                    end
                end

                // --- Flash Sector Erase Sequence with WIP Status Polling ---
                ST_ERASE_WREN: begin
                    qspi_cmd_op    <= OP_WREN;
                    qspi_cmd_start <= 1'b1;
                    state          <= ST_ERASE_WREN_WAIT;
                end

                ST_ERASE_WREN_WAIT: begin
                    if (qspi_cmd_done) begin
                        qspi_cmd_op    <= OP_SECTOR_ERASE;
                        qspi_cmd_addr  <= erase_flash_addr;
                        qspi_cmd_start <= 1'b1;
                        state          <= ST_ERASE_CMD_WAIT;
                    end
                end

                ST_ERASE_CMD_WAIT: begin
                    if (qspi_cmd_done) begin
                        // Command dispatched to Flash; poll RDSR until physical erase completes (WIP == 0)
                        state <= ST_ERASE_POLL_START;
                    end
                end

                ST_ERASE_POLL_START: begin
                    qspi_cmd_op    <= OP_RDSR;
                    qspi_cmd_start <= 1'b1;
                    state          <= ST_ERASE_POLL_WAIT;
                end

                ST_ERASE_POLL_WAIT: begin
                    if (qspi_cmd_done) begin
                        if (flash_status_reg[0] == 1'b0) begin
                            // WIP is 0: physical sector erase finished!
                            sector_erase_idx <= sector_erase_idx + 16'd1;
                            erase_flash_addr <= erase_flash_addr + 24'd4096;
                            if (sector_erase_idx + 16'd1 >= sectors_to_erase) begin
                                // All needed sectors erased! Ready for payload.
                                state <= ST_RCV_PAYLOAD;
                            end else begin
                                state <= ST_ERASE_WREN;
                            end
                        end else begin
                            // Still busy: poll again
                            state <= ST_ERASE_POLL_START;
                        end
                    end
                end

                // --- Receive Payload & Buffer for Page Program ---
                ST_RCV_PAYLOAD: begin
                    if (rx_valid) begin
                        page_buf_count <= page_buf_count + 9'd1;
                        bytes_received <= bytes_received + 32'd1;
                        running_rx_crc <= crc32_byte(running_rx_crc, rx_data);

                        if (page_buf_count == 9'd255 || (bytes_received + 32'd1 >= expected_file_size)) begin
                            // 256 bytes buffered OR last partial page of file reached!
                            page_buf_rd_idx <= 9'd0;
                            state           <= ST_PAGE_WREN;
                        end
                    end
                end

                // --- Page Program Sequence with WIP Status Polling ---
                ST_PAGE_WREN: begin
                    qspi_cmd_op    <= OP_WREN;
                    qspi_cmd_start <= 1'b1;
                    state          <= ST_PAGE_WREN_WAIT;
                end

                ST_PAGE_WREN_WAIT: begin
                    if (qspi_cmd_done) begin
                        qspi_cmd_op       <= OP_PAGE_PROG;
                        qspi_cmd_addr     <= current_flash_addr;
                        qspi_cmd_byte_len <= page_buf_count;
                        qspi_cmd_start    <= 1'b1;
                        qspi_wr_valid     <= 1'b0;
                        page_buf_rd_idx   <= 9'd0;
                        state             <= ST_PAGE_WRITE;
                    end
                end

                ST_PAGE_WRITE: begin
                    if (qspi_wr_ready && page_buf_rd_idx < page_buf_count) begin
                        qspi_wr_data    <= page_buffer[page_buf_rd_idx[7:0]];
                        qspi_wr_valid   <= 1'b1;
                        page_buf_rd_idx <= page_buf_rd_idx + 9'd1;
                    end else begin
                        qspi_wr_valid <= 1'b0;
                    end

                    if (qspi_cmd_done) begin
                        // Bytes clocked out to Flash; poll RDSR until physical page programming completes
                        state <= ST_PAGE_POLL_START;
                    end
                end

                ST_PAGE_POLL_START: begin
                    qspi_cmd_op    <= OP_RDSR;
                    qspi_cmd_start <= 1'b1;
                    state          <= ST_PAGE_POLL_WAIT;
                end

                ST_PAGE_POLL_WAIT: begin
                    if (qspi_cmd_done) begin
                        if (flash_status_reg[0] == 1'b0) begin
                            // Page programming completely finished in physical silicon!
                            bytes_programmed   <= bytes_programmed + {23'd0, page_buf_count};
                            current_flash_addr <= current_flash_addr + {15'd0, page_buf_count};
                            page_buf_count     <= 9'd0;
                            if (bytes_received >= expected_file_size) begin
                                sub_idx <= 4'd0;
                                state   <= ST_RCV_CRC;
                            end else begin
                                state   <= ST_RCV_PAYLOAD;
                            end
                        end else begin
                            // Still busy programming cells: poll again
                            state <= ST_PAGE_POLL_START;
                        end
                    end
                end

                // --- Receive Expected CRC32 ---
                ST_RCV_CRC: begin
                    if (rx_valid) begin
                        expected_crc <= {expected_crc[23:0], rx_data};
                        if (sub_idx == 4'd3) begin
                            sub_idx <= 4'd0;
                            state   <= ST_RCV_END;
                        end else begin
                            sub_idx <= sub_idx + 4'd1;
                        end
                    end
                end

                // --- Receive Completion Marker "END!" ---
                ST_RCV_END: begin
                    if (rx_valid) begin
                        case (sub_idx)
                            4'd0: if (rx_data != PROTOCOL_END[31:24]) begin report_code <= 8'h17; state <= ST_SEND_REPORT; end // 'E'
                            4'd1: if (rx_data != PROTOCOL_END[23:16]) begin report_code <= 8'h17; state <= ST_SEND_REPORT; end // 'N'
                            4'd2: if (rx_data != PROTOCOL_END[15:8])  begin report_code <= 8'h17; state <= ST_SEND_REPORT; end // 'D'
                            4'd3: begin
                                if (rx_data == PROTOCOL_END[7:0]) begin // '!'
                                    // Header, payload & upload packet verified!
                                    // Start Section 14 Readback Verification!
                                    state <= ST_VERIFY_START;
                                end else begin
                                    report_code <= 8'h17;
                                    state       <= ST_SEND_REPORT;
                                end
                            end
                            default: begin
                                report_code <= 8'h17;
                                state       <= ST_SEND_REPORT;
                            end
                        endcase
                        sub_idx <= sub_idx + 4'd1;
                    end
                end

                // --- Section 14: QSPI Flash Readback Verification ---
                ST_VERIFY_START: begin
                    if (!qspi_cmd_busy) begin
                        qspi_cmd_op      <= OP_READ;
                        qspi_cmd_addr    <= VIDEO_BASE_ADDR;
                        qspi_stream_mode <= 1'b1;
                        qspi_stream_stop <= 1'b0;
                        qspi_cmd_start   <= 1'b1;
                        qspi_rd_ready    <= 1'b1;
                        running_rb_crc   <= 32'hFFFFFFFF;
                        bytes_verified   <= 32'd0;
                        state            <= ST_VERIFY_READ;
                    end
                end

                ST_VERIFY_READ: begin
                    qspi_rd_ready <= 1'b1;
                    if (qspi_rd_valid) begin
                        bytes_verified <= bytes_verified + 32'd1;
                        running_rb_crc <= crc32_byte(running_rb_crc, qspi_rd_data);

                        if (bytes_verified + 32'd1 >= expected_file_size) begin
                            qspi_stream_stop <= 1'b1;
                            state            <= ST_VERIFY_EVAL;
                        end
                    end
                end

                ST_VERIFY_EVAL: begin
                    qspi_rd_ready <= 1'b0;
                    if (qspi_cmd_done) begin
                        qspi_stream_mode <= 1'b0;
                        qspi_stream_stop <= 1'b0;

                        // Check CRC match
                        if ((running_rb_crc ^ 32'hFFFFFFFF) == expected_crc &&
                            (running_rx_crc ^ 32'hFFFFFFFF) == expected_crc) begin
                            report_code    <= 8'h06; // ACK: Full upload & flash verified
                            upload_success <= 1'b1;
                        end else if ((running_rx_crc ^ 32'hFFFFFFFF) != expected_crc) begin
                            report_code    <= 8'h16; // NAK: UART RX corrupted / byte dropped
                            upload_success <= 1'b0;
                        end else begin
                            report_code    <= 8'h15; // NAK: Flash memory readback mismatch
                            upload_success <= 1'b0;
                        end
                        state <= ST_SEND_REPORT;
                    end
                end

                // --- Send Verification Report & ACK/NAK over UART TX ---
                ST_SEND_REPORT: begin
                    if (!tx_busy && !tx_start) begin
                        tx_data  <= report_code;
                        tx_start <= 1'b1;
                        state    <= ST_WAIT_TX;
                    end
                end

                ST_WAIT_TX: begin
                    if (tx_busy) begin
                        state <= ST_DONE;
                    end
                end

                ST_DONE: begin
                    if (!tx_busy) begin
                        upload_done   <= 1'b1;
                        upload_active <= 1'b0;
                        state         <= ST_IDLE;
                    end
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule
