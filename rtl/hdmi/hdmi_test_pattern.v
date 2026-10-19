//-----------------------------------------------------------------------------
// File: hdmi_test_pattern.v
// Description: Multi-pattern RGB888 generator for HDMI verification
// Patterns:
//   0: 8 standard color bars (White, Yellow, Cyan, Green, Magenta, Red, Blue, Black)
//   1: Dynamic moving color bars
//   2: Smooth RGB gradient ramp
//   3: 32x32 Checkerboard
//   4: Solid Red
//   5: Solid Green
//   6: Solid Blue
//   7: Solid White
// Standard: Verilog-2001
//-----------------------------------------------------------------------------

`timescale 1ns / 1ps

module hdmi_test_pattern (
    input  wire        clk_pixel,
    input  wire        rst_n,
    input  wire [11:0] pixel_x,
    input  wire [11:0] pixel_y,
    input  wire        vde,
    input  wire [2:0]  pattern_sel,

    output wire [23:0] rgb_data // {R[7:0], G[7:0], B[7:0]}
);

    reg [7:0] r, g, b;
    reg [7:0] frame_anim_cnt;

    // Slow counter for animated patterns
    always @(posedge clk_pixel or negedge rst_n) begin
        if (!rst_n) begin
            frame_anim_cnt <= 8'd0;
        end else if (pixel_x == 12'd0 && pixel_y == 12'd0) begin
            frame_anim_cnt <= frame_anim_cnt + 8'd1;
        end
    end

    // 8-bar index: 1280 / 8 = 160 pixels per bar (comparator tree instead of 12-bit hardware divider)
    reg [2:0] bar_idx;
    always @* begin
        if      (pixel_x < 12'd160)  bar_idx = 3'd0;
        else if (pixel_x < 12'd320)  bar_idx = 3'd1;
        else if (pixel_x < 12'd480)  bar_idx = 3'd2;
        else if (pixel_x < 12'd640)  bar_idx = 3'd3;
        else if (pixel_x < 12'd800)  bar_idx = 3'd4;
        else if (pixel_x < 12'd960)  bar_idx = 3'd5;
        else if (pixel_x < 12'd1120) bar_idx = 3'd6;
        else                         bar_idx = 3'd7;
    end

    wire [11:0] raw_anim_x = pixel_x + {3'd0, frame_anim_cnt, 1'b0};
    wire [11:0] anim_x = (raw_anim_x >= 12'd1280) ? (raw_anim_x - 12'd1280) : raw_anim_x;
    reg [2:0] anim_bar_idx;
    always @* begin
        if      (anim_x < 12'd160)  anim_bar_idx = 3'd0;
        else if (anim_x < 12'd320)  anim_bar_idx = 3'd1;
        else if (anim_x < 12'd480)  anim_bar_idx = 3'd2;
        else if (anim_x < 12'd640)  anim_bar_idx = 3'd3;
        else if (anim_x < 12'd800)  anim_bar_idx = 3'd4;
        else if (anim_x < 12'd960)  anim_bar_idx = 3'd5;
        else if (anim_x < 12'd1120) anim_bar_idx = 3'd6;
        else                        anim_bar_idx = 3'd7;
    end

    always @* begin
        if (!vde) begin
            r = 8'h00;
            g = 8'h00;
            b = 8'h00;
        end else begin
            case (pattern_sel)
                3'd0: begin // Standard Color Bars
                    case (bar_idx)
                        3'd0: begin r = 8'hFF; g = 8'hFF; b = 8'hFF; end // White
                        3'd1: begin r = 8'hFF; g = 8'hFF; b = 8'h00; end // Yellow
                        3'd2: begin r = 8'h00; g = 8'hFF; b = 8'hFF; end // Cyan
                        3'd3: begin r = 8'h00; g = 8'hFF; b = 8'h00; end // Green
                        3'd4: begin r = 8'hFF; g = 8'h00; b = 8'hFF; end // Magenta
                        3'd5: begin r = 8'hFF; g = 8'h00; b = 8'h00; end // Red
                        3'd6: begin r = 8'h00; g = 8'h00; b = 8'hFF; end // Blue
                        default: begin r = 8'h00; g = 8'h00; b = 8'h00; end // Black
                    endcase
                end

                3'd1: begin // Animated moving bars
                    case (anim_bar_idx)
                        3'd0: begin r = 8'hFF; g = 8'hFF; b = 8'hFF; end
                        3'd1: begin r = 8'hFF; g = 8'hFF; b = 8'h00; end
                        3'd2: begin r = 8'h00; g = 8'hFF; b = 8'hFF; end
                        3'd3: begin r = 8'h00; g = 8'hFF; b = 8'h00; end
                        3'd4: begin r = 8'hFF; g = 8'h00; b = 8'hFF; end
                        3'd5: begin r = 8'hFF; g = 8'h00; b = 8'h00; end
                        3'd6: begin r = 8'h00; g = 8'h00; b = 8'hFF; end
                        default: begin r = 8'h00; g = 8'h00; b = 8'h00; end
                    endcase
                end

                3'd2: begin // Color Ramp (Horizontal Red, Vertical Green, Diag Blue)
                    r = pixel_x[7:0];
                    g = pixel_y[7:0];
                    b = pixel_x[7:0] + pixel_y[7:0];
                end

                3'd3: begin // 32x32 Checkerboard
                    if (pixel_x[5] ^ pixel_y[5]) begin
                        r = 8'hFF; g = 8'hFF; b = 8'hFF;
                    end else begin
                        r = 8'h20; g = 8'h20; b = 8'h20;
                    end
                end

                3'd4: begin r = 8'hFF; g = 8'h00; b = 8'h00; end // Red
                3'd5: begin r = 8'h00; g = 8'hFF; b = 8'h00; end // Green
                3'd6: begin r = 8'h00; g = 8'h00; b = 8'hFF; end // Blue
                default: begin r = 8'hFF; g = 8'hFF; b = 8'hFF; end // White
            endcase
        end
    end

    assign rgb_data = {r, g, b};

endmodule
