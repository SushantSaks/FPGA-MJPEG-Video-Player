`timescale 1ns / 1ps
// ============================================================================
// Module: uart_tx
// Description: Standard 8N1 UART Transmitter with configurable baud rate.
// Standard: Verilog-2001
// ============================================================================

module uart_tx #(
    parameter integer CLK_FREQ_HZ = 100_000_000,
    parameter integer BAUD_RATE   = 921_600
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       tx_start,
    input  wire [7:0] tx_data,
    output reg        tx_busy,
    output reg        tx_pin
);

    localparam integer CLKS_PER_BIT = CLK_FREQ_HZ / BAUD_RATE;

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
            tx_busy   <= 1'b0;
            tx_pin    <= 1'b1;
        end else begin
            case (state)
                ST_IDLE: begin
                    clk_cnt <= 16'd0;
                    bit_idx <= 3'd0;
                    tx_pin  <= 1'b1;
                    if (tx_start) begin
                        shift_reg <= tx_data;
                        tx_busy   <= 1'b1;
                        tx_pin    <= 1'b0; // Start bit
                        state     <= ST_START;
                    end else begin
                        tx_busy <= 1'b0;
                    end
                end

                ST_START: begin
                    tx_pin <= 1'b0;
                    if (clk_cnt == CLKS_PER_BIT[15:0] - 16'd1) begin
                        clk_cnt <= 16'd0;
                        tx_pin  <= shift_reg[0];
                        bit_idx <= 3'd0;
                        state   <= ST_DATA;
                    end else begin
                        clk_cnt <= clk_cnt + 16'd1;
                    end
                end

                ST_DATA: begin
                    tx_pin <= shift_reg[bit_idx];
                    if (clk_cnt == CLKS_PER_BIT[15:0] - 16'd1) begin
                        clk_cnt <= 16'd0;
                        if (bit_idx == 3'd7) begin
                            tx_pin <= 1'b1; // Stop bit
                            state  <= ST_STOP;
                        end else begin
                            bit_idx <= bit_idx + 3'd1;
                        end
                    end else begin
                        clk_cnt <= clk_cnt + 16'd1;
                    end
                end

                ST_STOP: begin
                    tx_pin <= 1'b1;
                    if (clk_cnt == CLKS_PER_BIT[15:0] - 16'd1) begin
                        clk_cnt <= 16'd0;
                        tx_busy <= 1'b0;
                        state   <= ST_IDLE;
                    end else begin
                        clk_cnt <= clk_cnt + 16'd1;
                    end
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule
