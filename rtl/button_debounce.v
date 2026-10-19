`timescale 1ns / 1ps
// ============================================================================
// Module: button_debounce
// Description: Glitch filter and single-cycle edge detector for pushbuttons.
// Standard: Verilog-2001
// ============================================================================

module button_debounce #(
    parameter integer CLK_FREQ_HZ = 100_000_000,
    parameter integer DEBOUNCE_MS = 10
) (
    input  wire  clk,
    input  wire  rst_n,
    input  wire  btn_in,
    output reg   btn_state,
    output reg   btn_pulse
);

    localparam integer CLK_CYCLES = (CLK_FREQ_HZ / 1000) * DEBOUNCE_MS;
    localparam integer CNT_WIDTH  = (CLK_CYCLES > 1) ? $clog2(CLK_CYCLES) : 1;

    reg [1:0]            sync_reg;
    reg [CNT_WIDTH-1:0]  cnt;
    reg                  btn_state_prev;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sync_reg       <= 2'b00;
            cnt            <= {CNT_WIDTH{1'b0}};
            btn_state      <= 1'b0;
            btn_state_prev <= 1'b0;
            btn_pulse      <= 1'b0;
        end else begin
            // 2-stage synchronizer
            sync_reg <= {sync_reg[0], btn_in};

            // Debounce counter
            if (sync_reg[1] != btn_state) begin
                if (cnt == CLK_CYCLES[CNT_WIDTH-1:0] - 1'b1) begin
                    btn_state <= sync_reg[1];
                    cnt       <= {CNT_WIDTH{1'b0}};
                end else begin
                    cnt <= cnt + 1'b1;
                end
            end else begin
                cnt <= {CNT_WIDTH{1'b0}};
            end

            // Rising-edge pulse
            btn_state_prev <= btn_state;
            btn_pulse      <= btn_state && !btn_state_prev;
        end
    end

endmodule
