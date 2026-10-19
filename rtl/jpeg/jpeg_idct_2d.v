//-----------------------------------------------------------------------------
// File: jpeg_idct_2d.v
// Description: 2D 8x8 Inverse Discrete Cosine Transform (IDCT)
// Pipelined architecture with registered row/column loading and balanced MAC trees
// to achieve full 100 MHz timing closure on Artix-7/Spartan-7.
// Uses Chen/Arai-Agui-Hou (AAH) algorithm with fixed-point arithmetic (11-bit fraction).
// Standard: Verilog-2001
//-----------------------------------------------------------------------------

`timescale 1ns / 1ps

module jpeg_idct_2d (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,
    input  wire [1023:0] coeff_in,   // 64 dequantized 16-bit signed coefficients
    output reg         done,
    output reg  [511:0]  pixels_out  // 64 reconstructed 8-bit spatial samples
);

    // Fixed-point cosine constants scaled by 2^11 = 2048
    localparam signed [31:0] C0 = 32'sd1448; // cos(4*pi/16) * 2048 / sqrt(2)
    localparam signed [31:0] C1 = 32'sd2009; // cos(1*pi/16) * 2048
    localparam signed [31:0] C2 = 32'sd1892; // cos(2*pi/16) * 2048
    localparam signed [31:0] C3 = 32'sd1703; // cos(3*pi/16) * 2048
    localparam signed [31:0] C4 = 32'sd1448; // cos(4*pi/16) * 2048
    localparam signed [31:0] C5 = 32'sd1138; // cos(5*pi/16) * 2048
    localparam signed [31:0] C6 = 32'sd784;  // cos(6*pi/16) * 2048
    localparam signed [31:0] C7 = 32'sd399;  // cos(7*pi/16) * 2048

    // Intermediate transpose buffer
    reg signed [15:0] trans_buf [0:63];

    // Pipeline registers for 1D IDCT
    reg signed [15:0] x_reg [0:7];
    reg signed [31:0] ev_p0 [0:3], ev_p1 [0:3];
    reg signed [31:0] od_p0 [0:3], od_p1 [0:3];
    reg signed [31:0] even_r [0:3];
    reg signed [31:0] odd_r [0:3];
    reg signed [15:0] s_reg [0:7];

    localparam [3:0] IDLE       = 4'd0;
    localparam [3:0] ROW_LOAD   = 4'd1;
    localparam [3:0] ROW_STAGE1 = 4'd2;
    localparam [3:0] ROW_STAGE2 = 4'd3;
    localparam [3:0] ROW_STAGE3 = 4'd4;
    localparam [3:0] COL_LOAD   = 4'd5;
    localparam [3:0] COL_STAGE1 = 4'd6;
    localparam [3:0] COL_STAGE2 = 4'd7;
    localparam [3:0] COL_STAGE3 = 4'd8;
    localparam [3:0] COL_STAGE4 = 4'd9;
    localparam [3:0] FINISH     = 4'd10;

    reg [3:0] state;
    reg [2:0] step_idx; // 0..7 for rows / cols

    // Balanced 2-product MAC pairs (max 2 DSP cascade depth)
    reg signed [31:0] mac_ev_p0 [0:3], mac_ev_p1 [0:3];
    reg signed [31:0] mac_od_p0 [0:3], mac_od_p1 [0:3];

    always @* begin
        mac_ev_p0[0] = x_reg[0]*C0 + x_reg[2]*C2;
        mac_ev_p1[0] = x_reg[4]*C4 + x_reg[6]*C6;
        mac_ev_p0[1] = x_reg[0]*C0 + x_reg[2]*C6;
        mac_ev_p1[1] = x_reg[4]*C4 + x_reg[6]*C2;
        mac_ev_p0[2] = x_reg[0]*C0 - x_reg[2]*C6;
        mac_ev_p1[2] = x_reg[4]*C4 - x_reg[6]*C2;
        mac_ev_p0[3] = x_reg[0]*C0 - x_reg[2]*C2;
        mac_ev_p1[3] = x_reg[4]*C4 - x_reg[6]*C6;

        mac_od_p0[0] = x_reg[1]*C1 + x_reg[3]*C3;
        mac_od_p1[0] = x_reg[5]*C5 + x_reg[7]*C7;
        mac_od_p0[1] = x_reg[1]*C3 - x_reg[3]*C7;
        mac_od_p1[1] = x_reg[5]*C1 + x_reg[7]*C5;
        mac_od_p0[2] = x_reg[1]*C5 - x_reg[3]*C1;
        mac_od_p1[2] = x_reg[5]*C7 + x_reg[7]*C3;
        mac_od_p0[3] = x_reg[1]*C7 - x_reg[3]*C5;
        mac_od_p1[3] = x_reg[5]*C3 - x_reg[7]*C1;
    end

    // Stage 2: Combinational fabric summation
    reg signed [31:0] sum_even [0:3];
    reg signed [31:0] sum_odd  [0:3];

    always @* begin
        sum_even[0] = ev_p0[0] + ev_p1[0];
        sum_even[1] = ev_p0[1] - ev_p1[1];
        sum_even[2] = ev_p0[2] - ev_p1[2];
        sum_even[3] = ev_p0[3] + ev_p1[3];

        sum_odd[0]  = od_p0[0] + od_p1[0];
        sum_odd[1]  = od_p0[1] - od_p1[1];
        sum_odd[2]  = od_p0[2] + od_p1[2];
        sum_odd[3]  = od_p0[3] + od_p1[3];
    end

    // Clamping function for column stage
    function [7:0] clamp_sample;
        input signed [31:0] s_val;
        reg signed [31:0] val;
        begin
            val = s_val + 32'sd128;
            if (val < 32'sd0)
                clamp_sample = 8'd0;
            else if (val > 32'sd255)
                clamp_sample = 8'd255;
            else
                clamp_sample = val[7:0];
        end
    endfunction

    integer i;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= IDLE;
            step_idx   <= 3'd0;
            done       <= 1'b0;
            pixels_out <= 512'd0;
            for (i = 0; i < 8; i = i + 1) begin
                x_reg[i] <= 16'sd0;
                s_reg[i] <= 16'sd0;
            end
            for (i = 0; i < 4; i = i + 1) begin
                even_r[i] <= 32'sd0;
                odd_r[i]  <= 32'sd0;
                ev_p0[i]  <= 32'sd0;
                ev_p1[i]  <= 32'sd0;
                od_p0[i]  <= 32'sd0;
                od_p1[i]  <= 32'sd0;
            end
            for (i = 0; i < 64; i = i + 1) begin
                trans_buf[i] <= 16'sd0;
            end
        end else begin
            done <= 1'b0;

            case (state)
                IDLE: begin
                    if (start) begin
                        state    <= ROW_LOAD;
                        step_idx <= 3'd0;
                    end
                end

                // --- Row Pass: Load Inputs from Dequantized Buffer ---
                ROW_LOAD: begin
                    for (i = 0; i < 8; i = i + 1) begin
                        x_reg[i] <= $signed(coeff_in[{step_idx, i[2:0]}*16 +: 16]);
                    end
                    state <= ROW_STAGE1;
                end

                // --- Row Pass Stage 1: DSP Multiply-Accumulate Pairs (max 2 DSP cascade) ---
                ROW_STAGE1: begin
                    for (i = 0; i < 4; i = i + 1) begin
                        ev_p0[i] <= mac_ev_p0[i];
                        ev_p1[i] <= mac_ev_p1[i];
                        od_p0[i] <= mac_od_p0[i];
                        od_p1[i] <= mac_od_p1[i];
                    end
                    state <= ROW_STAGE2;
                end

                // --- Row Pass Stage 2: Fabric Sum ---
                ROW_STAGE2: begin
                    for (i = 0; i < 4; i = i + 1) begin
                        even_r[i] <= sum_even[i];
                        odd_r[i]  <= sum_odd[i];
                    end
                    state <= ROW_STAGE3;
                end

                // --- Row Pass Stage 3: Butterfly Addition, Scaling & Transpose Store ---
                ROW_STAGE3: begin
                    trans_buf[{3'd0, step_idx}] <= (even_r[0] + odd_r[0] + 32'sd1024) >>> 11;
                    trans_buf[{3'd1, step_idx}] <= (even_r[1] + odd_r[1] + 32'sd1024) >>> 11;
                    trans_buf[{3'd2, step_idx}] <= (even_r[2] + odd_r[2] + 32'sd1024) >>> 11;
                    trans_buf[{3'd3, step_idx}] <= (even_r[3] + odd_r[3] + 32'sd1024) >>> 11;
                    trans_buf[{3'd4, step_idx}] <= (even_r[3] - odd_r[3] + 32'sd1024) >>> 11;
                    trans_buf[{3'd5, step_idx}] <= (even_r[2] - odd_r[2] + 32'sd1024) >>> 11;
                    trans_buf[{3'd6, step_idx}] <= (even_r[1] - odd_r[1] + 32'sd1024) >>> 11;
                    trans_buf[{3'd7, step_idx}] <= (even_r[0] - odd_r[0] + 32'sd1024) >>> 11;

                    if (step_idx == 3'd7) begin
                        state    <= COL_LOAD;
                        step_idx <= 3'd0;
                    end else begin
                        step_idx <= step_idx + 3'd1;
                        state    <= ROW_LOAD;
                    end
                end

                // --- Column Pass: Load Inputs from Transpose Buffer ---
                COL_LOAD: begin
                    for (i = 0; i < 8; i = i + 1) begin
                        x_reg[i] <= trans_buf[{step_idx, i[2:0]}];
                    end
                    state <= COL_STAGE1;
                end

                // --- Column Pass Stage 1: DSP Multiply-Accumulate Pairs (max 2 DSP cascade) ---
                COL_STAGE1: begin
                    for (i = 0; i < 4; i = i + 1) begin
                        ev_p0[i] <= mac_ev_p0[i];
                        ev_p1[i] <= mac_ev_p1[i];
                        od_p0[i] <= mac_od_p0[i];
                        od_p1[i] <= mac_od_p1[i];
                    end
                    state <= COL_STAGE2;
                end

                // --- Column Pass Stage 2: Fabric Sum ---
                COL_STAGE2: begin
                    for (i = 0; i < 4; i = i + 1) begin
                        even_r[i] <= sum_even[i];
                        odd_r[i]  <= sum_odd[i];
                    end
                    state <= COL_STAGE3;
                end

                // --- Column Pass Stage 3: Butterfly Addition & Scaling ---
                COL_STAGE3: begin
                    s_reg[0] <= (even_r[0] + odd_r[0] + 32'sd4096) >>> 13;
                    s_reg[1] <= (even_r[1] + odd_r[1] + 32'sd4096) >>> 13;
                    s_reg[2] <= (even_r[2] + odd_r[2] + 32'sd4096) >>> 13;
                    s_reg[3] <= (even_r[3] + odd_r[3] + 32'sd4096) >>> 13;
                    s_reg[4] <= (even_r[3] - odd_r[3] + 32'sd4096) >>> 13;
                    s_reg[5] <= (even_r[2] - odd_r[2] + 32'sd4096) >>> 13;
                    s_reg[6] <= (even_r[1] - odd_r[1] + 32'sd4096) >>> 13;
                    s_reg[7] <= (even_r[0] - odd_r[0] + 32'sd4096) >>> 13;
                    state    <= COL_STAGE4;
                end

                // --- Column Pass Stage 4: Clamping & Output Store ---
                COL_STAGE4: begin
                    for (i = 0; i < 8; i = i + 1) begin
                        pixels_out[{i[2:0], step_idx}*8 +: 8] <= clamp_sample({{16{s_reg[i][15]}}, s_reg[i]});
                    end

                    if (step_idx == 3'd7) begin
                        state <= FINISH;
                    end else begin
                        step_idx <= step_idx + 3'd1;
                        state    <= COL_LOAD;
                    end
                end

                FINISH: begin
                    done  <= 1'b1;
                    state <= IDLE;
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule
