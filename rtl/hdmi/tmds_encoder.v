//-----------------------------------------------------------------------------
// File: tmds_encoder.v
// Description: Standard DVI 1.0 TMDS 8b/10b Encoder
// Converts 8-bit color data and 2-bit control inputs into 10-bit TMDS symbol.
// Standard: Verilog-2001
//-----------------------------------------------------------------------------

`timescale 1ns / 1ps

module tmds_encoder (
    input  wire       clk_pixel,
    input  wire       rst_n,
    input  wire [7:0] data_in,
    input  wire [1:0] ctrl_in, // c0, c1 (e.g. hsync, vsync for Channel 0)
    input  wire       vde,

    output reg  [9:0] tmds_out
);

    // Step 1: Count ones in data_in
    wire [3:0] ones_data = {3'd0, data_in[0]} + {3'd0, data_in[1]} + 
                           {3'd0, data_in[2]} + {3'd0, data_in[3]} +
                           {3'd0, data_in[4]} + {3'd0, data_in[5]} + 
                           {3'd0, data_in[6]} + {3'd0, data_in[7]};

    // Step 2: Minimize transitions using XOR or XNOR
    wire use_xnor = (ones_data > 4'd4) || ((ones_data == 4'd4) && (data_in[0] == 1'b0));

    reg [8:0] q_m;
    always @* begin
        q_m[0] = data_in[0];
        if (use_xnor) begin
            q_m[1] = q_m[0] ~^ data_in[1];
            q_m[2] = q_m[1] ~^ data_in[2];
            q_m[3] = q_m[2] ~^ data_in[3];
            q_m[4] = q_m[3] ~^ data_in[4];
            q_m[5] = q_m[4] ~^ data_in[5];
            q_m[6] = q_m[5] ~^ data_in[6];
            q_m[7] = q_m[6] ~^ data_in[7];
            q_m[8] = 1'b0;
        end else begin
            q_m[1] = q_m[0] ^ data_in[1];
            q_m[2] = q_m[1] ^ data_in[2];
            q_m[3] = q_m[2] ^ data_in[3];
            q_m[4] = q_m[3] ^ data_in[4];
            q_m[5] = q_m[4] ^ data_in[5];
            q_m[6] = q_m[5] ^ data_in[6];
            q_m[7] = q_m[6] ^ data_in[7];
            q_m[8] = 1'b1;
        end
    end

    // Number of ones/zeros in q_m[7:0]
    wire [3:0] ones_qm  = {3'd0, q_m[0]} + {3'd0, q_m[1]} + {3'd0, q_m[2]} + {3'd0, q_m[3]} +
                          {3'd0, q_m[4]} + {3'd0, q_m[5]} + {3'd0, q_m[6]} + {3'd0, q_m[7]};
    wire [3:0] zeros_qm = 4'd8 - ones_qm;

    // Disparity register (signed 5-bit)
    reg signed [4:0] disparity;

    wire signed [4:0] diff_ones_zeros = $signed({1'b0, ones_qm}) - $signed({1'b0, zeros_qm});
    wire signed [4:0] diff_zeros_ones = $signed({1'b0, zeros_qm}) - $signed({1'b0, ones_qm});

    always @(posedge clk_pixel or negedge rst_n) begin
        if (!rst_n) begin
            disparity <= 5'sd0;
            tmds_out  <= 10'b1101010100;
        end else if (!vde) begin
            disparity <= 5'sd0;
            case (ctrl_in)
                2'b00:   tmds_out <= 10'b1101010100;
                2'b01:   tmds_out <= 10'b0010101011;
                2'b10:   tmds_out <= 10'b0101010100;
                default: tmds_out <= 10'b1010101011;
            endcase
        end else begin
            if (disparity == 5'sd0 || ones_qm == zeros_qm) begin
                tmds_out[9]   <= ~q_m[8];
                tmds_out[8]   <= q_m[8];
                tmds_out[7:0] <= (q_m[8]) ? q_m[7:0] : ~q_m[7:0];

                if (!q_m[8])
                    disparity <= disparity + diff_zeros_ones;
                else
                    disparity <= disparity + diff_ones_zeros;
            end else begin
                if ((disparity > 5'sd0 && ones_qm > zeros_qm) ||
                    (disparity < 5'sd0 && zeros_qm > ones_qm)) begin
                    tmds_out[9]   <= 1'b1;
                    tmds_out[8]   <= q_m[8];
                    tmds_out[7:0] <= ~q_m[7:0];
                    disparity     <= disparity + $signed({3'd0, q_m[8], 1'b0}) + diff_zeros_ones;
                end else begin
                    tmds_out[9]   <= 1'b0;
                    tmds_out[8]   <= q_m[8];
                    tmds_out[7:0] <= q_m[7:0];
                    disparity     <= disparity - $signed({3'd0, ~q_m[8], 1'b0}) + diff_ones_zeros;
                end
            end
        end
    end

endmodule
