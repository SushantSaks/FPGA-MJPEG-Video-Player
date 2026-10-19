//-----------------------------------------------------------------------------
// File: hdmi_tx_top.v
// Description: HDMI Transmit Subsystem Top Module
// Integrates 720p timing generator, test pattern generator, 8b/10b TMDS encoders,
// and serializer.
// Standard: Verilog-2001
//-----------------------------------------------------------------------------

`timescale 1ns / 1ps

module hdmi_tx_top (
    input  wire        clk_pixel,    // 74.25 MHz pixel clock
    input  wire        clk_pixel_5x, // 371.25 MHz 5x serial clock
    input  wire        rst_n,

    // Video data source control
    input  wire        pattern_mode, // 1 = internal test pattern, 0 = external video
    input  wire [2:0]  pattern_sel,  // Test pattern selector
    input  wire [23:0] video_rgb_in, // External RGB888 from framebuffer/scaler

    // Timing and coordinate outputs to source/framebuffer
    output wire [11:0] pixel_x,
    output wire [11:0] pixel_y,
    output wire        hsync,
    output wire        vsync,
    output wire        vde,
    output wire        frame_start,
    output wire        line_start,

    // Active RGB out (for simulation verification / debug)
    output wire [23:0] rgb_active,

    // Physical HDMI differential outputs
    output wire        hdmi_tx_clk_p,
    output wire        hdmi_tx_clk_n,
    output wire [2:0]  hdmi_tx_data_p,
    output wire [2:0]  hdmi_tx_data_n
);

    // 1. Timing generation
    hdmi_timing_gen u_timing (
        .clk_pixel   (clk_pixel),
        .rst_n       (rst_n),
        .pixel_x     (pixel_x),
        .pixel_y     (pixel_y),
        .hsync       (hsync),
        .vsync       (vsync),
        .vde         (vde),
        .frame_start (frame_start),
        .line_start  (line_start)
    );

    // 2. Test pattern generation
    wire [23:0] pattern_rgb;
    hdmi_test_pattern u_pattern (
        .clk_pixel   (clk_pixel),
        .rst_n       (rst_n),
        .pixel_x     (pixel_x),
        .pixel_y     (pixel_y),
        .vde         (vde),
        .pattern_sel (pattern_sel),
        .rgb_data    (pattern_rgb)
    );

    // Multiplex external video or internal test pattern
    wire [23:0] active_rgb_mux = pattern_mode ? pattern_rgb : video_rgb_in;
    assign rgb_active          = vde ? active_rgb_mux : 24'h000000;

    wire [7:0] red_byte   = rgb_active[23:16];
    wire [7:0] green_byte = rgb_active[15:8];
    wire [7:0] blue_byte  = rgb_active[7:0];

    // 3. TMDS Encoders (3 channels)
    wire [9:0] tmds_d0; // Blue + Sync
    wire [9:0] tmds_d1; // Green
    wire [9:0] tmds_d2; // Red

    // Channel 0: Blue + Hsync/Vsync
    tmds_encoder u_enc_b (
        .clk_pixel (clk_pixel),
        .rst_n     (rst_n),
        .data_in   (blue_byte),
        .ctrl_in   ({vsync, hsync}),
        .vde       (vde),
        .tmds_out  (tmds_d0)
    );

    // Channel 1: Green (control signals fixed 2'b00)
    tmds_encoder u_enc_g (
        .clk_pixel (clk_pixel),
        .rst_n     (rst_n),
        .data_in   (green_byte),
        .ctrl_in   (2'b00),
        .vde       (vde),
        .tmds_out  (tmds_d1)
    );

    // Channel 2: Red (control signals fixed 2'b00)
    tmds_encoder u_enc_r (
        .clk_pixel (clk_pixel),
        .rst_n     (rst_n),
        .data_in   (red_byte),
        .ctrl_in   (2'b00),
        .vde       (vde),
        .tmds_out  (tmds_d2)
    );

    // 4. TMDS Serializer
    tmds_serializer u_serializer (
        .clk_pixel      (clk_pixel),
        .clk_pixel_5x   (clk_pixel_5x),
        .rst_n          (rst_n),
        .tmds_d0        (tmds_d0),
        .tmds_d1        (tmds_d1),
        .tmds_d2        (tmds_d2),
        .tmds_clk       (10'b1111100000),
        .hdmi_tx_clk_p  (hdmi_tx_clk_p),
        .hdmi_tx_clk_n  (hdmi_tx_clk_n),
        .hdmi_tx_data_p (hdmi_tx_data_p),
        .hdmi_tx_data_n (hdmi_tx_data_n)
    );

endmodule
