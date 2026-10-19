//-----------------------------------------------------------------------------
// File: scaler_5x.v
// Description: 5x Nearest-Neighbor Video Scaler with RGB565 -> RGB888 Expansion
// Maps 256x144 source video to exact 1280x720 HDMI display
// 256 * 5 = 1280, 144 * 5 = 720. Zero black borders / zero letterboxing!
// Compensates for BRAM 1-clock read latency by pipelining HDMI timing signals.
// Standard: Verilog-2001
//-----------------------------------------------------------------------------

`timescale 1ns / 1ps

module scaler_5x (
    input  wire        clk_pixel,
    input  wire        rst_pixel_n,

    // Coordinates and timing directly from hdmi_timing_gen
    input  wire [11:0] hdmi_pixel_x,
    input  wire [11:0] hdmi_pixel_y,
    input  wire        hdmi_hsync,
    input  wire        hdmi_vsync,
    input  wire        hdmi_vde,

    // Framebuffer read interface
    output wire        fb_rd_en,
    output wire [7:0]  fb_rd_x,
    output wire [7:0]  fb_rd_y,
    input  wire [15:0] fb_rd_rgb565, // Returned 1 cycle after rd_en

    // Output to TMDS / HDMI transmitter
    output wire [11:0] pixel_x_out,
    output wire [11:0] pixel_y_out,
    output wire        hsync_out,
    output wire        vsync_out,
    output wire        vde_out,
    output wire [23:0] rgb888_out
);

    // Coordinate mapping: src = hdmi / 5
    // hdmi_pixel_x in [0..1279] -> src_x in [0..255]
    // hdmi_pixel_y in [0..719]  -> src_y in [0..143]
    wire [11:0] div_x = hdmi_pixel_x / 12'd5;
    wire [11:0] div_y = hdmi_pixel_y / 12'd5;

    assign fb_rd_x  = div_x[7:0];
    assign fb_rd_y  = div_y[7:0];
    assign fb_rd_en = hdmi_vde;

    // Pipeline stage 1: match BRAM 1-cycle read latency
    reg [11:0] pixel_x_d1, pixel_y_d1;
    reg        hsync_d1, vsync_d1, vde_d1;

    always @(posedge clk_pixel or negedge rst_pixel_n) begin
        if (!rst_pixel_n) begin
            pixel_x_d1 <= 12'd0;
            pixel_y_d1 <= 12'd0;
            hsync_d1   <= 1'b0;
            vsync_d1   <= 1'b0;
            vde_d1     <= 1'b0;
        end else begin
            pixel_x_d1 <= hdmi_pixel_x;
            pixel_y_d1 <= hdmi_pixel_y;
            hsync_d1   <= hdmi_hsync;
            vsync_d1   <= hdmi_vsync;
            vde_d1     <= hdmi_vde;
        end
    end

    assign pixel_x_out = pixel_x_d1;
    assign pixel_y_out = pixel_y_d1;
    assign hsync_out   = hsync_d1;
    assign vsync_out   = vsync_d1;
    assign vde_out     = vde_d1;

    // RGB565 to RGB888 expansion:
    // R[7:0] = {R[4:0], R[4:2]}
    // G[7:0] = {G[5:0], G[5:4]}
    // B[7:0] = {B[4:0], B[4:2]}
    wire [4:0] r5 = fb_rd_rgb565[15:11];
    wire [5:0] g6 = fb_rd_rgb565[10:5];
    wire [4:0] b5 = fb_rd_rgb565[4:0];

    wire [7:0] r8 = {r5, r5[4:2]};
    wire [7:0] g8 = {g6, g6[5:4]};
    wire [7:0] b8 = {b5, b5[4:2]};

    assign rgb888_out = vde_d1 ? {r8, g8, b8} : 24'h000000;

endmodule
