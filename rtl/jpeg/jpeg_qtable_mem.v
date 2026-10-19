//-----------------------------------------------------------------------------
// File: jpeg_qtable_mem.v
// Description: Quantization Table Memory (Stores 2 x 64-byte Q-tables)
// Table 0: Luminance (Y)
// Table 1: Chrominance (Cb/Cr)
// Standard: Verilog-2001
//-----------------------------------------------------------------------------

`timescale 1ns / 1ps

module jpeg_qtable_mem (
    input  wire        clk,
    input  wire        rst_n,

    // Write interface (from DQT marker parser)
    input  wire        wr_en,
    input  wire        table_sel_wr, // 0 = Luma, 1 = Chroma
    input  wire [5:0]  addr_wr,      // 0..63
    input  wire [7:0]  q_data_wr,

    // Read interface (for dequantizer)
    input  wire        table_sel_rd,
    input  wire [5:0]  addr_rd,
    output wire [7:0]  q_data_rd,
    output wire [511:0] q_table_out
);

    // 2 tables of 64 bytes
    reg [7:0] q_table_0 [0:63];
    reg [7:0] q_table_1 [0:63];

    // Standard JPEG default tables as initialization fallback
    initial begin
        // Standard Luminance Q-table
        q_table_0[0]  = 8'd16; q_table_0[1]  = 8'd11; q_table_0[2]  = 8'd10; q_table_0[3]  = 8'd16;
        q_table_0[4]  = 8'd24; q_table_0[5]  = 8'd40; q_table_0[6]  = 8'd51; q_table_0[7]  = 8'd61;
        q_table_0[8]  = 8'd12; q_table_0[9]  = 8'd12; q_table_0[10] = 8'd14; q_table_0[11] = 8'd19;
        q_table_0[12] = 8'd26; q_table_0[13] = 8'd58; q_table_0[14] = 8'd60; q_table_0[15] = 8'd55;
        q_table_0[16] = 8'd14; q_table_0[17] = 8'd13; q_table_0[18] = 8'd16; q_table_0[19] = 8'd24;
        q_table_0[20] = 8'd40; q_table_0[21] = 8'd57; q_table_0[22] = 8'd69; q_table_0[23] = 8'd56;
        q_table_0[24] = 8'd14; q_table_0[25] = 8'd17; q_table_0[26] = 8'd22; q_table_0[27] = 8'd29;
        q_table_0[28] = 8'd51; q_table_0[29] = 8'd87; q_table_0[30] = 8'd80; q_table_0[31] = 8'd62;
        q_table_0[32] = 8'd18; q_table_0[33] = 8'd22; q_table_0[34] = 8'd37; q_table_0[35] = 8'd56;
        q_table_0[36] = 8'd68; q_table_0[37] = 8'd109;q_table_0[38] = 8'd103;q_table_0[39] = 8'd77;
        q_table_0[40] = 8'd24; q_table_0[41] = 8'd35; q_table_0[42] = 8'd55; q_table_0[43] = 8'd64;
        q_table_0[44] = 8'd81; q_table_0[45] = 8'd104;q_table_0[46] = 8'd113;q_table_0[47] = 8'd92;
        q_table_0[48] = 8'd49; q_table_0[49] = 8'd64; q_table_0[50] = 8'd78; q_table_0[51] = 8'd87;
        q_table_0[52] = 8'd103;q_table_0[53] = 8'd121;q_table_0[54] = 8'd120;q_table_0[55] = 8'd101;
        q_table_0[56] = 8'd72; q_table_0[57] = 8'd92; q_table_0[58] = 8'd95; q_table_0[59] = 8'd98;
        q_table_0[60] = 8'd112;q_table_0[61] = 8'd100;q_table_0[62] = 8'd103;q_table_0[63] = 8'd99;

        // Standard Chrominance Q-table
        q_table_1[0]  = 8'd17; q_table_1[1]  = 8'd18; q_table_1[2]  = 8'd24; q_table_1[3]  = 8'd47;
        q_table_1[4]  = 8'd99; q_table_1[5]  = 8'd99; q_table_1[6]  = 8'd99; q_table_1[7]  = 8'd99;
        q_table_1[8]  = 8'd18; q_table_1[9]  = 8'd21; q_table_1[10] = 8'd26; q_table_1[11] = 8'd66;
        q_table_1[12] = 8'd99; q_table_1[13] = 8'd99; q_table_1[14] = 8'd99; q_table_1[15] = 8'd99;
        q_table_1[16] = 8'd24; q_table_1[17] = 8'd26; q_table_1[18] = 8'd56; q_table_1[19] = 8'd99;
        q_table_1[20] = 8'd99; q_table_1[21] = 8'd99; q_table_1[22] = 8'd99; q_table_1[23] = 8'd99;
        q_table_1[24] = 8'd47; q_table_1[25] = 8'd66; q_table_1[26] = 8'd99; q_table_1[27] = 8'd99;
        q_table_1[28] = 8'd99; q_table_1[29] = 8'd99; q_table_1[30] = 8'd99; q_table_1[31] = 8'd99;
        q_table_1[32] = 8'd99; q_table_1[33] = 8'd99; q_table_1[34] = 8'd99; q_table_1[35] = 8'd99;
        q_table_1[36] = 8'd99; q_table_1[37] = 8'd99; q_table_1[38] = 8'd99; q_table_1[39] = 8'd99;
        q_table_1[40] = 8'd99; q_table_1[41] = 8'd99; q_table_1[42] = 8'd99; q_table_1[43] = 8'd99;
        q_table_1[44] = 8'd99; q_table_1[45] = 8'd99; q_table_1[46] = 8'd99; q_table_1[47] = 8'd99;
        q_table_1[48] = 8'd99; q_table_1[49] = 8'd99; q_table_1[50] = 8'd99; q_table_1[51] = 8'd99;
        q_table_1[52] = 8'd99; q_table_1[53] = 8'd99; q_table_1[54] = 8'd99; q_table_1[55] = 8'd99;
        q_table_1[56] = 8'd99; q_table_1[57] = 8'd99; q_table_1[58] = 8'd99; q_table_1[59] = 8'd99;
        q_table_1[60] = 8'd99; q_table_1[61] = 8'd99; q_table_1[62] = 8'd99; q_table_1[63] = 8'd99;
    end

    // Synchronous write
    always @(posedge clk) begin
        if (wr_en) begin
            if (!table_sel_wr)
                q_table_0[addr_wr] <= q_data_wr;
            else
                q_table_1[addr_wr] <= q_data_wr;
        end
    end

    // Combinational full-table read for parallel dequantization
    genvar q;
    generate
        for (q = 0; q < 64; q = q + 1) begin : gen_q_out
            assign q_table_out[q*8 +: 8] = !table_sel_rd ? q_table_0[q] : q_table_1[q];
        end
    endgenerate

    assign q_data_rd = !table_sel_rd ? q_table_0[addr_rd] : q_table_1[addr_rd];

endmodule
