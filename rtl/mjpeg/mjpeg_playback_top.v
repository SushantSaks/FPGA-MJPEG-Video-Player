//-----------------------------------------------------------------------------
// File: mjpeg_playback_top.v
// Description: Integrated MJPEG Playback Subsystem
// Connects stream parser, playback controller, and JPEG decoder core.
// Interfaces upstream with Flash/UART stream buffer and downstream with
// dual-ported framebuffer and HDMI timing sync.
// Standard: Verilog-2001
//-----------------------------------------------------------------------------

`timescale 1ns / 1ps

module mjpeg_playback_top (
    input  wire        clk,
    input  wire        rst_n,

    // Timing sync from HDMI subsystem
    input  wire        vsync,              // 60 Hz VSYNC pulse

    // Control pushbuttons
    input  wire        btn_play_pause,
    input  wire        btn_restart,
    input  wire        btn_step,
    input  wire        loop_enable,
    input  wire [15:0] total_frames,

    // Incoming byte stream (from QSPI Flash or memory FIFO)
    input  wire        stream_valid,
    output wire        stream_ready,
    input  wire [7:0]  stream_data,

    // Framebuffer write interface
    output wire        fb_wr_en,
    output wire [7:0]  fb_wr_x,
    output wire [7:0]  fb_wr_y,
    output wire [15:0] fb_wr_rgb565,
    output wire        fb_swap_buffers,

    // Playback telemetry
    output wire        is_playing,
    output wire [15:0] current_frame_num,
    output wire [15:0] total_frames_decoded,
    output wire        fps_tick,
    output wire        restart_stream
);

    // Internal interconnect wires
    wire start_decode;
    wire dec_restart;
    wire parser_frame_done;
    wire decoder_frame_done;

    assign restart_stream = dec_restart;

    // Parser to decoder stream
    wire        p2d_valid;
    wire        p2d_ready;
    wire [7:0]  p2d_data;

    wire        parser_active;
    wire [19:0] parser_byte_len;

    // Instantiate Playback Controller
    mjpeg_playback_controller u_ctrl (
        .clk                (clk),
        .rst_n              (rst_n),
        .vsync              (vsync),
        .btn_play_pause     (btn_play_pause),
        .btn_restart        (btn_restart),
        .btn_step           (btn_step),
        .loop_enable        (loop_enable),
        .total_frames       (total_frames),
        .decoder_frame_done (decoder_frame_done),
        .parser_frame_done  (parser_frame_done),
        .start_frame_decode (start_decode),
        .restart_stream     (dec_restart),
        .fb_swap_buffers    (fb_swap_buffers),
        .is_playing         (is_playing),
        .current_frame_num  (current_frame_num),
        .decode_frame_num   (),
        .fps_tick           (fps_tick)
    );

    // Instantiate Stream Parser
    mjpeg_stream_parser u_parser (
        .clk             (clk),
        .rst_n           (rst_n),
        .start_frame     (start_decode),
        .abort_stream    (dec_restart),
        .in_valid        (stream_valid),
        .in_ready        (stream_ready),
        .in_data         (stream_data),
        .out_valid       (p2d_valid),
        .out_ready       (p2d_ready),
        .out_data        (p2d_data),
        .frame_active    (parser_active),
        .frame_complete  (parser_frame_done),
        .frame_count     (total_frames_decoded),
        .frame_byte_len  (parser_byte_len)
    );

    // Instantiate Hardware JPEG Decoder
    jpeg_decoder_top u_decoder (
        .clk               (clk),
        .rst_n             (rst_n && !dec_restart),
        .stream_valid      (p2d_valid),
        .stream_ready      (p2d_ready),
        .stream_data       (p2d_data),
        .fb_wr_en          (fb_wr_en),
        .fb_wr_x           (fb_wr_x),
        .fb_wr_y           (fb_wr_y),
        .fb_wr_rgb565      (fb_wr_rgb565),
        .fb_frame_done     (decoder_frame_done),
        .status_state      (),
        .status_mcu_count  ()
    );

endmodule
