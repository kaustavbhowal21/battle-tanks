`timescale 1ns / 1ps
//=============================================================================
// RV32IM Extension Test Harness Testbench
// Connects the RV32IM soft-core directly to instruction memory, data memory,
// and the MMIO interconnect with console text output for verbal verification.
//=============================================================================

module tb_rv32im_test;

    reg clk;
    reg reset_n;

    // 50 MHz clock (period 20 ns)
    initial begin
        clk = 1'b0;
        forever #10 clk = ~clk;
    end

    // Reset sequence
    initial begin
        reset_n = 1'b0;
        #100;
        reset_n = 1'b1;
    end

    // CPU Bus Signals
    wire [31:0] pc_out;
    wire        exception;

    wire [31:0] inst_mem_address;
    wire [31:0] inst_mem_read_data;

    wire        dmem_read_ready;
    wire [31:0] dmem_read_address;
    wire        dmem_write_ready;
    wire [31:0] dmem_write_address;
    wire [31:0] dmem_write_data;
    wire [3:0]  dmem_write_byte;
    wire [31:0] dmem_cpu_rdata;

    wire [31:0] mem_bus_addr = dmem_write_ready ? dmem_write_address : dmem_read_address;
    wire        mem_bus_we   = dmem_write_ready;
    wire        mem_bus_re   = dmem_read_ready;

    wire [31:0] rd_dmem;
    wire        cs_dmem;
    wire [3:0]  dmem_we;

    // 1. Processor Core
    pipe u_cpu (
        .clk                (clk),
        .reset              (reset_n),
        .stall              (1'b0),
        .exception          (exception),
        .pc_out             (pc_out),

        .inst_mem_is_valid  (1'b1),
        .inst_mem_read_data (inst_mem_read_data),

        .dmem_read_data_temp(dmem_cpu_rdata),
        .dmem_write_valid   (1'b1),
        .dmem_read_valid    (1'b1),

        .inst_mem_address   (inst_mem_address),
        .dmem_read_ready    (dmem_read_ready),
        .dmem_read_address  (dmem_read_address),
        .dmem_write_ready   (dmem_write_ready),
        .dmem_write_address (dmem_write_address),
        .dmem_write_data    (dmem_write_data),
        .dmem_write_byte    (dmem_write_byte)
    );

    // 2. Instruction Memory (4 KB)
    instr_mem #(
        .HEX_FILE("imem.hex")
    ) u_imem (
        .clk   (clk),
        .pc    (inst_mem_address),
        .instr (inst_mem_read_data)
    );

    // 3. Data Memory (4 KB)
    data_mem #(
        .HEX_FILE("dmem.hex")
    ) u_dmem (
        .clk   (clk),
        .re    (dmem_read_ready && !dmem_read_address[31]),
        .raddr (dmem_read_address),
        .rdata (rd_dmem),
        .we    (dmem_write_ready && cs_dmem),
        .waddr (dmem_write_address),
        .wdata (dmem_write_data),
        .wstrb (dmem_we)
    );

    // 4. MMIO Interconnect with Console Test Output
    mmio_interconnect u_mmio (
        .clk         (clk),
        .reset_n     (reset_n),
        .d_addr      (mem_bus_addr),
        .d_raddr     (dmem_read_address),
        .d_wdata     (dmem_write_data),
        .d_wstrb     (dmem_write_byte),
        .d_we        (mem_bus_we),
        .d_re        (mem_bus_re),
        .d_rdata     (dmem_cpu_rdata),

        .rd_dmem     (rd_dmem),
        .rd_in       (32'h0),
        .rd_tmr      (32'h0),
        .rd_col      (32'h0),
        .rd_maze     (32'h0),

        .cs_dmem     (cs_dmem),
        .dmem_we     (dmem_we),
        .cs_in       (),
        .cs_tmr      (),
        .wr_en_tmr   (),
        .cs_col      (),
        .wr_en_col   (),
        .cs_spr      (),
        .wr_en_spr   (),
        .cs_maze     (),
        .wr_en_maze  ()
    );





    // Watch for test termination signals
    always @(posedge clk) begin
        if (mem_bus_we && (mem_bus_addr == 32'h8000000C)) begin
            if (dmem_write_data == 32'hCAFEF00D) begin
                $display("\n[TESTBENCH] Simulation completed with SUCCESS.");
                $finish;
            end else if (dmem_write_data == 32'hDEADBEEF) begin
                $display("\n[TESTBENCH] Simulation completed with FAILURE.");
                $finish;
            end
        end
        if (exception) begin
            $display("\n[TESTBENCH] FATAL: CPU signaled an illegal instruction / alignment exception at PC=0x%08h!", pc_out);
            $finish;
        end
    end

    // Safety timeout (500,000 ns = 25,000 CPU cycles)
    initial begin
        #500000;
        $display("\n[TESTBENCH] ERROR: Test timed out after 500 us (25,000 cycles)!");
        $finish;
    end

endmodule
