`timescale 1ns / 1ps
// ============================================================================
// Module: qspi_playback_reader
// Description: Continuously streams MJPEG video from QSPI Flash starting at
//              video_base_addr into mjpeg_playback_top. Supports stream abort
//              and restart on loop or button press.
// Standard: Verilog-2001
// ============================================================================

module qspi_playback_reader #(
    parameter [23:0] VIDEO_BASE_ADDR = 24'h400000
) (
    input  wire        clk,
    input  wire        rst_n,

    // Enable from Top (high when NOT uploading)
    input  wire        enable,
    input  wire [23:0] video_start_addr,
    input  wire        restart_stream,

    // QSPI Controller Command Interface
    output wire [2:0]  qspi_cmd_op,
    output reg  [23:0] qspi_cmd_addr,
    output wire [8:0]  qspi_cmd_byte_len,
    output reg         qspi_cmd_start,
    input  wire        qspi_cmd_busy,
    input  wire        qspi_cmd_done,

    // QSPI Controller Streaming Read Interface
    input  wire [7:0]  qspi_rd_data,
    input  wire        qspi_rd_valid,
    output wire        qspi_rd_ready,
    output reg         qspi_stream_mode,
    output reg         qspi_stream_stop,

    // Downstream Stream to MJPEG Parser / Decoder
    output wire [7:0]  stream_data,
    output wire        stream_valid,
    input  wire        stream_ready
);

    localparam [2:0] OP_READ = 3'd0;

    localparam [1:0] ST_IDLE       = 2'd0;
    localparam [1:0] ST_START_READ = 2'd1;
    localparam [1:0] ST_STREAMING  = 2'd2;
    localparam [1:0] ST_STOPPING   = 2'd3;

    reg [1:0] state;

    assign qspi_cmd_op       = OP_READ;
    assign qspi_cmd_byte_len = 9'd0; // continuous stream mode
    assign qspi_rd_ready     = (state == ST_STREAMING) ? stream_ready : 1'b0;
    assign stream_data       = qspi_rd_data;
    assign stream_valid      = (state == ST_STREAMING) ? qspi_rd_valid : 1'b0;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state            <= ST_IDLE;
            qspi_cmd_addr    <= VIDEO_BASE_ADDR;
            qspi_cmd_start   <= 1'b0;
            qspi_stream_mode <= 1'b0;
            qspi_stream_stop <= 1'b0;
        end else begin
            qspi_cmd_start   <= 1'b0;
            qspi_stream_stop <= 1'b0;

            if (!enable) begin
                // Upload active: immediately halt playback reader
                if (state == ST_STREAMING) begin
                    qspi_stream_stop <= 1'b1;
                    state            <= ST_STOPPING;
                end else if (state == ST_STOPPING) begin
                    if (qspi_cmd_done || !qspi_cmd_busy) begin
                        qspi_stream_mode <= 1'b0;
                        state            <= ST_IDLE;
                    end
                end else begin
                    qspi_stream_mode <= 1'b0;
                    state            <= ST_IDLE;
                end
            end else begin
                case (state)
                    ST_IDLE: begin
                        qspi_stream_mode <= 1'b0;
                        if (!qspi_cmd_busy) begin
                            qspi_cmd_addr    <= (video_start_addr != 24'd0) ? video_start_addr : VIDEO_BASE_ADDR;
                            qspi_stream_mode <= 1'b1;
                            qspi_cmd_start   <= 1'b1;
                            state            <= ST_STREAMING;
                        end
                    end

                    ST_STREAMING: begin
                        if (restart_stream) begin
                            qspi_stream_stop <= 1'b1;
                            state            <= ST_STOPPING;
                        end
                    end

                    ST_STOPPING: begin
                        if (qspi_cmd_done || !qspi_cmd_busy) begin
                            qspi_stream_mode <= 1'b0;
                            state            <= ST_IDLE;
                        end
                    end

                    default: state <= ST_IDLE;
                endcase
            end
        end
    end

endmodule
