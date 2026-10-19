//-----------------------------------------------------------------------------
// File: mjpeg_playback_controller.v
// Description: Video Playback Pacing & Control Engine (15 FPS from 60 Hz HDMI)
// Synchronizes JPEG frame decoding with HDMI VSYNC intervals. At 60 Hz HDMI refresh,
// one new frame is decoded every 4 VSYNC cycles (60 / 4 = 15 FPS).
// Provides atomic double-buffer swapping, play/pause toggling, restart/looping,
// and single-frame step execution.
// Standard: Verilog-2001
//-----------------------------------------------------------------------------

`timescale 1ns / 1ps

module mjpeg_playback_controller (
    input  wire        clk,
    input  wire        rst_n,

    // Timing synchronization
    input  wire        vsync,              // 1-cycle pulse at 60 Hz from HDMI generator

    // User controls
    input  wire        btn_play_pause,     // Toggle play/pause pulse
    input  wire        btn_restart,        // Restart video from frame 0 pulse
    input  wire        btn_step,           // Single-step next frame pulse (in pause mode)
    input  wire        loop_enable,        // Enable auto-looping at end of stream

    // Stream / decoder status
    input  wire [15:0] total_frames,       // Total frames in the stream (e.g. 15)
    input  wire        decoder_frame_done, // Pulse from JPEG decoder when backbuffer is filled
    input  wire        parser_frame_done,  // Pulse from parser on EOI detection

    // Commands to parser, flash controller, and framebuffer
    output reg         start_frame_decode, // Pulse to start decoding next frame
    output reg         restart_stream,     // Pulse to rewind stream to start
    output reg         fb_swap_buffers,    // Pulse to atomic double-buffer swap (during VSYNC)

    // Playback status & telemetry
    output wire        is_playing,         // 1 = playing, 0 = paused
    output wire [15:0] current_frame_num,  // Currently displayed frame number (0..total_frames-1)
    output wire [15:0] decode_frame_num,   // Frame number currently being decoded
    output reg         fps_tick            // 1-cycle pulse at 15 Hz for FPS measurement
);

    // Playback state
    reg        playing;
    reg        step_requested;
    reg [1:0]  vsync_cnt;         // 0..3 (count 4 VSYNC pulses for 15 FPS)
    reg        backbuffer_ready;  // Set when decoder completes, cleared on buffer swap
    reg [15:0] disp_frame;
    reg [15:0] dec_frame;

    assign is_playing        = playing;
    assign current_frame_num = disp_frame;
    assign decode_frame_num  = dec_frame;

    // Edge detectors for button inputs
    reg btn_play_prev, btn_restart_prev, btn_step_prev, vsync_prev;
    wire play_pause_pulse = btn_play_pause && !btn_play_prev;
    wire restart_pulse    = btn_restart    && !btn_restart_prev;
    wire step_pulse       = btn_step       && !btn_step_prev;
    wire vsync_pulse      = vsync          && !vsync_prev;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            btn_play_prev    <= 1'b0;
            btn_restart_prev <= 1'b0;
            btn_step_prev    <= 1'b0;
            vsync_prev       <= 1'b0;
        end else begin
            btn_play_prev    <= btn_play_pause;
            btn_restart_prev <= btn_restart;
            btn_step_prev    <= btn_step;
            vsync_prev       <= vsync;
        end
    end

    // Main Control & Pacing FSM
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            playing            <= 1'b1; // Start playing by default
            step_requested     <= 1'b0;
            vsync_cnt          <= 2'd0;
            backbuffer_ready   <= 1'b0;
            disp_frame         <= 16'd0;
            dec_frame          <= 16'd0;
            start_frame_decode <= 1'b0;
            restart_stream     <= 1'b0;
            fb_swap_buffers    <= 1'b0;
            fps_tick           <= 1'b0;
        end else begin
            start_frame_decode <= 1'b0;
            restart_stream     <= 1'b0;
            fb_swap_buffers    <= 1'b0;
            fps_tick           <= 1'b0;

            // Handle Play/Pause toggle
            if (play_pause_pulse) begin
                playing <= ~playing;
            end

            // Handle Step pulse
            if (step_pulse && !playing) begin
                step_requested <= 1'b1;
            end

            // Handle Restart pulse
            if (restart_pulse) begin
                restart_stream   <= 1'b1;
                disp_frame       <= 16'd0;
                dec_frame        <= 16'd0;
                vsync_cnt        <= 2'd0;
                backbuffer_ready <= 1'b0;
                step_requested   <= 1'b0;
            end

            // Track decoder completion (framebuffer write complete)
            if (decoder_frame_done) begin
                backbuffer_ready <= 1'b1;
            end

            // VSYNC-synchronized pacing engine
            if (vsync_pulse) begin
                vsync_cnt <= vsync_cnt + 2'd1;

                // Cycle 0: Trigger next frame decode if playing or step requested
                if (vsync_cnt == 2'd0) begin
                    if (playing || step_requested) begin
                        start_frame_decode <= 1'b1;
                        step_requested     <= 1'b0;
                        dec_frame          <= (total_frames != 16'd0 && dec_frame + 16'd1 >= total_frames) ?
                                              (loop_enable ? 16'd0 : dec_frame) :
                                              (dec_frame + 16'd1);
                    end
                end

                // Cycle 3 (end of 4-frame period): Atomic double-buffer swap
                if (vsync_cnt == 2'd3) begin
                    if (backbuffer_ready) begin
                        fb_swap_buffers  <= 1'b1;
                        backbuffer_ready <= 1'b0;
                        fps_tick         <= 1'b1;

                        // Advance displayed frame counter
                        if (total_frames != 16'd0 && disp_frame + 16'd1 >= total_frames) begin
                            if (loop_enable) begin
                                disp_frame     <= 16'd0;
                                restart_stream <= 1'b1;
                            end else begin
                                playing <= 1'b0; // Pause at end of video
                            end
                        end else begin
                            disp_frame <= disp_frame + 16'd1;
                        end
                    end
                end
            end
        end
    end

endmodule
