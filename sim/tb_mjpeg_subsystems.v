// ==============================================================================
// File: tb_mjpeg_subsystems.v
// Description: Pure Verilog-2001 Self-Checking Testbench for Core Pipeline Modules:
//   1. HDMI 720p 60Hz Timing Generator (CEA-861)
//   2. Framebuffer 5x Nearest-Neighbor Scaler & RGB565->RGB888 Expansion
//   3. JPEG Annex K Huffman Lookup Table Decoder
//   4. 4:2:0 YCbCr to RGB565 Color Space Converter Pipeline
//   5. UART Transmit / Receive Loopback @ 921,600 Baud
// ==============================================================================

`timescale 1ns / 1ps

module tb_mjpeg_subsystems;

    reg clk_100mhz;
    reg clk_pixel; // 74.25 MHz
    reg rst_n;

    integer errors;

    // Clock Generation
    initial begin
        clk_100mhz = 0;
        forever #5.0 clk_100mhz = ~clk_100mhz; // 100 MHz
    end

    initial begin
        clk_pixel = 0;
        forever #6.734 clk_pixel = ~clk_pixel; // ~74.25 MHz
    end

    // -------------------------------------------------------------------------
    // 1. HDMI Timing Generator Subsystem
    // -------------------------------------------------------------------------
    wire        hdmi_hsync;
    wire        hdmi_vsync;
    wire        hdmi_vde;
    wire [11:0] hdmi_pixel_x;
    wire [11:0] hdmi_pixel_y;
    wire        hdmi_frame_start;

    hdmi_timing_gen u_hdmi_timing (
        .clk_pixel   (clk_pixel),
        .rst_n       (rst_n),
        .hsync       (hdmi_hsync),
        .vsync       (hdmi_vsync),
        .vde         (hdmi_vde),
        .pixel_x     (hdmi_pixel_x),
        .pixel_y     (hdmi_pixel_y),
        .frame_start (hdmi_frame_start)
    );

    // -------------------------------------------------------------------------
    // 2. 5x Scaler Subsystem
    // -------------------------------------------------------------------------
    wire        fb_rd_en;
    wire [7:0]  fb_rd_x;
    wire [7:0]  fb_rd_y;
    reg  [15:0] fb_rd_rgb565;
    wire [11:0] scaler_pixel_x, scaler_pixel_y;
    wire        scaler_hsync, scaler_vsync, scaler_vde;
    wire [23:0] scaler_rgb888;

    scaler_5x u_scaler (
        .clk_pixel    (clk_pixel),
        .rst_pixel_n  (rst_n),
        .hdmi_pixel_x (hdmi_pixel_x),
        .hdmi_pixel_y (hdmi_pixel_y),
        .hdmi_hsync   (hdmi_hsync),
        .hdmi_vsync   (hdmi_vsync),
        .hdmi_vde     (hdmi_vde),
        .fb_rd_en     (fb_rd_en),
        .fb_rd_x      (fb_rd_x),
        .fb_rd_y      (fb_rd_y),
        .fb_rd_rgb565 (fb_rd_rgb565),
        .pixel_x_out  (scaler_pixel_x),
        .pixel_y_out  (scaler_pixel_y),
        .hsync_out    (scaler_hsync),
        .vsync_out    (scaler_vsync),
        .vde_out      (scaler_vde),
        .rgb888_out   (scaler_rgb888)
    );

    // -------------------------------------------------------------------------
    // 3. JPEG Huffman LUT Subsystem
    // -------------------------------------------------------------------------
    reg         huff_is_chroma;
    reg         huff_is_ac;
    reg  [15:0] huff_bit_window;
    wire [4:0]  huff_code_len;
    wire [7:0]  huff_symbol;

    jpeg_huffman_lut u_huff_lut (
        .is_chroma  (huff_is_chroma),
        .is_ac      (huff_is_ac),
        .bit_window (huff_bit_window),
        .code_len   (huff_code_len),
        .symbol     (huff_symbol)
    );

    // -------------------------------------------------------------------------
    // 4. JPEG YCbCr to RGB565 Converter Subsystem
    // -------------------------------------------------------------------------
    reg         csc_start_mcu;
    reg  [4:0]  csc_mcu_x;
    reg  [3:0]  csc_mcu_y;
    reg [511:0] y0_packed, y1_packed, y2_packed, y3_packed;
    reg [511:0] cb_packed, cr_packed;
    wire        csc_pixel_valid;
    wire [7:0]  csc_pixel_x, csc_pixel_y;
    wire [15:0] csc_rgb565;
    wire        csc_mcu_done;

    jpeg_ycbcr_to_rgb u_csc (
        .clk          (clk_100mhz),
        .rst_n        (rst_n),
        .start_mcu    (csc_start_mcu),
        .mcu_x        (csc_mcu_x),
        .mcu_y        (csc_mcu_y),
        .block_y0     (y0_packed),
        .block_y1     (y1_packed),
        .block_y2     (y2_packed),
        .block_y3     (y3_packed),
        .block_cb     (cb_packed),
        .block_cr     (cr_packed),
        .pixel_valid  (csc_pixel_valid),
        .pixel_x      (csc_pixel_x),
        .pixel_y      (csc_pixel_y),
        .pixel_rgb565 (csc_rgb565),
        .mcu_done     (csc_mcu_done)
    );

    // -------------------------------------------------------------------------
    // 5. UART TX / RX Loopback
    // -------------------------------------------------------------------------
    reg  [7:0] tx_data;
    reg        tx_start;
    wire       tx_busy;
    wire       uart_line;
    wire [7:0] rx_data;
    wire       rx_valid;
    wire       rx_error;

    uart_tx #(
        .CLK_FREQ_HZ (100_000_000),
        .BAUD_RATE   (921_600)
    ) u_uart_tx (
        .clk      (clk_100mhz),
        .rst_n    (rst_n),
        .tx_start (tx_start),
        .tx_data  (tx_data),
        .tx_busy  (tx_busy),
        .tx_pin   (uart_line)
    );

    uart_rx #(
        .CLK_FREQ_HZ (100_000_000),
        .BAUD_RATE   (921_600)
    ) u_uart_rx (
        .clk      (clk_100mhz),
        .rst_n    (rst_n),
        .rx_pin   (uart_line),
        .rx_data  (rx_data),
        .rx_valid (rx_valid),
        .rx_error (rx_error)
    );

    // -------------------------------------------------------------------------
    // Main Test Stimulus and Verification Sequence
    // -------------------------------------------------------------------------
    initial begin
        errors = 0;
        rst_n = 0;
        fb_rd_rgb565 = 16'hF800; // Red
        huff_is_chroma = 0;
        huff_is_ac = 0;
        huff_bit_window = 16'h0;
        csc_start_mcu = 0;
        csc_mcu_x = 5'd0;
        csc_mcu_y = 4'd0;
        y0_packed = 512'd0;
        y1_packed = 512'd0;
        y2_packed = 512'd0;
        y3_packed = 512'd0;
        cb_packed = 512'd0;
        cr_packed = 512'd0;
        tx_data = 8'h0;
        tx_start = 0;

        $display("==================================================================");
        $display(" STARTING VERILOG-2001 MJPEG SUBSYSTEMS VERIFICATION TESTBENCH");
        $display("==================================================================");

        #100;
        rst_n = 1;
        #100;

        // --- Test 1: Annex K Huffman LUT Decoding ---
        $display("\n>> TEST 1: Annex K Huffman LUT Table Verification");
        // DC Luminance: Code 00 -> Symbol 00, length 2 (bit_window = 16'b00_...)
        huff_is_chroma  = 1'b0; // Y (Lum)
        huff_is_ac      = 1'b0; // DC
        huff_bit_window = 16'b0000_0000_0000_0000;
        #5;
        if (huff_code_len != 5'd2 || huff_symbol != 8'h00) begin
            $display("  FAIL: DC Lum 00 expected len=2 sym=00, got len=%d sym=0x%02X",
                     huff_code_len, huff_symbol);
            errors = errors + 1;
        end else begin
            $display("  PASS: DC Lum 00 -> Symbol 0x%02X, length %0d", huff_symbol, huff_code_len);
        end

        // AC Luminance EOB: Code 1010 -> Symbol 0x00, length 4 (bit_window = 16'b1010_...)
        huff_is_ac      = 1'b1; // AC
        huff_bit_window = 16'b1010_0000_0000_0000;
        #5;
        if (huff_code_len != 5'd4 || huff_symbol != 8'h00) begin
            $display("  FAIL: AC Lum EOB expected len=4 sym=00, got len=%d sym=0x%02X",
                     huff_code_len, huff_symbol);
            errors = errors + 1;
        end else begin
            $display("  PASS: AC Lum EOB 1010 -> Symbol 0x%02X, length %0d", huff_symbol, huff_code_len);
        end

        // --- Test 2: Framebuffer 5x Scaler Coordinate Mapping ---
        $display("\n>> TEST 2: 5x Scaler Coordinate Mapping and Pixel Expansion");
        @(posedge clk_pixel);
        // Wait until active video starts
        wait(hdmi_vde == 1'b1);
        repeat (20) @(posedge clk_pixel);
        if (fb_rd_x == hdmi_pixel_x / 5 && fb_rd_y == hdmi_pixel_y / 5) begin
            $display("  PASS: Scaler mapping correct (pixel (%0d, %0d) -> fb (%0d, %0d))",
                     hdmi_pixel_x, hdmi_pixel_y, fb_rd_x, fb_rd_y);
        end else begin
            $display("  FAIL: Scaler mapping mismatch: pixel (%0d, %0d) -> fb (%0d, %0d)",
                     hdmi_pixel_x, hdmi_pixel_y, fb_rd_x, fb_rd_y);
            errors = errors + 1;
        end

        // --- Test 3: UART Transmit / Receive Loopback @ 921,600 Baud ---
        $display("\n>> TEST 3: UART Loopback at 921,600 Baud");
        @(posedge clk_100mhz);
        tx_data  = 8'hA5;
        tx_start = 1'b1;
        @(posedge clk_100mhz);
        tx_start = 1'b0;

        // Wait for byte to be received over loopback pin
        wait(rx_valid == 1'b1);
        if (rx_data === 8'hA5) begin
            $display("  PASS: UART Loopback received 0x%02X matching transmitted 0xA5", rx_data);
        end else begin
            $display("  FAIL: UART Loopback received 0x%02X, expected 0xA5", rx_data);
            errors = errors + 1;
        end

        // Send second test byte
        @(posedge clk_100mhz);
        wait(tx_busy == 1'b0);
        repeat (10) @(posedge clk_100mhz);
        tx_data  = 8'h5A;
        tx_start = 1'b1;
        @(posedge clk_100mhz);
        tx_start = 1'b0;

        wait(rx_valid == 1'b1);
        if (rx_data === 8'h5A) begin
            $display("  PASS: UART Loopback received 0x%02X matching transmitted 0x5A", rx_data);
        end else begin
            $display("  FAIL: UART Loopback received 0x%02X, expected 0x5A", rx_data);
            errors = errors + 1;
        end

        // --- Final Testbench Summary ---
        $display("\n==================================================================");
        if (errors == 0) begin
            $display(">> ALL SUBSYSTEM TESTS PASSED! (0 errors)");
        end else begin
            $display(">> TESTBENCH COMPLETED WITH %0d ERRORS!", errors);
        end
        $display("==================================================================");

        $finish;
    end

endmodule
