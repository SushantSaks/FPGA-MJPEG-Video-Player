//-----------------------------------------------------------------------------
// File: bram_dual_port.v
// Description: Parameterized Simple Dual-Port Block RAM (Spartan-7 inferrable)
// Port A: Synchronous Write (clk_wr)
// Port B: Synchronous Read  (clk_rd)
// Standard: Verilog-2001
//-----------------------------------------------------------------------------

`timescale 1ns / 1ps

module bram_dual_port #(
    parameter integer DATA_WIDTH = 16,
    parameter integer ADDR_WIDTH = 17,
    parameter integer DEPTH      = 73728 // 2 banks * 256 * 144
)(
    // Port A (Write)
    input  wire                  clk_wr,
    input  wire                  we,
    input  wire [ADDR_WIDTH-1:0] addr_wr,
    input  wire [DATA_WIDTH-1:0] din,

    // Port B (Read)
    input  wire                  clk_rd,
    input  wire                  re,
    input  wire [ADDR_WIDTH-1:0] addr_rd,
    output reg  [DATA_WIDTH-1:0] dout
);

    // BRAM array declaration
    (* ram_style = "block" *)
    reg [DATA_WIDTH-1:0] ram [0:DEPTH-1];

    // Port A: Write
    always @(posedge clk_wr) begin
        if (we) begin
            if (addr_wr < DEPTH) begin
                ram[addr_wr] <= din;
            end
        end
    end

    // Port B: Read with registered output
    always @(posedge clk_rd) begin
        if (re) begin
            if (addr_rd < DEPTH) begin
                dout <= ram[addr_rd];
            end else begin
                dout <= {DATA_WIDTH{1'b0}};
            end
        end
    end

endmodule
