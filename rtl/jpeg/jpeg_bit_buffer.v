//-----------------------------------------------------------------------------
// File: jpeg_bit_buffer.v
// Description: Dedicated 64-bit barrel shifter & byte-unstuffer for JPEG entropy decode.
// Automatically handles 0xFF 0x00 unstuffing, detects 0xFF 0xD9 (EOI), and provides
// a continuous MSB-aligned 32-bit window to the Huffman decoder.
// Standard: Verilog-2001
//-----------------------------------------------------------------------------

`timescale 1ns / 1ps

module jpeg_bit_buffer (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        flush,          // Clear buffer (asserted at SOS)

    // Byte stream input (from input FIFO)
    input  wire        in_valid,
    output wire        in_ready,
    input  wire [7:0]  in_data,

    // Consumer interface (from Huffman / bit-extractor)
    input  wire        consume_en,     // Pulse 1 when consuming bits
    input  wire [4:0]  consume_count,  // Number of bits consumed (0..27)

    // Peek window output
    output wire [31:0] bit_window,     // Top 32 valid bits (MSB-aligned)
    output wire [6:0]  bits_valid,     // Number of valid bits in buffer (0..64)
    output reg         eoi_detected    // Asserted if FF D9 marker encountered
);

    reg [63:0] shifter;
    reg [6:0]  count;
    reg        stuffed_ff;

    assign bit_window   = shifter[63:32];
    assign bits_valid   = flush ? 7'd0 : (eoi_detected ? 7'd64 : count);
    assign in_ready     = (count <= 7'd48);

    // Unstuffer combinational decode
    reg       push_byte;
    reg [7:0] byte_to_push;

    always @* begin
        push_byte    = 1'b0;
        byte_to_push = 8'd0;

        if (in_valid && in_ready) begin
            if (stuffed_ff) begin
                if (in_data == 8'h00) begin
                    // Byte stuffing: 0xFF 0x00 represents literal 0xFF
                    push_byte    = 1'b1;
                    byte_to_push = 8'hFF;
                end
                // If 0xD9, it is EOI (handled sequentially below)
            end else if (in_data == 8'hFF) begin
                // Marker prefix or stuffed byte: do not push yet
                push_byte = 1'b0;
            end else begin
                // Normal data byte
                push_byte    = 1'b1;
                byte_to_push = in_data;
            end
        end
    end

    // Intermediate calculation after consuming bits
    reg [6:0]  rem_count;
    reg [63:0] shifted;

    always @* begin
        rem_count = count - (consume_en ? {2'd0, consume_count} : 7'd0);
        shifted   = consume_en ? (shifter << consume_count) : shifter;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            shifter      <= 64'd0;
            count        <= 7'd0;
            stuffed_ff   <= 1'b0;
            eoi_detected <= 1'b0;
        end else if (flush) begin
            shifter      <= 64'd0;
            count        <= 7'd0;
            stuffed_ff   <= 1'b0;
            eoi_detected <= 1'b0;
        end else begin
            // Track 0xFF byte stuffing
            if (in_valid && in_ready) begin
                if (stuffed_ff) begin
                    stuffed_ff <= (in_data == 8'hFF); // Keep flag if consecutive 0xFF fill bytes
                    if (in_data == 8'hD9) begin
                        eoi_detected <= 1'b1;
                    end
                end else if (in_data == 8'hFF) begin
                    stuffed_ff <= 1'b1;
                end
            end

            // Combined shifter update
            if (push_byte) begin
                shifter <= (shifted & ~(64'hFF << (7'd56 - rem_count))) | ({56'd0, byte_to_push} << (7'd56 - rem_count));
                count   <= rem_count + 7'd8;
            end else begin
                shifter <= shifted;
                count   <= rem_count;
            end
        end
    end

endmodule
