//-----------------------------------------------------------------------------
// File: jpeg_decoder_top.v
// Description: JPEG Decoder Top Module with Stream Input FIFO & Framebuffer Output
// Connects to QSPI reader / UART input on stream side and framebuffer on output side.
// Standard: Verilog-2001
//-----------------------------------------------------------------------------

`timescale 1ns / 1ps

module jpeg_decoder_top (
    input  wire        clk,
    input  wire        rst_n,

    // Byte stream input (e.g. from QSPI FIFO or testbench)
    input  wire        stream_valid,
    output wire        stream_ready,
    input  wire [7:0]  stream_data,

    // Framebuffer write interface
    output wire        fb_wr_en,
    output wire [7:0]  fb_wr_x,
    output wire [7:0]  fb_wr_y,
    output wire [15:0] fb_wr_rgb565,
    output wire        fb_frame_done,

    // Status / telemetry
    output wire [3:0]  status_state,
    output wire [15:0] status_mcu_count
);

    // Simple FIFO buffer (64 bytes) for input stream smoothing
    reg [7:0] fifo_mem [0:63];
    reg [5:0] wr_ptr, rd_ptr;
    reg [6:0] fifo_count;

    wire fifo_empty = (fifo_count == 7'd0);
    wire fifo_full  = (fifo_count >= 7'd60);

    assign stream_ready = !fifo_full;

    // FIFO write
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr <= 6'd0;
        end else if (stream_valid && stream_ready) begin
            fifo_mem[wr_ptr] <= stream_data;
            wr_ptr           <= wr_ptr + 6'd1;
        end
    end

    // Core decoder signals
    wire        core_in_valid = !fifo_empty;
    wire        core_in_ready;
    wire [7:0]  core_in_data  = fifo_mem[rd_ptr];

    // FIFO read
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_ptr <= 6'd0;
        end else if (core_in_valid && core_in_ready) begin
            rd_ptr <= rd_ptr + 6'd1;
        end
    end

    // FIFO counter
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fifo_count <= 7'd0;
        end else begin
            case ({stream_valid && stream_ready, core_in_valid && core_in_ready})
                2'b10: fifo_count <= fifo_count + 7'd1;
                2'b01: fifo_count <= fifo_count - 7'd1;
                default: ;
            endcase
        end
    end

    // Instantiate core decoder
    jpeg_decoder_core u_core (
        .clk               (clk),
        .rst_n             (rst_n),
        .in_valid          (core_in_valid),
        .in_ready          (core_in_ready),
        .in_data           (core_in_data),

        .pixel_valid       (fb_wr_en),
        .pixel_x           (fb_wr_x),
        .pixel_y           (fb_wr_y),
        .pixel_rgb565      (fb_wr_rgb565),
        .frame_done        (fb_frame_done),

        .decoder_state     (status_state),
        .decoded_mcu_count (status_mcu_count)
    );

endmodule
