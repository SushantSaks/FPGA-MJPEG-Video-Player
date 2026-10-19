`timescale 1ns / 1ps
// ============================================================================
// Module: uart_rx
// Description: Standard 8N1 UART Receiver with 2-stage synchronizer and 
//              midpoint bit sampling.
// Standard: Verilog-2001
// ============================================================================

module uart_rx #(
    parameter integer CLK_FREQ_HZ = 100_000_000,
    parameter integer BAUD_RATE   = 921_600
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       rx_pin,
    output reg  [7:0] rx_data,
    output reg        rx_valid,
    output reg        rx_error
);

    localparam integer CLKS_PER_BIT = CLK_FREQ_HZ / BAUD_RATE;
    localparam integer MIDPOINT     = CLKS_PER_BIT / 2;

    // Synchronize RX input to avoid metastability
    reg rx_sync1;
    reg rx_sync2;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_sync1 <= 1'b1;
            rx_sync2 <= 1'b1;
        end else begin
            rx_sync1 <= rx_pin;
            rx_sync2 <= rx_sync1;
        end
    end

    localparam [1:0] ST_IDLE  = 2'd0;
    localparam [1:0] ST_START = 2'd1;
    localparam [1:0] ST_DATA  = 2'd2;
    localparam [1:0] ST_STOP  = 2'd3;

    reg [1:0]   state;
    reg [15:0]  clk_cnt;
    reg [2:0]   bit_idx;
    reg [7:0]   shift_reg;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= ST_IDLE;
            clk_cnt   <= 16'd0;
            bit_idx   <= 3'd0;
            shift_reg <= 8'd0;
            rx_data   <= 8'd0;
            rx_valid  <= 1'b0;
            rx_error  <= 1'b0;
        end else begin
            rx_valid <= 1'b0;
            rx_error <= 1'b0;

            case (state)
                ST_IDLE: begin
                    clk_cnt <= 16'd0;
                    bit_idx <= 3'd0;
                    // Falling edge indicates potential start bit
                    if (rx_sync2 == 1'b0) begin
                        state <= ST_START;
                    end
                end

                ST_START: begin
                    if (clk_cnt == MIDPOINT[15:0]) begin
                        // Check that start bit is still low
                        if (rx_sync2 == 1'b0) begin
                            clk_cnt <= 16'd0;
                            state   <= ST_DATA;
                        end else begin
                            // False alarm / glitch
                            state <= ST_IDLE;
                        end
                    end else begin
                        clk_cnt <= clk_cnt + 16'd1;
                    end
                end

                ST_DATA: begin
                    if (clk_cnt == CLKS_PER_BIT[15:0] - 16'd1) begin
                        clk_cnt              <= 16'd0;
                        shift_reg[bit_idx]   <= rx_sync2;
                        if (bit_idx == 3'd7) begin
                            state <= ST_STOP;
                        end else begin
                            bit_idx <= bit_idx + 3'd1;
                        end
                    end else begin
                        clk_cnt <= clk_cnt + 16'd1;
                    end
                end

                ST_STOP: begin
                    if (clk_cnt == CLKS_PER_BIT[15:0] - 16'd1) begin
                        clk_cnt <= 16'd0;
                        state   <= ST_IDLE;
                        if (rx_sync2 == 1'b1) begin
                            // Valid stop bit: output byte
                            rx_data  <= shift_reg;
                            rx_valid <= 1'b1;
                        end else begin
                            // Framing error
                            rx_error <= 1'b1;
                        end
                    end else begin
                        clk_cnt <= clk_cnt + 16'd1;
                    end
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule
