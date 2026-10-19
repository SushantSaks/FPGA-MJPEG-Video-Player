//-----------------------------------------------------------------------------
// File: hdmi_timing_gen.v
// Description: CEA-861 1280x720 @ 60 Hz Timing Generator
// Standard 720p:
//   Pixel clock: 74.25 MHz
//   Horizontal: Active 1280, Front Porch 110, Sync 40, Back Porch 220 (Total 1650)
//   Vertical:   Active 720,  Front Porch 5,   Sync 5,  Back Porch 20  (Total 750)
//   Polarity: HSYNC positive (+), VSYNC positive (+)
// Standard: Verilog-2001
//-----------------------------------------------------------------------------

`timescale 1ns / 1ps

module hdmi_timing_gen #(
    parameter [11:0] H_ACTIVE      = 12'd1280,
    parameter [11:0] H_FRONT_PORCH = 12'd110,
    parameter [11:0] H_SYNC_WIDTH  = 12'd40,
    parameter [11:0] H_BACK_PORCH  = 12'd220,
    parameter [11:0] H_TOTAL       = 12'd1650,

    parameter [11:0] V_ACTIVE      = 12'd720,
    parameter [11:0] V_FRONT_PORCH = 12'd5,
    parameter [11:0] V_SYNC_WIDTH  = 12'd5,
    parameter [11:0] V_BACK_PORCH  = 12'd20,
    parameter [11:0] V_TOTAL       = 12'd750
)(
    input  wire        clk_pixel,
    input  wire        rst_n,

    output wire [11:0] pixel_x,
    output wire [11:0] pixel_y,
    output reg         hsync,
    output reg         vsync,
    output reg         vde,
    output reg         frame_start, // 1-cycle pulse at (0, 0)
    output reg         line_start   // 1-cycle pulse at start of active line
);

    reg [11:0] h_count;
    reg [11:0] v_count;

    // Horizontal and vertical counters
    always @(posedge clk_pixel or negedge rst_n) begin
        if (!rst_n) begin
            h_count <= 12'd0;
            v_count <= 12'd0;
        end else begin
            if (h_count == H_TOTAL - 12'd1) begin
                h_count <= 12'd0;
                if (v_count == V_TOTAL - 12'd1) begin
                    v_count <= 12'd0;
                end else begin
                    v_count <= v_count + 12'd1;
                end
            end else begin
                h_count <= h_count + 12'd1;
            end
        end
    end

    // Active pixel coordinates (valid when vde is high)
    assign pixel_x = (h_count < H_ACTIVE) ? h_count : 12'd0;
    assign pixel_y = (v_count < V_ACTIVE) ? v_count : 12'd0;

    // Timing pulses
    localparam [11:0] H_SYNC_START = H_ACTIVE + H_FRONT_PORCH;
    localparam [11:0] H_SYNC_END   = H_SYNC_START + H_SYNC_WIDTH;

    localparam [11:0] V_SYNC_START = V_ACTIVE + V_FRONT_PORCH;
    localparam [11:0] V_SYNC_END   = V_SYNC_START + V_SYNC_WIDTH;

    always @(posedge clk_pixel or negedge rst_n) begin
        if (!rst_n) begin
            hsync       <= 1'b0;
            vsync       <= 1'b0;
            vde         <= 1'b0;
            frame_start <= 1'b0;
            line_start  <= 1'b0;
        end else begin
            // CEA-861 720p: positive polarity for both HSYNC and VSYNC
            hsync <= (h_count >= H_SYNC_START && h_count < H_SYNC_END);
            vsync <= (v_count >= V_SYNC_START && v_count < V_SYNC_END);
            vde   <= (h_count < H_ACTIVE) && (v_count < V_ACTIVE);

            frame_start <= (h_count == 12'd0) && (v_count == 12'd0);
            line_start  <= (h_count == 12'd0) && (v_count < V_ACTIVE);
        end
    end

endmodule
