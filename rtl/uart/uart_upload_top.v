`timescale 1ns / 1ps
// ============================================================================
// Module: uart_upload_top
// Description: Top-level UART Upload Subsystem integrating uart_rx, uart_rx_fifo,
//              uart_tx, and uart_upload_parser.
// Standard: Verilog-2001
// ============================================================================

module uart_upload_top #(
    parameter integer CLK_FREQ_HZ     = 100_000_000,
    parameter integer BAUD_RATE       = 921_600,
    parameter [23:0]  VIDEO_BASE_ADDR = 24'h400000
) (
    input  wire        clk,
    input  wire        rst_n,

    // Physical UART Pins
    input  wire        uart_rx_pin,
    output wire        uart_tx_pin,

    // QSPI Controller Command Interface
    output wire [2:0]  qspi_cmd_op,
    output wire [23:0] qspi_cmd_addr,
    output wire [8:0]  qspi_cmd_byte_len,
    output wire        qspi_cmd_start,
    input  wire        qspi_cmd_busy,
    input  wire        qspi_cmd_done,
    input  wire [7:0]  flash_status_reg,

    // QSPI Controller Write Interface
    output wire [7:0]  qspi_wr_data,
    output wire        qspi_wr_valid,
    input  wire        qspi_wr_ready,

    // QSPI Controller Read Interface
    input  wire [7:0]  qspi_rd_data,
    input  wire        qspi_rd_valid,
    output wire        qspi_rd_ready,
    output wire        qspi_stream_mode,
    output wire        qspi_stream_stop,

    // Status to Video Playback Engine
    output wire [23:0] video_start_addr,
    output wire [31:0] video_file_size,
    output wire        upload_active,
    output wire        upload_done,
    output wire        upload_success
);

    wire [7:0]  rx_byte;
    wire        rx_valid;
    wire        rx_error;
    wire        fifo_full;
    wire [11:0] fifo_count;

    wire [7:0]  fifo_dout;
    wire        fifo_empty;
    wire        parser_rx_ready;
    wire        fifo_rd_en = !fifo_empty && parser_rx_ready;

    wire        tx_start;
    wire [7:0]  tx_data;
    wire        tx_busy;

    uart_rx #(
        .CLK_FREQ_HZ(CLK_FREQ_HZ),
        .BAUD_RATE(BAUD_RATE)
    ) u_rx (
        .clk(clk),
        .rst_n(rst_n),
        .rx_pin(uart_rx_pin),
        .rx_data(rx_byte),
        .rx_valid(rx_valid),
        .rx_error(rx_error)
    );

    uart_rx_fifo #(
        .DEPTH(2048)
    ) u_rx_fifo (
        .clk(clk),
        .rst_n(rst_n),
        .wr_en(rx_valid),
        .din(rx_byte),
        .full(fifo_full),
        .rd_en(fifo_rd_en),
        .dout(fifo_dout),
        .empty(fifo_empty),
        .count(fifo_count)
    );

    uart_tx #(
        .CLK_FREQ_HZ(CLK_FREQ_HZ),
        .BAUD_RATE(BAUD_RATE)
    ) u_tx (
        .clk(clk),
        .rst_n(rst_n),
        .tx_start(tx_start),
        .tx_data(tx_data),
        .tx_busy(tx_busy),
        .tx_pin(uart_tx_pin)
    );

    uart_upload_parser #(
        .VIDEO_BASE_ADDR(VIDEO_BASE_ADDR)
    ) u_parser (
        .clk(clk),
        .rst_n(rst_n),
        .rx_data(fifo_dout),
        .rx_valid(fifo_rd_en),
        .rx_ready(parser_rx_ready),
        .tx_start(tx_start),
        .tx_data(tx_data),
        .tx_busy(tx_busy),
        .qspi_cmd_op(qspi_cmd_op),
        .qspi_cmd_addr(qspi_cmd_addr),
        .qspi_cmd_byte_len(qspi_cmd_byte_len),
        .qspi_cmd_start(qspi_cmd_start),
        .qspi_cmd_busy(qspi_cmd_busy),
        .qspi_cmd_done(qspi_cmd_done),
        .flash_status_reg(flash_status_reg),
        .qspi_wr_data(qspi_wr_data),
        .qspi_wr_valid(qspi_wr_valid),
        .qspi_wr_ready(qspi_wr_ready),
        .qspi_rd_data(qspi_rd_data),
        .qspi_rd_valid(qspi_rd_valid),
        .qspi_rd_ready(qspi_rd_ready),
        .qspi_stream_mode(qspi_stream_mode),
        .qspi_stream_stop(qspi_stream_stop),
        .video_start_addr(video_start_addr),
        .video_file_size(video_file_size),
        .upload_active(upload_active),
        .upload_done(upload_done),
        .upload_success(upload_success)
    );

endmodule
