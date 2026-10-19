//-----------------------------------------------------------------------------
// File: jpeg_huffman_lut.sv
// Description: Synthesizable Huffman Variable-Length Decoder (Annex K compliant)
// Single-cycle prefix lookup for standard JPEG baseline streams.
//-----------------------------------------------------------------------------

`timescale 1ns / 1ps

// Standard: Verilog-2001

module jpeg_huffman_lut (
    input  wire        is_chroma,     // 0 = Luma, 1 = Chroma
    input  wire        is_ac,         // 0 = DC, 1 = AC
    input  wire [15:0] bit_window,    // Current top 16 bits of bitstream

    output reg  [4:0]  code_len,      // Number of bits to consume (1..16)
    output reg  [7:0]  symbol         // Decoded symbol
);

    always @* begin
        code_len = 5'd1;
        symbol   = 8'h00;

        case ({is_chroma, is_ac})
            2'b00: begin // DC Luminance
                casez (bit_window[15:0])
    // Table: DC_Luma
            16'b00??????????????: begin code_len = 5'd2; symbol = 8'h00; end
            16'b010?????????????: begin code_len = 5'd3; symbol = 8'h01; end
            16'b011?????????????: begin code_len = 5'd3; symbol = 8'h02; end
            16'b100?????????????: begin code_len = 5'd3; symbol = 8'h03; end
            16'b101?????????????: begin code_len = 5'd3; symbol = 8'h04; end
            16'b110?????????????: begin code_len = 5'd3; symbol = 8'h05; end
            16'b1110????????????: begin code_len = 5'd4; symbol = 8'h06; end
            16'b11110???????????: begin code_len = 5'd5; symbol = 8'h07; end
            16'b111110??????????: begin code_len = 5'd6; symbol = 8'h08; end
            16'b1111110?????????: begin code_len = 5'd7; symbol = 8'h09; end
            16'b11111110????????: begin code_len = 5'd8; symbol = 8'h0A; end
            16'b111111110???????: begin code_len = 5'd9; symbol = 8'h0B; end
                    default: begin code_len = 5'd2; symbol = 8'h00; end
                endcase
            end

            2'b10: begin // DC Chrominance
                casez (bit_window[15:0])
    // Table: DC_Chroma
            16'b00??????????????: begin code_len = 5'd2; symbol = 8'h00; end
            16'b01??????????????: begin code_len = 5'd2; symbol = 8'h01; end
            16'b10??????????????: begin code_len = 5'd2; symbol = 8'h02; end
            16'b110?????????????: begin code_len = 5'd3; symbol = 8'h03; end
            16'b1110????????????: begin code_len = 5'd4; symbol = 8'h04; end
            16'b11110???????????: begin code_len = 5'd5; symbol = 8'h05; end
            16'b111110??????????: begin code_len = 5'd6; symbol = 8'h06; end
            16'b1111110?????????: begin code_len = 5'd7; symbol = 8'h07; end
            16'b11111110????????: begin code_len = 5'd8; symbol = 8'h08; end
            16'b111111110???????: begin code_len = 5'd9; symbol = 8'h09; end
            16'b1111111110??????: begin code_len = 5'd10; symbol = 8'h0A; end
            16'b11111111110?????: begin code_len = 5'd11; symbol = 8'h0B; end
                    default: begin code_len = 5'd2; symbol = 8'h00; end
                endcase
            end

            2'b01: begin // AC Luminance
                casez (bit_window[15:0])
    // Table: AC_Luma
            16'b00??????????????: begin code_len = 5'd2; symbol = 8'h01; end
            16'b01??????????????: begin code_len = 5'd2; symbol = 8'h02; end
            16'b100?????????????: begin code_len = 5'd3; symbol = 8'h03; end
            16'b1010????????????: begin code_len = 5'd4; symbol = 8'h00; end
            16'b1011????????????: begin code_len = 5'd4; symbol = 8'h04; end
            16'b1100????????????: begin code_len = 5'd4; symbol = 8'h11; end
            16'b11010???????????: begin code_len = 5'd5; symbol = 8'h05; end
            16'b11011???????????: begin code_len = 5'd5; symbol = 8'h12; end
            16'b11100???????????: begin code_len = 5'd5; symbol = 8'h21; end
            16'b111010??????????: begin code_len = 5'd6; symbol = 8'h31; end
            16'b111011??????????: begin code_len = 5'd6; symbol = 8'h41; end
            16'b1111000?????????: begin code_len = 5'd7; symbol = 8'h06; end
            16'b1111001?????????: begin code_len = 5'd7; symbol = 8'h13; end
            16'b1111010?????????: begin code_len = 5'd7; symbol = 8'h51; end
            16'b1111011?????????: begin code_len = 5'd7; symbol = 8'h61; end
            16'b11111000????????: begin code_len = 5'd8; symbol = 8'h07; end
            16'b11111001????????: begin code_len = 5'd8; symbol = 8'h22; end
            16'b11111010????????: begin code_len = 5'd8; symbol = 8'h71; end
            16'b111110110???????: begin code_len = 5'd9; symbol = 8'h14; end
            16'b111110111???????: begin code_len = 5'd9; symbol = 8'h32; end
            16'b111111000???????: begin code_len = 5'd9; symbol = 8'h81; end
            16'b111111001???????: begin code_len = 5'd9; symbol = 8'h91; end
            16'b111111010???????: begin code_len = 5'd9; symbol = 8'hA1; end
            16'b1111110110??????: begin code_len = 5'd10; symbol = 8'h08; end
            16'b1111110111??????: begin code_len = 5'd10; symbol = 8'h23; end
            16'b1111111000??????: begin code_len = 5'd10; symbol = 8'h42; end
            16'b1111111001??????: begin code_len = 5'd10; symbol = 8'hB1; end
            16'b1111111010??????: begin code_len = 5'd10; symbol = 8'hC1; end
            16'b11111110110?????: begin code_len = 5'd11; symbol = 8'h15; end
            16'b11111110111?????: begin code_len = 5'd11; symbol = 8'h52; end
            16'b11111111000?????: begin code_len = 5'd11; symbol = 8'hD1; end
            16'b11111111001?????: begin code_len = 5'd11; symbol = 8'hF0; end
            16'b111111110100????: begin code_len = 5'd12; symbol = 8'h24; end
            16'b111111110101????: begin code_len = 5'd12; symbol = 8'h33; end
            16'b111111110110????: begin code_len = 5'd12; symbol = 8'h62; end
            16'b111111110111????: begin code_len = 5'd12; symbol = 8'h72; end
            16'b111111111000000?: begin code_len = 5'd15; symbol = 8'h82; end
            16'b1111111110000010: begin code_len = 5'd16; symbol = 8'h09; end
            16'b1111111110000011: begin code_len = 5'd16; symbol = 8'h0A; end
            16'b1111111110000100: begin code_len = 5'd16; symbol = 8'h16; end
            16'b1111111110000101: begin code_len = 5'd16; symbol = 8'h17; end
            16'b1111111110000110: begin code_len = 5'd16; symbol = 8'h18; end
            16'b1111111110000111: begin code_len = 5'd16; symbol = 8'h19; end
            16'b1111111110001000: begin code_len = 5'd16; symbol = 8'h1A; end
            16'b1111111110001001: begin code_len = 5'd16; symbol = 8'h25; end
            16'b1111111110001010: begin code_len = 5'd16; symbol = 8'h26; end
            16'b1111111110001011: begin code_len = 5'd16; symbol = 8'h27; end
            16'b1111111110001100: begin code_len = 5'd16; symbol = 8'h28; end
            16'b1111111110001101: begin code_len = 5'd16; symbol = 8'h29; end
            16'b1111111110001110: begin code_len = 5'd16; symbol = 8'h2A; end
            16'b1111111110001111: begin code_len = 5'd16; symbol = 8'h34; end
            16'b1111111110010000: begin code_len = 5'd16; symbol = 8'h35; end
            16'b1111111110010001: begin code_len = 5'd16; symbol = 8'h36; end
            16'b1111111110010010: begin code_len = 5'd16; symbol = 8'h37; end
            16'b1111111110010011: begin code_len = 5'd16; symbol = 8'h38; end
            16'b1111111110010100: begin code_len = 5'd16; symbol = 8'h39; end
            16'b1111111110010101: begin code_len = 5'd16; symbol = 8'h3A; end
            16'b1111111110010110: begin code_len = 5'd16; symbol = 8'h43; end
            16'b1111111110010111: begin code_len = 5'd16; symbol = 8'h44; end
            16'b1111111110011000: begin code_len = 5'd16; symbol = 8'h45; end
            16'b1111111110011001: begin code_len = 5'd16; symbol = 8'h46; end
            16'b1111111110011010: begin code_len = 5'd16; symbol = 8'h47; end
            16'b1111111110011011: begin code_len = 5'd16; symbol = 8'h48; end
            16'b1111111110011100: begin code_len = 5'd16; symbol = 8'h49; end
            16'b1111111110011101: begin code_len = 5'd16; symbol = 8'h4A; end
            16'b1111111110011110: begin code_len = 5'd16; symbol = 8'h53; end
            16'b1111111110011111: begin code_len = 5'd16; symbol = 8'h54; end
            16'b1111111110100000: begin code_len = 5'd16; symbol = 8'h55; end
            16'b1111111110100001: begin code_len = 5'd16; symbol = 8'h56; end
            16'b1111111110100010: begin code_len = 5'd16; symbol = 8'h57; end
            16'b1111111110100011: begin code_len = 5'd16; symbol = 8'h58; end
            16'b1111111110100100: begin code_len = 5'd16; symbol = 8'h59; end
            16'b1111111110100101: begin code_len = 5'd16; symbol = 8'h5A; end
            16'b1111111110100110: begin code_len = 5'd16; symbol = 8'h63; end
            16'b1111111110100111: begin code_len = 5'd16; symbol = 8'h64; end
            16'b1111111110101000: begin code_len = 5'd16; symbol = 8'h65; end
            16'b1111111110101001: begin code_len = 5'd16; symbol = 8'h66; end
            16'b1111111110101010: begin code_len = 5'd16; symbol = 8'h67; end
            16'b1111111110101011: begin code_len = 5'd16; symbol = 8'h68; end
            16'b1111111110101100: begin code_len = 5'd16; symbol = 8'h69; end
            16'b1111111110101101: begin code_len = 5'd16; symbol = 8'h6A; end
            16'b1111111110101110: begin code_len = 5'd16; symbol = 8'h73; end
            16'b1111111110101111: begin code_len = 5'd16; symbol = 8'h74; end
            16'b1111111110110000: begin code_len = 5'd16; symbol = 8'h75; end
            16'b1111111110110001: begin code_len = 5'd16; symbol = 8'h76; end
            16'b1111111110110010: begin code_len = 5'd16; symbol = 8'h77; end
            16'b1111111110110011: begin code_len = 5'd16; symbol = 8'h78; end
            16'b1111111110110100: begin code_len = 5'd16; symbol = 8'h79; end
            16'b1111111110110101: begin code_len = 5'd16; symbol = 8'h7A; end
            16'b1111111110110110: begin code_len = 5'd16; symbol = 8'h83; end
            16'b1111111110110111: begin code_len = 5'd16; symbol = 8'h84; end
            16'b1111111110111000: begin code_len = 5'd16; symbol = 8'h85; end
            16'b1111111110111001: begin code_len = 5'd16; symbol = 8'h86; end
            16'b1111111110111010: begin code_len = 5'd16; symbol = 8'h87; end
            16'b1111111110111011: begin code_len = 5'd16; symbol = 8'h88; end
            16'b1111111110111100: begin code_len = 5'd16; symbol = 8'h89; end
            16'b1111111110111101: begin code_len = 5'd16; symbol = 8'h8A; end
            16'b1111111110111110: begin code_len = 5'd16; symbol = 8'h92; end
            16'b1111111110111111: begin code_len = 5'd16; symbol = 8'h93; end
            16'b1111111111000000: begin code_len = 5'd16; symbol = 8'h94; end
            16'b1111111111000001: begin code_len = 5'd16; symbol = 8'h95; end
            16'b1111111111000010: begin code_len = 5'd16; symbol = 8'h96; end
            16'b1111111111000011: begin code_len = 5'd16; symbol = 8'h97; end
            16'b1111111111000100: begin code_len = 5'd16; symbol = 8'h98; end
            16'b1111111111000101: begin code_len = 5'd16; symbol = 8'h99; end
            16'b1111111111000110: begin code_len = 5'd16; symbol = 8'h9A; end
            16'b1111111111000111: begin code_len = 5'd16; symbol = 8'hA2; end
            16'b1111111111001000: begin code_len = 5'd16; symbol = 8'hA3; end
            16'b1111111111001001: begin code_len = 5'd16; symbol = 8'hA4; end
            16'b1111111111001010: begin code_len = 5'd16; symbol = 8'hA5; end
            16'b1111111111001011: begin code_len = 5'd16; symbol = 8'hA6; end
            16'b1111111111001100: begin code_len = 5'd16; symbol = 8'hA7; end
            16'b1111111111001101: begin code_len = 5'd16; symbol = 8'hA8; end
            16'b1111111111001110: begin code_len = 5'd16; symbol = 8'hA9; end
            16'b1111111111001111: begin code_len = 5'd16; symbol = 8'hAA; end
            16'b1111111111010000: begin code_len = 5'd16; symbol = 8'hB2; end
            16'b1111111111010001: begin code_len = 5'd16; symbol = 8'hB3; end
            16'b1111111111010010: begin code_len = 5'd16; symbol = 8'hB4; end
            16'b1111111111010011: begin code_len = 5'd16; symbol = 8'hB5; end
            16'b1111111111010100: begin code_len = 5'd16; symbol = 8'hB6; end
            16'b1111111111010101: begin code_len = 5'd16; symbol = 8'hB7; end
            16'b1111111111010110: begin code_len = 5'd16; symbol = 8'hB8; end
            16'b1111111111010111: begin code_len = 5'd16; symbol = 8'hB9; end
            16'b1111111111011000: begin code_len = 5'd16; symbol = 8'hBA; end
            16'b1111111111011001: begin code_len = 5'd16; symbol = 8'hC2; end
            16'b1111111111011010: begin code_len = 5'd16; symbol = 8'hC3; end
            16'b1111111111011011: begin code_len = 5'd16; symbol = 8'hC4; end
            16'b1111111111011100: begin code_len = 5'd16; symbol = 8'hC5; end
            16'b1111111111011101: begin code_len = 5'd16; symbol = 8'hC6; end
            16'b1111111111011110: begin code_len = 5'd16; symbol = 8'hC7; end
            16'b1111111111011111: begin code_len = 5'd16; symbol = 8'hC8; end
            16'b1111111111100000: begin code_len = 5'd16; symbol = 8'hC9; end
            16'b1111111111100001: begin code_len = 5'd16; symbol = 8'hCA; end
            16'b1111111111100010: begin code_len = 5'd16; symbol = 8'hD2; end
            16'b1111111111100011: begin code_len = 5'd16; symbol = 8'hD3; end
            16'b1111111111100100: begin code_len = 5'd16; symbol = 8'hD4; end
            16'b1111111111100101: begin code_len = 5'd16; symbol = 8'hD5; end
            16'b1111111111100110: begin code_len = 5'd16; symbol = 8'hD6; end
            16'b1111111111100111: begin code_len = 5'd16; symbol = 8'hD7; end
            16'b1111111111101000: begin code_len = 5'd16; symbol = 8'hD8; end
            16'b1111111111101001: begin code_len = 5'd16; symbol = 8'hD9; end
            16'b1111111111101010: begin code_len = 5'd16; symbol = 8'hDA; end
            16'b1111111111101011: begin code_len = 5'd16; symbol = 8'hE1; end
            16'b1111111111101100: begin code_len = 5'd16; symbol = 8'hE2; end
            16'b1111111111101101: begin code_len = 5'd16; symbol = 8'hE3; end
            16'b1111111111101110: begin code_len = 5'd16; symbol = 8'hE4; end
            16'b1111111111101111: begin code_len = 5'd16; symbol = 8'hE5; end
            16'b1111111111110000: begin code_len = 5'd16; symbol = 8'hE6; end
            16'b1111111111110001: begin code_len = 5'd16; symbol = 8'hE7; end
            16'b1111111111110010: begin code_len = 5'd16; symbol = 8'hE8; end
            16'b1111111111110011: begin code_len = 5'd16; symbol = 8'hE9; end
            16'b1111111111110100: begin code_len = 5'd16; symbol = 8'hEA; end
            16'b1111111111110101: begin code_len = 5'd16; symbol = 8'hF1; end
            16'b1111111111110110: begin code_len = 5'd16; symbol = 8'hF2; end
            16'b1111111111110111: begin code_len = 5'd16; symbol = 8'hF3; end
            16'b1111111111111000: begin code_len = 5'd16; symbol = 8'hF4; end
            16'b1111111111111001: begin code_len = 5'd16; symbol = 8'hF5; end
            16'b1111111111111010: begin code_len = 5'd16; symbol = 8'hF6; end
            16'b1111111111111011: begin code_len = 5'd16; symbol = 8'hF7; end
            16'b1111111111111100: begin code_len = 5'd16; symbol = 8'hF8; end
            16'b1111111111111101: begin code_len = 5'd16; symbol = 8'hF9; end
            16'b1111111111111110: begin code_len = 5'd16; symbol = 8'hFA; end
                    default: begin code_len = 5'd4; symbol = 8'h00; end // fallback EOB
                endcase
            end

            default: begin // 2'b11: AC Chrominance
                casez (bit_window[15:0])
    // Table: AC_Chroma
            16'b00??????????????: begin code_len = 5'd2; symbol = 8'h00; end
            16'b01??????????????: begin code_len = 5'd2; symbol = 8'h01; end
            16'b100?????????????: begin code_len = 5'd3; symbol = 8'h02; end
            16'b1010????????????: begin code_len = 5'd4; symbol = 8'h03; end
            16'b1011????????????: begin code_len = 5'd4; symbol = 8'h11; end
            16'b11000???????????: begin code_len = 5'd5; symbol = 8'h04; end
            16'b11001???????????: begin code_len = 5'd5; symbol = 8'h05; end
            16'b11010???????????: begin code_len = 5'd5; symbol = 8'h21; end
            16'b11011???????????: begin code_len = 5'd5; symbol = 8'h31; end
            16'b111000??????????: begin code_len = 5'd6; symbol = 8'h06; end
            16'b111001??????????: begin code_len = 5'd6; symbol = 8'h12; end
            16'b111010??????????: begin code_len = 5'd6; symbol = 8'h41; end
            16'b111011??????????: begin code_len = 5'd6; symbol = 8'h51; end
            16'b1111000?????????: begin code_len = 5'd7; symbol = 8'h07; end
            16'b1111001?????????: begin code_len = 5'd7; symbol = 8'h61; end
            16'b1111010?????????: begin code_len = 5'd7; symbol = 8'h71; end
            16'b11110110????????: begin code_len = 5'd8; symbol = 8'h13; end
            16'b11110111????????: begin code_len = 5'd8; symbol = 8'h22; end
            16'b11111000????????: begin code_len = 5'd8; symbol = 8'h32; end
            16'b11111001????????: begin code_len = 5'd8; symbol = 8'h81; end
            16'b111110100???????: begin code_len = 5'd9; symbol = 8'h08; end
            16'b111110101???????: begin code_len = 5'd9; symbol = 8'h14; end
            16'b111110110???????: begin code_len = 5'd9; symbol = 8'h42; end
            16'b111110111???????: begin code_len = 5'd9; symbol = 8'h91; end
            16'b111111000???????: begin code_len = 5'd9; symbol = 8'hA1; end
            16'b111111001???????: begin code_len = 5'd9; symbol = 8'hB1; end
            16'b111111010???????: begin code_len = 5'd9; symbol = 8'hC1; end
            16'b1111110110??????: begin code_len = 5'd10; symbol = 8'h09; end
            16'b1111110111??????: begin code_len = 5'd10; symbol = 8'h23; end
            16'b1111111000??????: begin code_len = 5'd10; symbol = 8'h33; end
            16'b1111111001??????: begin code_len = 5'd10; symbol = 8'h52; end
            16'b1111111010??????: begin code_len = 5'd10; symbol = 8'hF0; end
            16'b11111110110?????: begin code_len = 5'd11; symbol = 8'h15; end
            16'b11111110111?????: begin code_len = 5'd11; symbol = 8'h62; end
            16'b11111111000?????: begin code_len = 5'd11; symbol = 8'h72; end
            16'b11111111001?????: begin code_len = 5'd11; symbol = 8'hD1; end
            16'b111111110100????: begin code_len = 5'd12; symbol = 8'h0A; end
            16'b111111110101????: begin code_len = 5'd12; symbol = 8'h16; end
            16'b111111110110????: begin code_len = 5'd12; symbol = 8'h24; end
            16'b111111110111????: begin code_len = 5'd12; symbol = 8'h34; end
            16'b11111111100000??: begin code_len = 5'd14; symbol = 8'hE1; end
            16'b111111111000010?: begin code_len = 5'd15; symbol = 8'h25; end
            16'b111111111000011?: begin code_len = 5'd15; symbol = 8'hF1; end
            16'b1111111110001000: begin code_len = 5'd16; symbol = 8'h17; end
            16'b1111111110001001: begin code_len = 5'd16; symbol = 8'h18; end
            16'b1111111110001010: begin code_len = 5'd16; symbol = 8'h19; end
            16'b1111111110001011: begin code_len = 5'd16; symbol = 8'h1A; end
            16'b1111111110001100: begin code_len = 5'd16; symbol = 8'h26; end
            16'b1111111110001101: begin code_len = 5'd16; symbol = 8'h27; end
            16'b1111111110001110: begin code_len = 5'd16; symbol = 8'h28; end
            16'b1111111110001111: begin code_len = 5'd16; symbol = 8'h29; end
            16'b1111111110010000: begin code_len = 5'd16; symbol = 8'h2A; end
            16'b1111111110010001: begin code_len = 5'd16; symbol = 8'h35; end
            16'b1111111110010010: begin code_len = 5'd16; symbol = 8'h36; end
            16'b1111111110010011: begin code_len = 5'd16; symbol = 8'h37; end
            16'b1111111110010100: begin code_len = 5'd16; symbol = 8'h38; end
            16'b1111111110010101: begin code_len = 5'd16; symbol = 8'h39; end
            16'b1111111110010110: begin code_len = 5'd16; symbol = 8'h3A; end
            16'b1111111110010111: begin code_len = 5'd16; symbol = 8'h43; end
            16'b1111111110011000: begin code_len = 5'd16; symbol = 8'h44; end
            16'b1111111110011001: begin code_len = 5'd16; symbol = 8'h45; end
            16'b1111111110011010: begin code_len = 5'd16; symbol = 8'h46; end
            16'b1111111110011011: begin code_len = 5'd16; symbol = 8'h47; end
            16'b1111111110011100: begin code_len = 5'd16; symbol = 8'h48; end
            16'b1111111110011101: begin code_len = 5'd16; symbol = 8'h49; end
            16'b1111111110011110: begin code_len = 5'd16; symbol = 8'h4A; end
            16'b1111111110011111: begin code_len = 5'd16; symbol = 8'h53; end
            16'b1111111110100000: begin code_len = 5'd16; symbol = 8'h54; end
            16'b1111111110100001: begin code_len = 5'd16; symbol = 8'h55; end
            16'b1111111110100010: begin code_len = 5'd16; symbol = 8'h56; end
            16'b1111111110100011: begin code_len = 5'd16; symbol = 8'h57; end
            16'b1111111110100100: begin code_len = 5'd16; symbol = 8'h58; end
            16'b1111111110100101: begin code_len = 5'd16; symbol = 8'h59; end
            16'b1111111110100110: begin code_len = 5'd16; symbol = 8'h5A; end
            16'b1111111110100111: begin code_len = 5'd16; symbol = 8'h63; end
            16'b1111111110101000: begin code_len = 5'd16; symbol = 8'h64; end
            16'b1111111110101001: begin code_len = 5'd16; symbol = 8'h65; end
            16'b1111111110101010: begin code_len = 5'd16; symbol = 8'h66; end
            16'b1111111110101011: begin code_len = 5'd16; symbol = 8'h67; end
            16'b1111111110101100: begin code_len = 5'd16; symbol = 8'h68; end
            16'b1111111110101101: begin code_len = 5'd16; symbol = 8'h69; end
            16'b1111111110101110: begin code_len = 5'd16; symbol = 8'h6A; end
            16'b1111111110101111: begin code_len = 5'd16; symbol = 8'h73; end
            16'b1111111110110000: begin code_len = 5'd16; symbol = 8'h74; end
            16'b1111111110110001: begin code_len = 5'd16; symbol = 8'h75; end
            16'b1111111110110010: begin code_len = 5'd16; symbol = 8'h76; end
            16'b1111111110110011: begin code_len = 5'd16; symbol = 8'h77; end
            16'b1111111110110100: begin code_len = 5'd16; symbol = 8'h78; end
            16'b1111111110110101: begin code_len = 5'd16; symbol = 8'h79; end
            16'b1111111110110110: begin code_len = 5'd16; symbol = 8'h7A; end
            16'b1111111110110111: begin code_len = 5'd16; symbol = 8'h82; end
            16'b1111111110111000: begin code_len = 5'd16; symbol = 8'h83; end
            16'b1111111110111001: begin code_len = 5'd16; symbol = 8'h84; end
            16'b1111111110111010: begin code_len = 5'd16; symbol = 8'h85; end
            16'b1111111110111011: begin code_len = 5'd16; symbol = 8'h86; end
            16'b1111111110111100: begin code_len = 5'd16; symbol = 8'h87; end
            16'b1111111110111101: begin code_len = 5'd16; symbol = 8'h88; end
            16'b1111111110111110: begin code_len = 5'd16; symbol = 8'h89; end
            16'b1111111110111111: begin code_len = 5'd16; symbol = 8'h8A; end
            16'b1111111111000000: begin code_len = 5'd16; symbol = 8'h92; end
            16'b1111111111000001: begin code_len = 5'd16; symbol = 8'h93; end
            16'b1111111111000010: begin code_len = 5'd16; symbol = 8'h94; end
            16'b1111111111000011: begin code_len = 5'd16; symbol = 8'h95; end
            16'b1111111111000100: begin code_len = 5'd16; symbol = 8'h96; end
            16'b1111111111000101: begin code_len = 5'd16; symbol = 8'h97; end
            16'b1111111111000110: begin code_len = 5'd16; symbol = 8'h98; end
            16'b1111111111000111: begin code_len = 5'd16; symbol = 8'h99; end
            16'b1111111111001000: begin code_len = 5'd16; symbol = 8'h9A; end
            16'b1111111111001001: begin code_len = 5'd16; symbol = 8'hA2; end
            16'b1111111111001010: begin code_len = 5'd16; symbol = 8'hA3; end
            16'b1111111111001011: begin code_len = 5'd16; symbol = 8'hA4; end
            16'b1111111111001100: begin code_len = 5'd16; symbol = 8'hA5; end
            16'b1111111111001101: begin code_len = 5'd16; symbol = 8'hA6; end
            16'b1111111111001110: begin code_len = 5'd16; symbol = 8'hA7; end
            16'b1111111111001111: begin code_len = 5'd16; symbol = 8'hA8; end
            16'b1111111111010000: begin code_len = 5'd16; symbol = 8'hA9; end
            16'b1111111111010001: begin code_len = 5'd16; symbol = 8'hAA; end
            16'b1111111111010010: begin code_len = 5'd16; symbol = 8'hB2; end
            16'b1111111111010011: begin code_len = 5'd16; symbol = 8'hB3; end
            16'b1111111111010100: begin code_len = 5'd16; symbol = 8'hB4; end
            16'b1111111111010101: begin code_len = 5'd16; symbol = 8'hB5; end
            16'b1111111111010110: begin code_len = 5'd16; symbol = 8'hB6; end
            16'b1111111111010111: begin code_len = 5'd16; symbol = 8'hB7; end
            16'b1111111111011000: begin code_len = 5'd16; symbol = 8'hB8; end
            16'b1111111111011001: begin code_len = 5'd16; symbol = 8'hB9; end
            16'b1111111111011010: begin code_len = 5'd16; symbol = 8'hBA; end
            16'b1111111111011011: begin code_len = 5'd16; symbol = 8'hC2; end
            16'b1111111111011100: begin code_len = 5'd16; symbol = 8'hC3; end
            16'b1111111111011101: begin code_len = 5'd16; symbol = 8'hC4; end
            16'b1111111111011110: begin code_len = 5'd16; symbol = 8'hC5; end
            16'b1111111111011111: begin code_len = 5'd16; symbol = 8'hC6; end
            16'b1111111111100000: begin code_len = 5'd16; symbol = 8'hC7; end
            16'b1111111111100001: begin code_len = 5'd16; symbol = 8'hC8; end
            16'b1111111111100010: begin code_len = 5'd16; symbol = 8'hC9; end
            16'b1111111111100011: begin code_len = 5'd16; symbol = 8'hCA; end
            16'b1111111111100100: begin code_len = 5'd16; symbol = 8'hD2; end
            16'b1111111111100101: begin code_len = 5'd16; symbol = 8'hD3; end
            16'b1111111111100110: begin code_len = 5'd16; symbol = 8'hD4; end
            16'b1111111111100111: begin code_len = 5'd16; symbol = 8'hD5; end
            16'b1111111111101000: begin code_len = 5'd16; symbol = 8'hD6; end
            16'b1111111111101001: begin code_len = 5'd16; symbol = 8'hD7; end
            16'b1111111111101010: begin code_len = 5'd16; symbol = 8'hD8; end
            16'b1111111111101011: begin code_len = 5'd16; symbol = 8'hD9; end
            16'b1111111111101100: begin code_len = 5'd16; symbol = 8'hDA; end
            16'b1111111111101101: begin code_len = 5'd16; symbol = 8'hE2; end
            16'b1111111111101110: begin code_len = 5'd16; symbol = 8'hE3; end
            16'b1111111111101111: begin code_len = 5'd16; symbol = 8'hE4; end
            16'b1111111111110000: begin code_len = 5'd16; symbol = 8'hE5; end
            16'b1111111111110001: begin code_len = 5'd16; symbol = 8'hE6; end
            16'b1111111111110010: begin code_len = 5'd16; symbol = 8'hE7; end
            16'b1111111111110011: begin code_len = 5'd16; symbol = 8'hE8; end
            16'b1111111111110100: begin code_len = 5'd16; symbol = 8'hE9; end
            16'b1111111111110101: begin code_len = 5'd16; symbol = 8'hEA; end
            16'b1111111111110110: begin code_len = 5'd16; symbol = 8'hF2; end
            16'b1111111111110111: begin code_len = 5'd16; symbol = 8'hF3; end
            16'b1111111111111000: begin code_len = 5'd16; symbol = 8'hF4; end
            16'b1111111111111001: begin code_len = 5'd16; symbol = 8'hF5; end
            16'b1111111111111010: begin code_len = 5'd16; symbol = 8'hF6; end
            16'b1111111111111011: begin code_len = 5'd16; symbol = 8'hF7; end
            16'b1111111111111100: begin code_len = 5'd16; symbol = 8'hF8; end
            16'b1111111111111101: begin code_len = 5'd16; symbol = 8'hF9; end
            16'b1111111111111110: begin code_len = 5'd16; symbol = 8'hFA; end
                    default: begin code_len = 5'd2; symbol = 8'h00; end // fallback EOB
                endcase
            end
        endcase
    end

endmodule
