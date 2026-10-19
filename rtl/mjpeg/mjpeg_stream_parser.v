//-----------------------------------------------------------------------------
// File: mjpeg_stream_parser.v
// Description: Motion-JPEG stream parser and frame delimiter detector.
// Scans incoming byte stream for JPEG frame boundaries (SOI 0xFF 0xD8 and
// EOI 0xFF 0xD9), strips inter-frame padding, and streams individual frames
// to the hardware JPEG decoder with pacing control.
// Standard: Verilog-2001
//-----------------------------------------------------------------------------

`timescale 1ns / 1ps

module mjpeg_stream_parser (
    input  wire        clk,
    input  wire        rst_n,

    // Control from playback controller
    input  wire        start_frame,        // Pulse to initiate decoding next frame
    input  wire        abort_stream,       // Reset parser state to idle (e.g. on seek/restart)

    // Upstream byte stream (from QSPI Flash FIFO or UART buffer)
    input  wire        in_valid,
    output reg         in_ready,
    input  wire [7:0]  in_data,

    // Downstream stream to JPEG decoder
    output reg         out_valid,
    input  wire        out_ready,
    output reg  [7:0]  out_data,

    // Frame telemetry & status
    output wire        frame_active,       // High while streaming a JPEG frame
    output wire        frame_complete,     // 1-cycle pulse upon reaching EOI
    output wire [15:0] frame_count,        // Cumulative frames parsed
    output wire [19:0] frame_byte_len      // Length in bytes of the current frame
);

    localparam [1:0] ST_IDLE        = 2'd0;
    localparam [1:0] ST_SEEK_SOI    = 2'd1;
    localparam [1:0] ST_SEND_SOI_D8 = 2'd2;
    localparam [1:0] ST_STREAM_BODY = 2'd3;

    reg [1:0]  state;

    reg [15:0] frames_decoded;
    reg [19:0] byte_counter;
    reg        frame_done_pulse;
    reg [7:0]  prev_byte;

    assign frame_count    = frames_decoded;
    assign frame_byte_len = byte_counter;
    assign frame_complete = frame_done_pulse;
    assign frame_active   = (state == ST_SEND_SOI_D8) || (state == ST_STREAM_BODY);

    always @* begin
        out_valid = 1'b0;
        out_data  = in_data;
        in_ready  = 1'b0;

        case (state)
            ST_IDLE: begin
                out_valid = 1'b0;
                in_ready  = 1'b0;
            end

            ST_SEEK_SOI: begin
                if ((prev_byte == 8'hFF) && (in_data == 8'hD8)) begin
                    // Found SOI! Present 0xFF to output, hold in_data (0xD8)
                    out_valid = in_valid;
                    out_data  = 8'hFF;
                    in_ready  = 1'b0;
                end else begin
                    // Ready to accept & discard non-SOI byte
                    out_valid = 1'b0;
                    in_ready  = 1'b1;
                end
            end

            ST_SEND_SOI_D8: begin
                // Forward 0xD8 and consume from input
                out_valid = in_valid;
                out_data  = 8'hD8;
                in_ready  = out_ready;
            end

            ST_STREAM_BODY: begin
                // Direct pass-through
                out_valid = in_valid;
                out_data  = in_data;
                in_ready  = out_ready;
            end

            default: ;
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state            <= ST_IDLE;
            frames_decoded   <= 16'd0;
            byte_counter     <= 20'd0;
            frame_done_pulse <= 1'b0;
            prev_byte        <= 8'h00;
        end else if (abort_stream) begin
            state            <= ST_IDLE;
            byte_counter     <= 20'd0;
            frame_done_pulse <= 1'b0;
            prev_byte        <= 8'h00;
        end else begin
            frame_done_pulse <= 1'b0;

            case (state)
                ST_IDLE: begin
                    if (start_frame) begin
                        state        <= ST_SEEK_SOI;
                        byte_counter <= 20'd0;
                        prev_byte    <= 8'h00;
                    end
                end

                ST_SEEK_SOI: begin
                    if (in_valid && (prev_byte == 8'hFF) && (in_data == 8'hD8)) begin
                        if (out_ready) begin
                            // Successfully sent 0xFF
                            byte_counter <= byte_counter + 20'd1;
                            state        <= ST_SEND_SOI_D8;
                        end
                    end else if (in_valid) begin
                        prev_byte <= in_data;
                    end
                end

                ST_SEND_SOI_D8: begin
                    if (in_valid && out_ready) begin
                        // Successfully sent 0xD8
                        byte_counter <= byte_counter + 20'd1;
                        prev_byte    <= 8'hD8;
                        state        <= ST_STREAM_BODY;
                    end
                end

                ST_STREAM_BODY: begin
                    if (in_valid && out_ready) begin
                        byte_counter <= byte_counter + 20'd1;
                        prev_byte    <= in_data;

                        if ((prev_byte == 8'hFF) && (in_data == 8'hD9)) begin
                            // EOI reached (0xFF 0xD9)!
                            frames_decoded   <= frames_decoded + 16'd1;
                            frame_done_pulse <= 1'b1;
                            state            <= ST_IDLE;
                        end
                    end
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule
