`timescale 1ns / 1ps
//=============================================================================
// MMIO Interconnect (Fig 2a & Fig 2b)
//
// Part A: Address decode and write enables (combinational).
// Part B: Read-data multiplexer with 1-cycle registered chip-selects to match
//         synchronous BRAM latency.
//=============================================================================
`ifndef MMIO_INTERCONNECT_V
`define MMIO_INTERCONNECT_V

module mmio_interconnect (
    input  wire        clk,
    input  wire        reset_n,

    // CPU Data Memory Bus (EX / WB stage)
    input  wire [31:0] d_addr,         // byte address used for WRITE decode (store in WB stage)
    input  wire [31:0] d_raddr,        // byte address used for READ select (load in EX stage)
    input  wire [31:0] d_wdata,        // store data
    input  wire [3:0]  d_wstrb,        // byte write enables
    input  wire        d_we,           // write enable strobe
    input  wire        d_re,           // read enable strobe
    output wire [31:0] d_rdata,        // read data back to CPU

    // Subsystem Read Data Inputs (1-cycle read latency)
    input  wire [31:0] rd_dmem,        // from Data Memory BRAM (0x0000_0000)
    input  wire [31:0] rd_in,          // from Input Controller (0x8000_0000)
    input  wire [31:0] rd_tmr,         // from Cooldown Timers (0x8000_0010)
    input  wire [31:0] rd_col,         // from Collision Engine (0x8000_0020)
    input  wire [31:0] rd_perf,        // from Cycle Profiling Telemetry (0x8000_0030)
    input  wire [31:0] rd_maze,        // from Maze RAM Copy V CPU port (0x8000_0100)

    // Subsystem Control Outputs (Fig 2a)
    output wire        cs_dmem,
    output wire [3:0]  dmem_we,        // byte enables for data memory
    output wire        cs_in,
    output wire        cs_tmr,
    output wire        wr_en_tmr,
    output wire        cs_col,
    output wire        wr_en_col,
    output wire        cs_spr,
    output wire        wr_en_spr,
    output wire        cs_maze,
    output wire        wr_en_maze,
    output wire        uart_tx_pin
);

    // =========================================================================
    // Part A: Address Decode (Fig 2a)
    // =========================================================================
    // addr[31] == 0 selects standard Data Memory (stack, globals, LUTs)
    assign cs_dmem = (d_addr[31] == 1'b0);
    assign dmem_we = {4{cs_dmem && d_we}} & d_wstrb;

    // addr[31] == 1 selects the MMIO peripheral window (0x8000_xxxx)
    wire mmio_sel = d_addr[31];

    // P1/P2 Input Registers: 0x8000_0000, 0x8000_0004 (addr[11:3] == 9'h000)
    assign cs_in = mmio_sel && (d_addr[11:3] == 9'h000);

    // Cooldown Timers: 0x8000_0010, 0x8000_0014 (addr[11:3] == 9'h002)
    assign cs_tmr    = mmio_sel && (d_addr[11:3] == 9'h002);
    assign wr_en_tmr = cs_tmr && d_we;

    // Collision Engine: 0x8000_0020..0x8000_002C (addr[11:4] == 8'h02)
    assign cs_col    = mmio_sel && (d_addr[11:4] == 8'h02);
    assign wr_en_col = cs_col && d_we;

    // Sprite & HUD Register File: 0x8000_0040..0x7F and 0x8000_0080..0x87
    // addr[11:6] == 6'h01 (0x40..0x7F) OR addr[11:3] == 9'h010 (0x80..0x87)
    assign cs_spr    = mmio_sel && ((d_addr[11:6] == 6'h01) || (d_addr[11:3] == 9'h010));
    assign wr_en_spr = cs_spr && d_we;

    // Maze Tile RAM (400 words): 0x8000_0100..0x8000_073F (addr[11:8] in 1..7)
    assign cs_maze    = mmio_sel && (d_addr[11:8] >= 4'h1 && d_addr[11:8] <= 4'h7);
    assign wr_en_maze = cs_maze && d_we;

    // Simulation Console Print & Status Port: 0x8000_0008 (char) & 0x8000_000C (status)
    // -------------------------------------------------------------------------
    // 1. Hardware UART Transmit Controller with 128-Byte FIFO Buffer
    // -------------------------------------------------------------------------
    // Decouples the 50 MHz CPU from the slow 115,200 baud serial link (~4,340
    // cycles/byte). CPU bursts up to 128 characters in 1 cycle each to 0x8000_0008
    // without waiting, reducing a 40-char status line from ~173,600 cycles to ~120 cycles.
    //
    //   0x8000_0008 (Write): Non-blocking push to 128-byte FIFO
    //   0x8000_0008 (Read) : {16'd0, uart_count[7:0], 5'd0, fifo_empty, fifo_full, tx_busy}
    // -------------------------------------------------------------------------
    parameter UART_CLK_DIV = 434; // 50,000,000 / 115,200 = 434 clocks/bit

    wire cs_sim_out = mmio_sel && (d_addr[11:2] == 10'h002); // 0x8000_0008
    wire cs_sim_res = mmio_sel && (d_addr[11:2] == 10'h003); // 0x8000_000C

    reg [7:0]  uart_fifo [0:127];
    reg [6:0]  uart_wr_ptr;
    reg [6:0]  uart_rd_ptr;
    reg [7:0]  uart_count;

    reg [9:0]  uart_shift_reg;
    reg [15:0] uart_baud_cnt;
    reg [3:0]  uart_bit_cnt;
    reg        uart_tx_busy;

    wire uart_fifo_empty = (uart_count == 8'd0);
    wire uart_fifo_full  = (uart_count == 8'd128);
    wire uart_push       = d_we && cs_sim_out && !uart_fifo_full;
    wire uart_pop        = !uart_tx_busy && !uart_fifo_empty;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            uart_wr_ptr    <= 7'd0;
            uart_rd_ptr    <= 7'd0;
            uart_count     <= 8'd0;
            uart_shift_reg <= 10'h3FF;
            uart_baud_cnt  <= 16'd0;
            uart_bit_cnt   <= 4'd0;
            uart_tx_busy   <= 1'b0;
        end else begin
            // FIFO write
            if (uart_push) begin
                uart_fifo[uart_wr_ptr] <= d_wdata[7:0];
                uart_wr_ptr <= uart_wr_ptr + 7'd1;
            end

            // FIFO read & UART serializer state machine
            if (uart_pop) begin
                uart_shift_reg <= {1'b1, uart_fifo[uart_rd_ptr], 1'b0}; // Stop(1), Data[7:0], Start(0)
                uart_rd_ptr    <= uart_rd_ptr + 7'd1;
                uart_tx_busy   <= 1'b1;
                uart_baud_cnt  <= 16'd0;
                uart_bit_cnt   <= 4'd0;
            end else if (uart_tx_busy) begin
                if (uart_baud_cnt >= (UART_CLK_DIV - 1)) begin
                    uart_baud_cnt <= 16'd0;
                    if (uart_bit_cnt == 4'd9) begin
                        uart_tx_busy   <= 1'b0;
                        uart_shift_reg <= 10'h3FF;
                    end else begin
                        uart_bit_cnt   <= uart_bit_cnt + 4'd1;
                        uart_shift_reg <= {1'b1, uart_shift_reg[9:1]};
                    end
                end else begin
                    uart_baud_cnt <= uart_baud_cnt + 16'd1;
                end
            end

            // Update FIFO occupancy count
            case ({uart_push, uart_pop})
                2'b10: uart_count <= uart_count + 8'd1;
                2'b01: uart_count <= uart_count - 8'd1;
                default: ;
            endcase
        end
    end

    assign uart_tx_pin = uart_shift_reg[0];
    wire [31:0] rd_uart_status = {16'd0, uart_count, 5'd0, uart_fifo_empty, uart_fifo_full, uart_tx_busy};

`ifndef SYNTHESIS
    always @(posedge clk) begin
        if (d_we && cs_sim_out) begin
            $write("%c", d_wdata[7:0]);
            $fflush();
        end
        if (d_we && cs_sim_res) begin
            if (d_wdata == 32'hCAFEF00D)
                $display("\n>>> [TEST SUITE PASS] All assertions completed successfully! <<<\n");
            else if (d_wdata == 32'hDEADBEEF)
                $display("\n>>> [TEST SUITE FAIL] An assertion check failed! <<<\n");
        end
    end
`endif

    // =========================================================================
    // Part B: Read-Data Path (Fig 2b)
    // Synchronous BRAM returns read data 1 clock cycle after the address is
    // presented. The chip-selects are registered by 1 clock cycle to align.
    // =========================================================================
    // The CPU can issue a load (EX stage) in the very same clock in which an
    // earlier store is committed (WB stage). Read selects therefore MUST be
    // decoded from the dedicated read address, never from the write address,
    // otherwise the load is steered to the wrong peripheral and returns 0/garbage
    // (which previously corrupted the saved return address and made the CPU
    // restart from PC=0 every game frame).
    wire rmmio_sel = d_raddr[31];
    wire rcs_dmem  = ~rmmio_sel;
    wire rcs_in    = rmmio_sel && (d_raddr[11:3] == 9'h000);
    wire rcs_uart  = rmmio_sel && (d_raddr[11:3] == 9'h001); // 0x8000_0008, 0x8000_000C
    wire rcs_tmr   = rmmio_sel && (d_raddr[11:3] == 9'h002);
    wire rcs_col   = rmmio_sel && (d_raddr[11:4] == 8'h02);
    wire rcs_perf  = rmmio_sel && (d_raddr[11:4] == 8'h03 || d_raddr[11:4] == 8'h09);
    wire rcs_maze  = rmmio_sel && (d_raddr[11:8] >= 4'h1 && d_raddr[11:8] <= 4'h7);

    reg cs_dmem_q;
    reg cs_in_q;
    reg cs_uart_q;
    reg cs_tmr_q;
    reg cs_col_q;
    reg cs_perf_q;
    reg cs_maze_q;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            cs_dmem_q <= 1'b0;
            cs_in_q   <= 1'b0;
            cs_uart_q <= 1'b0;
            cs_tmr_q  <= 1'b0;
            cs_col_q  <= 1'b0;
            cs_perf_q <= 1'b0;
            cs_maze_q <= 1'b0;
        end else begin
            cs_dmem_q <= rcs_dmem;
            cs_in_q   <= rcs_in;
            cs_uart_q <= rcs_uart;
            cs_tmr_q  <= rcs_tmr;
            cs_col_q  <= rcs_col;
            cs_perf_q <= rcs_perf;
            cs_maze_q <= rcs_maze;
        end
    end

    // 7-input AND-OR read multiplexer
    assign d_rdata = ({32{cs_dmem_q}} & rd_dmem)        |
                     ({32{cs_in_q}}   & rd_in)          |
                     ({32{cs_uart_q}} & rd_uart_status) |
                     ({32{cs_tmr_q}}  & rd_tmr)         |
                     ({32{cs_col_q}}  & rd_col)         |
                     ({32{cs_perf_q}} & rd_perf)        |
                     ({32{cs_maze_q}} & rd_maze);

endmodule

`endif
