`timescale 1ns / 1ps
// ============================================================================
// Module: mjpeg_player_top
// Description: Master SoC Top-Level Module for FPGA Hardware MJPEG Video Player
// Target: AMD Spartan-7 XC7S50-CSGA324-1 (RealDigital Boolean Board)
// Standard: Verilog-2001
// ============================================================================

module mjpeg_player_top #(
    parameter integer CLK_FREQ_HZ     = 100_000_000,
    parameter integer UART_BAUD_RATE  = 921_600,
    parameter [23:0]  VIDEO_BASE_ADDR = 24'h400000
) (
    // Primary 100 MHz Oscillator (Pin F14)
    input  wire        clk_100mhz,

`ifndef SYNTHESIS
    // Direct pixel clock inputs for bit-accurate simulation
    input  wire        sim_clk_pixel,
    input  wire        sim_clk_pixel_5x,

    // Simulation outputs for VirtualHDMIMonitor
    output wire [11:0] dbg_pixel_x,
    output wire [11:0] dbg_pixel_y,
    output wire        dbg_hsync,
    output wire        dbg_vsync,
    output wire        dbg_vde,
    output wire [23:0] dbg_rgb_active,
    output wire [4:0]  dbg_parser_state,
    output wire        dbg_fb_swap_buffers,
    output wire        dbg_fb_wr_en,
    output wire [15:0] dbg_current_frame,
    output wire [15:0] dbg_total_frames_decoded,
    output wire [1:0]  dbg_pb_state,
`endif

    // Active-Low Reset Pushbutton (Pin H2)
    input  wire        rst_btn_n,

    // Slide Switches (Pin V2: SW0 - Test Pattern / Live Video, Pin U2: SW1)
    input  wire [1:0]  sw,

    // Control Pushbuttons (Pin J2: Play/Pause, Pin J1: Restart)
    input  wire        btn_play_pause,
    input  wire        btn_restart,

    // 16 Onboard LEDs (Pins G1..A4)
    output wire [15:0] led,

    // USB-UART Bridge Pins (Pin V12: RX from PC, Pin U11/R12: TX to PC)
    input  wire        uart_rx_pin,
    output wire        uart_tx_pin,
`ifdef SYNTHESIS
    output wire        uart_tx_alt_pin,
`endif

    // Winbond W25Q128 QSPI Flash Physical Pins (Exact RealDigital Boolean Board Pins)
    output wire        qspi_cs_n,
    output wire        qspi_io0_do,
    input  wire        qspi_io1_di,
    output wire        qspi_io2_do,
    output wire        qspi_io3_do,

`ifndef SYNTHESIS
    output wire        qspi_sck,
    output wire        qspi_io0_oe,
    input  wire        qspi_io0_di,
    output wire        qspi_io1_oe,
    output wire        qspi_io1_do,
    output wire        qspi_io2_oe,
    input  wire        qspi_io2_di,
    output wire        qspi_io3_oe,
    input  wire        qspi_io3_di,
`endif

    // HDMI 720p Differential TMDS Pairs
    output wire        hdmi_tx_clk_p,
    output wire        hdmi_tx_clk_n,
    output wire [2:0]  hdmi_tx_data_p,
    output wire [2:0]  hdmi_tx_data_n
);

    // ========================================================================
    // 1. Clock Management & Reset Conditioning
    // ========================================================================
    wire clk_sys   = clk_100mhz;
    wire clk_pixel;
    wire clk_pixel_5x;
    wire mmcm_locked;

`ifdef SYNTHESIS
    // Spartan-7 MMCM: 100 MHz in -> 74.25 MHz pixel clock & 371.25 MHz 5x serial clock
    wire clk_fb;
    wire clk_pixel_unbuf;
    wire clk_pixel_5x_unbuf;

    MMCME2_BASE #(
        .BANDWIDTH("OPTIMIZED"),
        .CLKFBOUT_MULT_F(37.125),   // 100 * 37.125 / 5 = 742.5 MHz VCO
        .CLKFBOUT_PHASE(0.0),
        .CLKIN1_PERIOD(10.0),
        .CLKOUT0_DIVIDE_F(10.0),    // 742.5 / 10 = 74.25 MHz
        .CLKOUT1_DIVIDE(2),         // 742.5 / 2 = 371.25 MHz
        .DIVCLK_DIVIDE(5),
        .STARTUP_WAIT("FALSE")
    ) u_mmcm (
        .CLKOUT0(clk_pixel_unbuf),
        .CLKOUT1(clk_pixel_5x_unbuf),
        .CLKFBOUT(clk_fb),
        .LOCKED(mmcm_locked),
        .CLKIN1(clk_100mhz),
        .PWRDWN(1'b0),
        .RST(1'b0),                 // Free-running MMCM: Never shut down by reset button
        .CLKFBIN(clk_fb)
    );

    BUFG u_bufg_pixel (.I(clk_pixel_unbuf),    .O(clk_pixel));
    BUFG u_bufg_5x    (.I(clk_pixel_5x_unbuf), .O(clk_pixel_5x));

    // Power-On Reset shift register (~0.65 ms at 100 MHz)
    reg [15:0] por_shift;
    initial por_shift = 16'h0000;
    always @(posedge clk_sys) begin
        por_shift <= {por_shift[14:0], 1'b1};
    end
    wire por_ready = por_shift[15];

    // On RealDigital Boolean Board, pushbuttons are ACTIVE-HIGH (0 = released, 1 = pressed)
    wire manual_reset       = rst_btn_n; 
    wire sys_reset_assert   = (!por_ready) || manual_reset;
    wire pixel_reset_assert = (!por_ready) || (!mmcm_locked) || manual_reset;
`else
    assign clk_pixel        = sim_clk_pixel;
    assign clk_pixel_5x     = sim_clk_pixel_5x;
    assign mmcm_locked      = 1'b1;

    wire sys_reset_assert   = !rst_btn_n;
    wire pixel_reset_assert = !rst_btn_n;
`endif

    // Reset synchronizer for 100 MHz domain
    reg [2:0] rst_sync_sys;
    always @(posedge clk_sys or posedge sys_reset_assert) begin
        if (sys_reset_assert) rst_sync_sys <= 3'b000;
        else                  rst_sync_sys <= {rst_sync_sys[1:0], 1'b1};
    end
    wire rst_sys_n = rst_sync_sys[2];

    // Reset synchronizer for 74.25 MHz pixel domain
    reg [2:0] rst_sync_pixel;
    always @(posedge clk_pixel or posedge pixel_reset_assert) begin
        if (pixel_reset_assert) rst_sync_pixel <= 3'b000;
        else                    rst_sync_pixel <= {rst_sync_pixel[1:0], 1'b1};
    end
    wire rst_pixel_n = rst_sync_pixel[2];

    // ========================================================================
    // 2. Pushbutton Debouncers
    // ========================================================================
    wire play_pause_pulse;
    wire restart_pulse;

    button_debounce #(
        .CLK_FREQ_HZ(CLK_FREQ_HZ),
        .DEBOUNCE_MS(10)
    ) u_db_play (
        .clk(clk_sys),
        .rst_n(rst_sys_n),
        .btn_in(btn_play_pause),
        .btn_state(),
        .btn_pulse(play_pause_pulse)
    );

    button_debounce #(
        .CLK_FREQ_HZ(CLK_FREQ_HZ),
        .DEBOUNCE_MS(10)
    ) u_db_restart (
        .clk(clk_sys),
        .rst_n(rst_sys_n),
        .btn_in(btn_restart),
        .btn_state(),
        .btn_pulse(restart_pulse)
    );

    // ========================================================================
    // 3. UART Video Upload Engine
    // ========================================================================
    wire [2:0]  upload_cmd_op;
    wire [23:0] upload_cmd_addr;
    wire [8:0]  upload_cmd_byte_len;
    wire        upload_cmd_start;
    wire [7:0]  upload_wr_data;
    wire        upload_wr_valid;
    wire        upload_rd_ready;
    wire        upload_stream_mode;
    wire        upload_stream_stop;

    // QSPI Controller interconnect wires
    wire        qspi_cmd_busy;
    wire        qspi_cmd_done;
    wire [7:0]  qspi_rd_data;
    wire        qspi_rd_valid;
    wire        qspi_wr_ready;
    wire        qspi_sck_int;

    wire [23:0] video_start_addr;
    wire [31:0] video_file_size;
    wire        upload_done;
    wire        upload_active;
    wire        upload_success;
    wire [7:0]  qspi_flash_status;

`ifdef SYNTHESIS
    assign uart_tx_alt_pin = uart_tx_pin;
`endif

    uart_upload_top #(
        .CLK_FREQ_HZ(CLK_FREQ_HZ),
        .BAUD_RATE(UART_BAUD_RATE),
        .VIDEO_BASE_ADDR(VIDEO_BASE_ADDR)
    ) u_uploader (
        .clk(clk_sys),
        .rst_n(rst_sys_n),
        .uart_rx_pin(uart_rx_pin),
        .uart_tx_pin(uart_tx_pin),
        .qspi_cmd_op(upload_cmd_op),
        .qspi_cmd_addr(upload_cmd_addr),
        .qspi_cmd_byte_len(upload_cmd_byte_len),
        .qspi_cmd_start(upload_cmd_start),
        .qspi_cmd_busy(qspi_cmd_busy),
        .qspi_cmd_done(qspi_cmd_done),
        .flash_status_reg(qspi_flash_status),
        .qspi_wr_data(upload_wr_data),
        .qspi_wr_valid(upload_wr_valid),
        .qspi_wr_ready(qspi_wr_ready),
        .qspi_rd_data(qspi_rd_data),
        .qspi_rd_valid(qspi_rd_valid),
        .qspi_rd_ready(upload_rd_ready),
        .qspi_stream_mode(upload_stream_mode),
        .qspi_stream_stop(upload_stream_stop),
        .video_start_addr(video_start_addr),
        .video_file_size(video_file_size),
        .upload_active(upload_active),
        .upload_done(upload_done),
        .upload_success(upload_success)
    );

    // ========================================================================
    // 4. QSPI Video Playback Reader
    // ========================================================================
    wire [2:0]  pb_cmd_op;
    wire [23:0] pb_cmd_addr;
    wire [8:0]  pb_cmd_byte_len;
    wire        pb_cmd_start;
    wire        pb_stream_mode;
    wire        pb_stream_stop;
    wire        pb_rd_ready;

    wire [7:0]  playback_stream_data;
    wire        playback_stream_valid;
    wire        playback_stream_ready;
    wire        restart_stream_req;

    // Video ready flag: asserted after successful upload or manual play button
    reg video_ready;
    always @(posedge clk_sys or negedge rst_sys_n) begin
        if (!rst_sys_n) begin
            video_ready <= 1'b0;
        end else if (upload_done && upload_success) begin
            video_ready <= 1'b1;
        end else if (play_pause_pulse || restart_pulse) begin
            video_ready <= 1'b1;
        end
    end

    wire pb_enable = video_ready && !upload_active;

    qspi_playback_reader #(
        .VIDEO_BASE_ADDR(VIDEO_BASE_ADDR)
    ) u_pb_reader (
        .clk(clk_sys),
        .rst_n(rst_sys_n),
        .enable(pb_enable),
        .video_start_addr(video_start_addr),
        .restart_stream(restart_stream_req),
        .qspi_cmd_op(pb_cmd_op),
        .qspi_cmd_addr(pb_cmd_addr),
        .qspi_cmd_byte_len(pb_cmd_byte_len),
        .qspi_cmd_start(pb_cmd_start),
        .qspi_cmd_busy(qspi_cmd_busy),
        .qspi_cmd_done(qspi_cmd_done),
        .qspi_rd_data(qspi_rd_data),
        .qspi_rd_valid(qspi_rd_valid),
        .qspi_rd_ready(pb_rd_ready),
        .qspi_stream_mode(pb_stream_mode),
        .qspi_stream_stop(pb_stream_stop),
        .stream_data(playback_stream_data),
        .stream_valid(playback_stream_valid),
        .stream_ready(playback_stream_ready)
    );

    // ========================================================================
    // 5. QSPI Flash Controller & Physical Multiplexer
    // ========================================================================
    wire [2:0]  qspi_cmd_op       = upload_active ? upload_cmd_op       : pb_cmd_op;
    wire [23:0] qspi_cmd_addr     = upload_active ? upload_cmd_addr     : pb_cmd_addr;
    wire [8:0]  qspi_cmd_byte_len = upload_active ? upload_cmd_byte_len : pb_cmd_byte_len;
    wire        qspi_cmd_start    = upload_active ? upload_cmd_start    : pb_cmd_start;
    wire        qspi_stream_mode  = upload_active ? upload_stream_mode  : pb_stream_mode;
    wire        qspi_stream_stop  = upload_active ? upload_stream_stop  : pb_stream_stop;
    wire        qspi_rd_ready     = upload_active ? upload_rd_ready     : pb_rd_ready;

`ifdef SYNTHESIS
    // Internal wires for bidirectional QSPI controls not mapped to package pins
    wire        qspi_io0_oe;
    wire        qspi_io0_di = 1'b0;
    wire        qspi_io1_oe;
    wire        qspi_io1_do;
    wire        qspi_io2_oe;
    wire        qspi_io2_di = 1'b1;
    wire        qspi_io3_oe;
    wire        qspi_io3_di = 1'b1;

    // Drive dedicated CCLK pin via Spartan-7 STARTUPE2 primitive
    STARTUPE2 #(
        .PROG_USR("FALSE"),
        .SIM_CCLK_FREQ(0.0)
    ) u_startup (
        .CFGCLK(),
        .CFGMCLK(),
        .EOS(),
        .PREQ(),
        .CLK(1'b0),
        .GSR(1'b0),
        .GTS(1'b0),
        .KEYCLEARB(1'b0),
        .PACK(1'b0),
        .USRCCLKO(qspi_sck_int),
        .USRCCLKTS(1'b0),
        .USRDONEO(1'b1),
        .USRDONETS(1'b1)
    );
`else
    assign qspi_sck = qspi_sck_int;
`endif

    qspi_controller u_qspi (
        .clk(clk_sys),
        .rst_n(rst_sys_n),
        .cmd_op(qspi_cmd_op),
        .cmd_addr(qspi_cmd_addr),
        .cmd_byte_len(qspi_cmd_byte_len),
        .cmd_start(qspi_cmd_start),
        .cmd_busy(qspi_cmd_busy),
        .cmd_done(qspi_cmd_done),
        .rd_data(qspi_rd_data),
        .rd_valid(qspi_rd_valid),
        .rd_ready(qspi_rd_ready),
        .stream_mode(qspi_stream_mode),
        .stream_stop(qspi_stream_stop),
        .wr_data(upload_wr_data),
        .wr_valid(upload_wr_valid),
        .wr_ready(qspi_wr_ready),
        .flash_status_reg(qspi_flash_status),
        .flash_jedec_id(),
        .qspi_cs_n(qspi_cs_n),
        .qspi_sck(qspi_sck_int),
        .qspi_io0_oe(qspi_io0_oe),
        .qspi_io0_do(qspi_io0_do),
        .qspi_io0_di(qspi_io0_di),
        .qspi_io1_oe(qspi_io1_oe),
        .qspi_io1_do(qspi_io1_do),
        .qspi_io1_di(qspi_io1_di),
        .qspi_io2_oe(qspi_io2_oe),
        .qspi_io2_do(qspi_io2_do),
        .qspi_io2_di(qspi_io2_di),
        .qspi_io3_oe(qspi_io3_oe),
        .qspi_io3_do(qspi_io3_do),
        .qspi_io3_di(qspi_io3_di)
    );

    // HDMI Timing Wires
    wire [11:0] hdmi_pixel_x;
    wire [11:0] hdmi_pixel_y;
    wire        hdmi_hsync_raw;
    wire        hdmi_vsync_raw;
    wire        hdmi_vde_raw;

    // ========================================================================
    // 6. MJPEG Video Playback & Hardware JPEG Decoder Subsystem
    // ========================================================================
    wire        fb_wr_en;
    wire [7:0]  fb_wr_x;
    wire [7:0]  fb_wr_y;
    wire [15:0] fb_wr_rgb565;
    wire        fb_swap_buffers;

    wire        is_playing;
    wire [15:0] current_frame_num;
    wire [15:0] total_frames_decoded;
    wire        fps_tick;

    // VSYNC sync into 100 MHz system clock domain
    reg [2:0] vsync_sync_sys;
    always @(posedge clk_sys or negedge rst_sys_n) begin
        if (!rst_sys_n) vsync_sync_sys <= 3'b000;
        else            vsync_sync_sys <= {vsync_sync_sys[1:0], hdmi_vsync_raw};
    end
    wire vsync_pulse_sys = vsync_sync_sys[1] && !vsync_sync_sys[2];

    mjpeg_playback_top u_playback (
        .clk(clk_sys),
        .rst_n(rst_sys_n && video_ready && !upload_active),
        .vsync(vsync_pulse_sys),
        .btn_play_pause(play_pause_pulse),
        .btn_restart(restart_pulse),
        .btn_step(1'b0),
        .loop_enable(1'b1),
        .total_frames(16'd0), // Free-running loop
        .stream_valid(playback_stream_valid),
        .stream_ready(playback_stream_ready),
        .stream_data(playback_stream_data),
        .fb_wr_en(fb_wr_en),
        .fb_wr_x(fb_wr_x),
        .fb_wr_y(fb_wr_y),
        .fb_wr_rgb565(fb_wr_rgb565),
        .fb_swap_buffers(fb_swap_buffers),
        .is_playing(is_playing),
        .current_frame_num(current_frame_num),
        .total_frames_decoded(total_frames_decoded),
        .fps_tick(fps_tick),
        .restart_stream(restart_stream_req)
    );

    // ========================================================================
    // 7. Double-Buffered Framebuffer (144 KB BRAM)
    // ========================================================================
    wire        fb_rd_en;
    wire [7:0]  fb_rd_x;
    wire [7:0]  fb_rd_y;
    wire [15:0] fb_rd_rgb565;

    framebuffer_double_buffer #(
        .FRAME_WIDTH(256),
        .FRAME_HEIGHT(144)
    ) u_framebuffer (
        .clk_wr(clk_sys),
        .rst_wr_n(rst_sys_n),
        .wr_en(fb_wr_en),
        .wr_x(fb_wr_x),
        .wr_y(fb_wr_y),
        .wr_rgb565(fb_wr_rgb565),
        .frame_write_done(fb_swap_buffers),
        .clk_pixel(clk_pixel),
        .rst_pixel_n(rst_pixel_n),
        .vsync_in(hdmi_vsync_raw),
        .rd_en(fb_rd_en),
        .rd_x(fb_rd_x),
        .rd_y(fb_rd_y),
        .rd_rgb565(fb_rd_rgb565),
        .current_write_bank(),
        .current_read_bank(),
        .total_frames_displayed()
    );

    // ========================================================================
    // 8. 5x Nearest-Neighbor Scaler (256x144 -> 1280x720)
    // ========================================================================
    wire [23:0] scaler_rgb888;
    wire        scaler_hsync;
    wire        scaler_vsync;
    wire        scaler_vde;

    scaler_5x u_scaler (
        .clk_pixel(clk_pixel),
        .rst_pixel_n(rst_pixel_n),
        .hdmi_pixel_x(hdmi_pixel_x),
        .hdmi_pixel_y(hdmi_pixel_y),
        .hdmi_hsync(hdmi_hsync_raw),
        .hdmi_vsync(hdmi_vsync_raw),
        .hdmi_vde(hdmi_vde_raw),
        .fb_rd_en(fb_rd_en),
        .fb_rd_x(fb_rd_x),
        .fb_rd_y(fb_rd_y),
        .fb_rd_rgb565(fb_rd_rgb565),
        .pixel_x_out(),
        .pixel_y_out(),
        .hsync_out(scaler_hsync),
        .vsync_out(scaler_vsync),
        .vde_out(scaler_vde),
        .rgb888_out(scaler_rgb888)
    );

    // ========================================================================
    // 9. HDMI 720p 60Hz Transmitter
    // ========================================================================
    wire [23:0] rgb_active;

`ifdef SYNTHESIS
    // SW0 = 0: Hardware Color Bars pattern mode (or fallback if no video uploaded yet)
    // SW0 = 1: Live MJPEG Playback mode
    wire hdmi_pattern_mode      = (sw[0] == 1'b0) || (!upload_success);
    wire [2:0] hdmi_pattern_sel = (sw[1] == 1'b1) ? 3'd1 : 3'd0;
`else
    wire hdmi_pattern_mode      = 1'b0;
    wire [2:0] hdmi_pattern_sel = 3'd0;
`endif

    hdmi_tx_top u_hdmi_tx (
        .clk_pixel(clk_pixel),
        .clk_pixel_5x(clk_pixel_5x),
        .rst_n(rst_pixel_n),
        .pattern_mode(hdmi_pattern_mode),
        .pattern_sel(hdmi_pattern_sel),
        .video_rgb_in(scaler_rgb888),
        .pixel_x(hdmi_pixel_x),
        .pixel_y(hdmi_pixel_y),
        .hsync(hdmi_hsync_raw),
        .vsync(hdmi_vsync_raw),
        .vde(hdmi_vde_raw),
        .frame_start(),
        .line_start(),
        .rgb_active(rgb_active),
        .hdmi_tx_clk_p(hdmi_tx_clk_p),
        .hdmi_tx_clk_n(hdmi_tx_clk_n),
        .hdmi_tx_data_p(hdmi_tx_data_p),
        .hdmi_tx_data_n(hdmi_tx_data_n)
    );

`ifndef SYNTHESIS
    assign dbg_pixel_x              = hdmi_pixel_x;
    assign dbg_pixel_y              = hdmi_pixel_y;
    assign dbg_hsync                = hdmi_hsync_raw;
    assign dbg_vsync                = hdmi_vsync_raw;
    assign dbg_vde                  = hdmi_vde_raw;
    assign dbg_rgb_active           = rgb_active;
    assign dbg_parser_state         = u_uploader.u_parser.state;
    assign dbg_fb_swap_buffers     = fb_swap_buffers;
    assign dbg_fb_wr_en            = fb_wr_en;
    assign dbg_current_frame       = current_frame_num;
    assign dbg_total_frames_decoded = total_frames_decoded;
    assign dbg_pb_state            = u_pb_reader.state;
`endif

    // ========================================================================
    // 10. Status LED Telemetry & Heartbeat Blinker
    // ========================================================================
    reg [25:0] heartbeat_cnt;
    initial heartbeat_cnt = 26'd0;
    always @(posedge clk_sys) begin
        heartbeat_cnt <= heartbeat_cnt + 1'b1;
    end
    wire heartbeat = heartbeat_cnt[25]; // ~1.5 Hz blinker on 100 MHz clock

    assign led[0]     = upload_active;
    assign led[1]     = upload_success;
    assign led[2]     = is_playing;
`ifdef SYNTHESIS
    assign led[3]     = mmcm_locked;              // Solid ON = MMCM 74.25/371.25 MHz clocks locked
`else
    assign led[3]     = !is_playing;
`endif
    assign led[7:4]   = current_frame_num[3:0];
    assign led[11:8]  = current_frame_num[7:4];
`ifdef SYNTHESIS
    assign led[14:12] = total_frames_decoded[2:0];
    assign led[15]    = heartbeat;                // 1.5 Hz blinker = 100 MHz clock & FPGA logic running
`else
    assign led[15:12] = total_frames_decoded[3:0];
`endif

endmodule
