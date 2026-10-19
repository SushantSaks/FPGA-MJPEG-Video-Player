//-----------------------------------------------------------------------------
// File: framebuffer_double_buffer.v
// Description: Double-Buffered RGB565 Framebuffer (256x144 resolution)
// Total storage: 2 * 256 * 144 = 73,728 x 16-bit words (~144 KB)
// Bank 0: 0x00000 - 0x08FFF
// Bank 1: 0x09000 - 0x11FFF
// Bank switching occurs synchronously on VSYNC rising edge to prevent tearing.
// Standard: Verilog-2001
//-----------------------------------------------------------------------------

`timescale 1ns / 1ps

module framebuffer_double_buffer #(
    parameter integer FRAME_WIDTH  = 256,
    parameter integer FRAME_HEIGHT = 144
)(
    // Write side (Decoder / Video Input)
    input  wire        clk_wr,
    input  wire        rst_wr_n,
    input  wire        wr_en,
    input  wire [7:0]  wr_x,
    input  wire [7:0]  wr_y,
    input  wire [15:0] wr_rgb565,
    input  wire        frame_write_done, // 1-cycle pulse when full frame is decoded

    // Read side (HDMI / Scaler)
    input  wire        clk_pixel,
    input  wire        rst_pixel_n,
    input  wire        vsync_in,         // VSYNC from HDMI timing generator
    input  wire        rd_en,
    input  wire [7:0]  rd_x,
    input  wire [7:0]  rd_y,
    output wire [15:0] rd_rgb565,

    // Status outputs
    output wire        current_write_bank,
    output wire        current_read_bank,
    output reg  [31:0] total_frames_displayed
);

    // Bank registers
    reg write_bank;
    reg read_bank;
    reg swap_pending;
    reg vsync_prev;

    assign current_write_bank = write_bank;
    assign current_read_bank  = read_bank;

    // Toggle-based CDC synchronizer for frame_write_done
    reg wr_done_toggle;
    always @(posedge clk_wr or negedge rst_wr_n) begin
        if (!rst_wr_n) begin
            wr_done_toggle <= 1'b0;
        end else if (frame_write_done) begin
            wr_done_toggle <= ~wr_done_toggle;
        end
    end

    reg wr_done_sync0, wr_done_sync1, wr_done_sync2;
    always @(posedge clk_pixel or negedge rst_pixel_n) begin
        if (!rst_pixel_n) begin
            wr_done_sync0 <= 1'b0;
            wr_done_sync1 <= 1'b0;
            wr_done_sync2 <= 1'b0;
        end else begin
            wr_done_sync0 <= wr_done_toggle;
            wr_done_sync1 <= wr_done_sync0;
            wr_done_sync2 <= wr_done_sync1;
        end
    end
    wire write_done_pulse = wr_done_sync1 ^ wr_done_sync2;

    // Bank swap state machine (operated in pixel clock domain)
    always @(posedge clk_pixel or negedge rst_pixel_n) begin
        if (!rst_pixel_n) begin
            write_bank             <= 1'b1; // Start writing to Bank 1
            read_bank              <= 1'b0; // Start reading from Bank 0
            swap_pending           <= 1'b0;
            vsync_prev             <= 1'b0;
            total_frames_displayed <= 32'd0;
        end else begin
            vsync_prev <= vsync_in;

            // When a new frame finishes writing, mark swap as pending
            if (write_done_pulse) begin
                swap_pending <= 1'b1;
            end

            // On rising edge of VSYNC, execute bank swap if pending
            if (vsync_in && !vsync_prev) begin
                if (swap_pending) begin
                    read_bank              <= write_bank;
                    write_bank             <= ~write_bank;
                    swap_pending           <= 1'b0;
                    total_frames_displayed <= total_frames_displayed + 32'd1;
                end
            end
        end
    end

    // Address calculations:
    // Because width is 256 (2^8), offset = (y << 8) | x = {y, x}
    wire [15:0] wr_offset = {wr_y, wr_x};
    wire [15:0] rd_offset = {rd_y, rd_x};

    wire [16:0] b_wr_addr = write_bank ? (17'd36864 + {1'b0, wr_offset}) : {1'b0, wr_offset};
    wire [16:0] b_rd_addr = read_bank  ? (17'd36864 + {1'b0, rd_offset}) : {1'b0, rd_offset};

    // Instantiate Dual-Port BRAM
    bram_dual_port #(
        .DATA_WIDTH (16),
        .ADDR_WIDTH (17),
        .DEPTH      (73728)
    ) u_bram (
        .clk_wr  (clk_wr),
        .we      (wr_en),
        .addr_wr (b_wr_addr),
        .din     (wr_rgb565),

        .clk_rd  (clk_pixel),
        .re      (rd_en),
        .addr_rd (b_rd_addr),
        .dout    (rd_rgb565)
    );

endmodule
