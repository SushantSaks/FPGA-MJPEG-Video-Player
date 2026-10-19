`timescale 1ns / 1ps
// ============================================================================
// Module: qspi_controller
// Description: Multi-mode QSPI Flash Controller for Winbond W25Q128 (16 MB)
// Standard: Verilog-2001
// ============================================================================

module qspi_controller #(
    parameter integer CLK_DIV = 8 // 100 MHz in -> 12.5 MHz SCK (40ns half-period, robust against STARTUPE2/flash delays)
) (
    input  wire        clk,
    input  wire        rst_n,

    // Command Interface
    input  wire [2:0]  cmd_op,         // 0: Read, 1: Page Prog, 2: Sector Erase, 3: Block Erase, 4: WREN, 5: RDSR, 6: JEDEC_ID
    input  wire [23:0] cmd_addr,       // 24-bit byte address in Flash
    input  wire [8:0]  cmd_byte_len,   // Number of bytes (for read/write, up to 256)
    input  wire        cmd_start,      // Pulse high to execute command
    output wire        cmd_busy,       // High while transaction is active
    output wire        cmd_done,       // Single-cycle pulse on completion

    // Streaming Read Interface
    output wire [7:0]  rd_data,        // Read data byte from Flash
    output wire        rd_valid,       // Asserted when rd_data is valid
    input  wire        rd_ready,       // Backpressure from consumer (e.g. MJPEG parser)
    input  wire        stream_mode,    // 1 = continuous read mode until stream_stop
    input  wire        stream_stop,    // 1 = terminate streaming read

    // Write Data Interface (Page Program)
    input  wire [7:0]  wr_data,        // Data byte to write to Flash
    input  wire        wr_valid,       // Asserted when wr_data is ready
    output wire        wr_ready,       // Ready to accept next byte to program

    // Status Registers
    output wire [7:0]  flash_status_reg, // Latched Status Register (WEL, BUSY, etc.)
    output wire [23:0] flash_jedec_id,   // Latched JEDEC ID (Manufacturer, Type, Capacity)

    // Physical SPI / QSPI Pins (Standard SPI Mode 0)
    output wire        qspi_cs_n,
    output wire        qspi_sck,
    output wire        qspi_io0_oe,
    output wire        qspi_io0_do,
    input  wire        qspi_io0_di,
    output wire        qspi_io1_oe,
    output wire        qspi_io1_do,
    input  wire        qspi_io1_di,
    output wire        qspi_io2_oe,
    output wire        qspi_io2_do,
    input  wire        qspi_io2_di,
    output wire        qspi_io3_oe,
    output wire        qspi_io3_do,
    input  wire        qspi_io3_di
);

    // Command Opcodes
    localparam [2:0] OP_READ         = 3'd0;
    localparam [2:0] OP_PAGE_PROG    = 3'd1;
    localparam [2:0] OP_SECTOR_ERASE = 3'd2;
    localparam [2:0] OP_BLOCK_ERASE  = 3'd3;
    localparam [2:0] OP_WREN         = 3'd4;
    localparam [2:0] OP_RDSR         = 3'd5;
    localparam [2:0] OP_JEDEC_ID     = 3'd6;

    // Flash Instruction Bytes
    localparam [7:0] FLASH_CMD_READ   = 8'h03;
    localparam [7:0] FLASH_CMD_PP     = 8'h02;
    localparam [7:0] FLASH_CMD_SE     = 8'h20;
    localparam [7:0] FLASH_CMD_BE     = 8'hD8;
    localparam [7:0] FLASH_CMD_WREN   = 8'h06;
    localparam [7:0] FLASH_CMD_RDSR   = 8'h05;
    localparam [7:0] FLASH_CMD_JEDEC  = 8'h9F;

    // Pin defaults for Standard SPI
    assign qspi_io0_oe = 1'b1;  // MOSI is driven
    assign qspi_io1_oe = 1'b0;  // MISO is input
    assign qspi_io2_oe = 1'b1;
    assign qspi_io2_do = 1'b1;  // WP# held high
    assign qspi_io3_oe = 1'b1;
    assign qspi_io3_do = 1'b1;  // HOLD# held high
    assign qspi_io1_do = 1'b0;

    // Controller FSM
    localparam [3:0] ST_IDLE        = 4'd0;
    localparam [3:0] ST_PREP_CMD    = 4'd1;
    localparam [3:0] ST_SEND_CMD    = 4'd2;
    localparam [3:0] ST_SEND_ADDR   = 4'd3;
    localparam [3:0] ST_READ_DATA   = 4'd4;
    localparam [3:0] ST_READ_WAIT   = 4'd5;
    localparam [3:0] ST_WRITE_WAIT  = 4'd6;
    localparam [3:0] ST_WRITE_DATA  = 4'd7;
    localparam [3:0] ST_READ_STATUS = 4'd8;
    localparam [3:0] ST_READ_ID     = 4'd9;
    localparam [3:0] ST_CS_DESELECT = 4'd10;
    localparam [3:0] ST_DONE        = 4'd11;

    reg [3:0] state;

    // Clock and Status Registers
    reg sck_reg;
    assign qspi_sck = sck_reg;

    localparam integer HALF_PERIOD = (CLK_DIV >= 2) ? (CLK_DIV / 2) : 1;
    reg [3:0] div_cnt;
    wire sck_tick = (div_cnt == HALF_PERIOD[3:0] - 4'd1);

    wire sck_active = (state == ST_SEND_CMD) || (state == ST_SEND_ADDR) ||
                      (state == ST_WRITE_DATA) || (state == ST_READ_DATA) ||
                      (state == ST_READ_STATUS) || (state == ST_READ_ID);

    reg cs_n_reg;
    assign qspi_cs_n = cs_n_reg;
    assign cmd_busy  = (state != ST_IDLE);

    reg done_pulse;
    assign cmd_done = done_pulse;

    // Shift registers
    reg [7:0]  shift_out;
    reg [7:0]  shift_in;
    reg [31:0] addr_shifter;
    reg [2:0]  bit_cnt;
    reg [8:0]  byte_cnt;
    reg [8:0]  bytes_remaining;

    reg [7:0]  latched_status;
    reg [23:0] latched_id;
    reg        stop_req;

    assign flash_status_reg = latched_status;
    assign flash_jedec_id   = latched_id;

    // Read interface
    reg [7:0] rd_data_reg;
    reg       rd_val_reg;
    assign rd_data  = rd_data_reg;
    assign rd_valid = rd_val_reg;

    // Write interface
    reg wr_rdy_reg;
    assign wr_ready = wr_rdy_reg && !wr_valid;

    // MOSI output is MSB of shift_out
    assign qspi_io0_do = shift_out[7];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state           <= ST_IDLE;
            cs_n_reg        <= 1'b1;
            sck_reg         <= 1'b0;
            div_cnt         <= 4'd0;
            shift_out       <= 8'd0;
            shift_in        <= 8'd0;
            addr_shifter    <= 32'd0;
            bit_cnt         <= 3'd0;
            byte_cnt        <= 9'd0;
            bytes_remaining <= 9'd0;
            done_pulse      <= 1'b0;
            rd_val_reg      <= 1'b0;
            rd_data_reg     <= 8'd0;
            wr_rdy_reg      <= 1'b0;
            latched_status  <= 8'd0;
            latched_id      <= 24'd0;
            stop_req        <= 1'b0;
        end else begin
            done_pulse <= 1'b0;
            rd_val_reg <= 1'b0;
            wr_rdy_reg <= 1'b0;

            if (sck_active) begin
                if (sck_tick) div_cnt <= 4'd0;
                else          div_cnt <= div_cnt + 4'd1;
            end else begin
                div_cnt <= 4'd0;
            end

            if (stream_stop) stop_req <= 1'b1;

            case (state)
                ST_IDLE: begin
                    cs_n_reg <= 1'b1;
                    sck_reg  <= 1'b0;
                    stop_req <= 1'b0;

                    if (cmd_start) begin
                        cs_n_reg        <= 1'b0; // Assert CS#
                        bit_cnt         <= 3'd7;
                        bytes_remaining <= cmd_byte_len;
                        byte_cnt        <= 9'd0;
                        state           <= ST_PREP_CMD;
                    end
                end

                ST_PREP_CMD: begin
                    // Load opcode into shift_out
                    case (cmd_op)
                        OP_READ:         shift_out <= FLASH_CMD_READ;
                        OP_PAGE_PROG:    shift_out <= FLASH_CMD_PP;
                        OP_SECTOR_ERASE: shift_out <= FLASH_CMD_SE;
                        OP_BLOCK_ERASE:  shift_out <= FLASH_CMD_BE;
                        OP_WREN:         shift_out <= FLASH_CMD_WREN;
                        OP_RDSR:         shift_out <= FLASH_CMD_RDSR;
                        OP_JEDEC_ID:     shift_out <= FLASH_CMD_JEDEC;
                        default:         shift_out <= 8'h00;
                    endcase
                    addr_shifter <= {cmd_addr, 8'd0}; // 24-bit address MSB aligned
                    sck_reg      <= 1'b0;
                    bit_cnt      <= 3'd7;
                    state        <= ST_SEND_CMD;
                end

                ST_SEND_CMD: begin
                    if (sck_tick) begin
                        if (sck_reg == 1'b0) begin
                            // Low-to-high: slave samples MOSI
                            sck_reg <= 1'b1;
                        end else begin
                            // High-to-low: master shifts out next bit
                            sck_reg <= 1'b0;
                            if (bit_cnt == 3'd0) begin
                                bit_cnt <= 3'd7;
                                case (cmd_op)
                                    OP_WREN: begin
                                        state <= ST_CS_DESELECT;
                                    end
                                    OP_RDSR: begin
                                        state <= ST_READ_STATUS;
                                    end
                                    OP_JEDEC_ID: begin
                                        state <= ST_READ_ID;
                                    end
                                    default: begin
                                        // Commands needing 24-bit address
                                        shift_out    <= addr_shifter[31:24];
                                        addr_shifter <= {addr_shifter[23:0], 8'd0};
                                        byte_cnt     <= 9'd1;
                                        state        <= ST_SEND_ADDR;
                                    end
                                endcase
                            end else begin
                                shift_out <= {shift_out[6:0], 1'b0};
                                bit_cnt   <= bit_cnt - 3'd1;
                            end
                        end
                    end
                end

                ST_SEND_ADDR: begin
                    if (sck_tick) begin
                        if (sck_reg == 1'b0) begin
                            sck_reg <= 1'b1;
                        end else begin
                            sck_reg <= 1'b0;
                            if (bit_cnt == 3'd0) begin
                                bit_cnt <= 3'd7;
                                if (byte_cnt == 9'd3) begin
                                    // 24-bit address complete!
                                    byte_cnt <= 9'd0;
                                    case (cmd_op)
                                        OP_READ: begin
                                            state <= ST_READ_DATA;
                                        end
                                        OP_PAGE_PROG: begin
                                            wr_rdy_reg <= 1'b1;
                                            state      <= ST_WRITE_WAIT;
                                        end
                                        default: begin
                                            // Sector / Block erase completes after address
                                            state <= ST_CS_DESELECT;
                                        end
                                    endcase
                                end else begin
                                    shift_out    <= addr_shifter[31:24];
                                    addr_shifter <= {addr_shifter[23:0], 8'd0};
                                    byte_cnt     <= byte_cnt + 9'd1;
                                end
                            end else begin
                                shift_out <= {shift_out[6:0], 1'b0};
                                bit_cnt   <= bit_cnt - 3'd1;
                            end
                        end
                    end
                end

                ST_WRITE_WAIT: begin
                    sck_reg    <= 1'b0;
                    wr_rdy_reg <= 1'b1;
                    if (wr_valid) begin
                        shift_out  <= wr_data;
                        bit_cnt    <= 3'd7;
                        wr_rdy_reg <= 1'b0;
                        state      <= ST_WRITE_DATA;
                    end
                end

                ST_WRITE_DATA: begin
                    if (sck_tick) begin
                        if (sck_reg == 1'b0) begin
                            // Low-to-high: slave samples MOSI
                            sck_reg <= 1'b1;
                        end else begin
                            // High-to-low: shift next bit
                            sck_reg <= 1'b0;
                            if (bit_cnt == 3'd0) begin
                                byte_cnt <= byte_cnt + 9'd1;
                                if (byte_cnt + 9'd1 >= bytes_remaining) begin
                                    state <= ST_CS_DESELECT;
                                end else begin
                                    wr_rdy_reg <= 1'b1;
                                    state      <= ST_WRITE_WAIT;
                                end
                            end else begin
                                shift_out <= {shift_out[6:0], 1'b0};
                                bit_cnt   <= bit_cnt - 3'd1;
                            end
                        end
                    end
                end

                ST_READ_DATA: begin
                    if (sck_tick) begin
                        if (sck_reg == 1'b0) begin
                            // Low-to-high: sample MISO
                            sck_reg  <= 1'b1;
                            shift_in <= {shift_in[6:0], qspi_io1_di};
                        end else begin
                            // High-to-low: SCK falls to 0
                            sck_reg <= 1'b0;
                            if (bit_cnt == 3'd0) begin
                                bit_cnt     <= 3'd7;
                                byte_cnt    <= byte_cnt + 9'd1;
                                rd_data_reg <= shift_in;
                                rd_val_reg  <= 1'b1;
                                state       <= ST_READ_WAIT;
                            end else begin
                                bit_cnt <= bit_cnt - 3'd1;
                            end
                        end
                    end
                end

                ST_READ_WAIT: begin
                    sck_reg    <= 1'b0;
                    rd_val_reg <= 1'b1;
                    if (stream_mode && (stream_stop || stop_req)) begin
                        rd_val_reg <= 1'b0;
                        state      <= ST_CS_DESELECT;
                    end else if (rd_ready) begin
                        rd_val_reg <= 1'b0;
                        if (!stream_mode && (byte_cnt >= bytes_remaining)) begin
                            state <= ST_CS_DESELECT;
                        end else begin
                            state <= ST_READ_DATA;
                        end
                    end
                end

                ST_READ_STATUS: begin
                    if (sck_tick) begin
                        if (sck_reg == 1'b0) begin
                            sck_reg  <= 1'b1;
                            shift_in <= {shift_in[6:0], qspi_io1_di};
                        end else begin
                            sck_reg <= 1'b0;
                            if (bit_cnt == 3'd0) begin
                                latched_status <= shift_in;
                                state          <= ST_CS_DESELECT;
                            end else begin
                                bit_cnt <= bit_cnt - 3'd1;
                            end
                        end
                    end
                end

                ST_READ_ID: begin
                    if (sck_tick) begin
                        if (sck_reg == 1'b0) begin
                            sck_reg  <= 1'b1;
                            shift_in <= {shift_in[6:0], qspi_io1_di};
                        end else begin
                            sck_reg <= 1'b0;
                            if (bit_cnt == 3'd0) begin
                                latched_id <= {latched_id[15:0], shift_in};
                                bit_cnt    <= 3'd7;
                                byte_cnt   <= byte_cnt + 9'd1;
                                if (byte_cnt == 9'd2) begin
                                    state <= ST_CS_DESELECT;
                                end
                            end else begin
                                bit_cnt <= bit_cnt - 3'd1;
                            end
                        end
                    end
                end

                ST_CS_DESELECT: begin
                    sck_reg  <= 1'b0;
                    cs_n_reg <= 1'b1;
                    if (bit_cnt == 3'd7) begin
                        state <= ST_DONE;
                    end else begin
                        bit_cnt <= bit_cnt + 3'd1;
                    end
                end

                ST_DONE: begin
                    done_pulse <= 1'b1;
                    state      <= ST_IDLE;
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule
