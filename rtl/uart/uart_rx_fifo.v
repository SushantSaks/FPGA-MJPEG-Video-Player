`timescale 1ns / 1ps
// ============================================================================
// Module: uart_rx_fifo
// Description: Circular buffer FIFO for buffering incoming UART bytes.
//              Prevents buffer overrun while Flash Controller performs 
//              Sector Erase and Page Programming.
// Standard: Verilog-2001
// ============================================================================

module uart_rx_fifo #(
    parameter integer DEPTH = 2048
) (
    input  wire        clk,
    input  wire        rst_n,

    // Write Port (from uart_rx)
    input  wire        wr_en,
    input  wire [7:0]  din,
    output wire        full,

    // Read Port (to uart_upload_parser)
    input  wire        rd_en,
    output wire [7:0]  dout,
    output wire        empty,
    output wire [11:0] count
);

    localparam integer ADDR_WIDTH = $clog2(DEPTH);

    (* ram_style = "block" *)
    reg [7:0] mem [0:DEPTH-1];

    reg [ADDR_WIDTH-1:0] wr_ptr;
    reg [ADDR_WIDTH-1:0] rd_ptr;
    reg [ADDR_WIDTH:0]   item_count;

    assign full  = (item_count == DEPTH[ADDR_WIDTH:0]);
    assign empty = (item_count == 0);
    assign count = item_count[11:0];

    // Read data is available combinationally
    assign dout = mem[rd_ptr];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr     <= {ADDR_WIDTH{1'b0}};
            rd_ptr     <= {ADDR_WIDTH{1'b0}};
            item_count <= {(ADDR_WIDTH+1){1'b0}};
        end else begin
            case ({wr_en && !full, rd_en && !empty})
                2'b10: begin // Write only
                    mem[wr_ptr] <= din;
                    wr_ptr      <= wr_ptr + 1'b1;
                    item_count  <= item_count + 1'b1;
                end
                2'b01: begin // Read only
                    rd_ptr     <= rd_ptr + 1'b1;
                    item_count <= item_count - 1'b1;
                end
                2'b11: begin // Write and Read simultaneously
                    mem[wr_ptr] <= din;
                    wr_ptr      <= wr_ptr + 1'b1;
                    rd_ptr      <= rd_ptr + 1'b1;
                end
                default: ;
            endcase
        end
    end

endmodule
