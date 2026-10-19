//-----------------------------------------------------------------------------
// File: tmds_serializer.v
// Description: 10:1 TMDS Serializer with differential outputs
// Dual target:
//   - Simulation / Verilator: Behavioral shift register model
//   - Vivado / FPGA hardware: Spartan-7 ODDR primitives + OBUFDS
// Standard: Verilog-2001
//-----------------------------------------------------------------------------

`timescale 1ns / 1ps

module tmds_serializer (
    input  wire       clk_pixel,    // 74.25 MHz parallel pixel clock
    input  wire       clk_pixel_5x, // 371.25 MHz 5x serial clock (for hardware DDR)
    input  wire       rst_n,

    input  wire [9:0] tmds_d0,      // Blue + Sync
    input  wire [9:0] tmds_d1,      // Green
    input  wire [9:0] tmds_d2,      // Red
    input  wire [9:0] tmds_clk,     // 10'b1111100000

    output wire       hdmi_tx_clk_p,
    output wire       hdmi_tx_clk_n,
    output wire [2:0] hdmi_tx_data_p,
    output wire [2:0] hdmi_tx_data_n
);

`ifdef SYNTHESIS
    // Synchronize clk_pixel phase using a registered toggle in clk_pixel domain (NO BUFG clock-to-D)
    reg pixel_toggle;
    always @(posedge clk_pixel or negedge rst_n) begin
        if (!rst_n) pixel_toggle <= 1'b0;
        else        pixel_toggle <= ~pixel_toggle;
    end

    (* ASYNC_REG = "TRUE" *) reg [2:0] toggle_sync;
    always @(posedge clk_pixel_5x or negedge rst_n) begin
        if (!rst_n) toggle_sync <= 3'b000;
        else        toggle_sync <= {toggle_sync[1:0], pixel_toggle};
    end
    wire load_pulse = (toggle_sync[1] ^ toggle_sync[2]);

    // Data channels (Dual 5-bit shift registers for high-speed ODDR serialization)
    genvar i;
    generate
        for (i = 0; i < 3; i = i + 1) begin : gen_data_diff
            reg [9:0] din;
            always @* begin
                case (i)
                    0: din = tmds_d0;
                    1: din = tmds_d1;
                    default: din = tmds_d2;
                endcase
            end

            reg [4:0] shift_even;
            reg [4:0] shift_odd;

            always @(posedge clk_pixel_5x or negedge rst_n) begin
                if (!rst_n) begin
                    shift_even <= 5'd0;
                    shift_odd  <= 5'd0;
                end else if (load_pulse) begin
                    shift_even <= {din[8], din[6], din[4], din[2], din[0]};
                    shift_odd  <= {din[9], din[7], din[5], din[3], din[1]};
                end else begin
                    shift_even <= {1'b0, shift_even[4:1]};
                    shift_odd  <= {1'b0, shift_odd[4:1]};
                end
            end

            wire s_out;
            ODDR #(
                .DDR_CLK_EDGE("SAME_EDGE"),
                .INIT(1'b0),
                .SRTYPE("SYNC")
            ) u_oddr_data (
                .Q(s_out),
                .C(clk_pixel_5x),
                .CE(1'b1),
                .D1(shift_even[0]),
                .D2(shift_odd[0]),
                .R(1'b0),
                .S(1'b0)
            );

            OBUFDS #(
                .IOSTANDARD("TMDS_33")
            ) obufds_data (
                .I(s_out),
                .O(hdmi_tx_data_p[i]),
                .OB(hdmi_tx_data_n[i])
            );
        end
    endgenerate

    // Clock channel: Forward clk_pixel directly through ODDR + OBUFDS
    wire clk_out_s;
    ODDR #(
        .DDR_CLK_EDGE("SAME_EDGE"),
        .INIT(1'b0),
        .SRTYPE("SYNC")
    ) u_oddr_clk (
        .Q(clk_out_s),
        .C(clk_pixel),
        .CE(1'b1),
        .D1(1'b1),
        .D2(1'b0),
        .R(1'b0),
        .S(1'b0)
    );

    OBUFDS #(
        .IOSTANDARD("TMDS_33")
    ) obufds_clk (
        .I(clk_out_s),
        .O(hdmi_tx_clk_p),
        .OB(hdmi_tx_clk_n)
    );

`else
    // Behavioral simulation model
    reg [9:0] shift_d0, shift_d1, shift_d2, shift_clk;

    always @(posedge clk_pixel or negedge rst_n) begin
        if (!rst_n) begin
            shift_d0  <= 10'd0;
            shift_d1  <= 10'd0;
            shift_d2  <= 10'd0;
            shift_clk <= 10'b1111100000;
        end else begin
            shift_d0  <= tmds_d0;
            shift_d1  <= tmds_d1;
            shift_d2  <= tmds_d2;
            shift_clk <= tmds_clk;
        end
    end

    assign hdmi_tx_data_p[0] = shift_d0[0];
    assign hdmi_tx_data_n[0] = ~shift_d0[0];

    assign hdmi_tx_data_p[1] = shift_d1[0];
    assign hdmi_tx_data_n[1] = ~shift_d1[0];

    assign hdmi_tx_data_p[2] = shift_d2[0];
    assign hdmi_tx_data_n[2] = ~shift_d2[0];

    assign hdmi_tx_clk_p     = shift_clk[0];
    assign hdmi_tx_clk_n     = ~shift_clk[0];
`endif

endmodule
