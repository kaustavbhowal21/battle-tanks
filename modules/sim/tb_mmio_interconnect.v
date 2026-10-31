`timescale 1ns / 1ps
//=============================================================================
// Testbench: MMIO Interconnect Verification
// Verifies:
// 1. Part A: Address decode logic (DMEM vs MMIO peripherals).
//    - cs_dmem (addr[31] == 0)
//    - cs_in   (0x8000_0000)
//    - cs_tmr  (0x8000_0010)
//    - cs_col  (0x8000_0020)
//    - cs_spr  (0x8000_0040)
//    - cs_maze (0x8000_0100)
// 2. Write enable and byte-strobe gating.
// 3. Part B: 1-cycle registered chip-select read data multiplexer.
//=============================================================================

module tb_mmio_interconnect;

    reg        clk;
    reg        reset_n;

    reg  [31:0] d_addr;
    reg  [31:0] d_wdata;
    reg  [3:0]  d_wstrb;
    reg        d_we;
    reg        d_re;
    wire [31:0] d_rdata;

    reg  [31:0] rd_dmem;
    reg  [31:0] rd_in;
    reg  [31:0] rd_tmr;
    reg  [31:0] rd_col;
    reg  [31:0] rd_maze;

    wire        cs_dmem;
    wire [3:0]  dmem_we;
    wire        cs_in;
    wire        cs_tmr;
    wire        wr_en_tmr;
    wire        cs_col;
    wire        wr_en_col;
    wire        cs_spr;
    wire        wr_en_spr;
    wire        cs_maze;
    wire        wr_en_maze;

    integer errors = 0;

    mmio_interconnect dut (
        .clk        (clk),
        .reset_n    (reset_n),
        .d_addr     (d_addr),
        .d_raddr    (d_addr),
        .d_wdata    (d_wdata),
        .d_wstrb    (d_wstrb),
        .d_we       (d_we),
        .d_re       (d_re),
        .d_rdata    (d_rdata),
        .rd_dmem    (rd_dmem),
        .rd_in      (rd_in),
        .rd_tmr     (rd_tmr),
        .rd_col     (rd_col),
        .rd_maze    (rd_maze),
        .cs_dmem    (cs_dmem),
        .dmem_we    (dmem_we),
        .cs_in      (cs_in),
        .cs_tmr     (cs_tmr),
        .wr_en_tmr  (wr_en_tmr),
        .cs_col     (cs_col),
        .wr_en_col  (wr_en_col),
        .cs_spr     (cs_spr),
        .wr_en_spr  (wr_en_spr),
        .cs_maze    (cs_maze),
        .wr_en_maze (wr_en_maze)
    );

    // 50 MHz clock
    initial begin
        clk = 1'b0;
        forever #10 clk = ~clk;
    end

    initial begin
        $display("==========================================================");
        $display("   TESTBENCH: MMIO INTERCONNECT VERIFICATION              ");
        $display("==========================================================");

        reset_n = 1'b0;
        d_addr  = 32'h0000_0000;
        d_wdata = 32'h0000_0000;
        d_wstrb = 4'b0000;
        d_we    = 1'b0;
        d_re    = 1'b0;

        rd_dmem = 32'hDEAD_BEEF;
        rd_in   = 32'h1111_1111;
        rd_tmr  = 32'h2222_2222;
        rd_col  = 32'h3333_3333;
        rd_maze = 32'h4444_4444;

        #100;
        @(posedge clk);
        reset_n = 1'b1;
        @(posedge clk);

        // =====================================================================
        // Test 1: Data Memory Address Decoding (addr[31] == 0)
        // =====================================================================
        $display("  [TEST 1] Testing Data Memory (DMEM) Window Decode...");
        d_addr = 32'h0000_0500;
        d_we   = 1'b1;
        d_wstrb = 4'b1111;
        #5;
        if (cs_dmem !== 1'b1 || dmem_we !== 4'b1111 || cs_in !== 1'b0 || cs_tmr !== 1'b0) begin
            $display("  [FAIL] DMEM decode failed! cs_dmem=%b dmem_we=%b", cs_dmem, dmem_we);
            errors = errors + 1;
        end else begin
            $display("  [PASS] DMEM correctly decoded (cs_dmem=1, dmem_we=4'b1111).");
        end

        // Check read mux pipelining for DMEM
        @(posedge clk);
        #5;
        if (d_rdata !== 32'hDEAD_BEEF) begin
            $display("  [FAIL] DMEM read mux failed! Expected 0xDEADBEEF, got 0x%08h", d_rdata);
            errors = errors + 1;
        end else begin
            $display("  [PASS] DMEM read data returned via registered mux.");
        end

        // =====================================================================
        // Test 2: Input Controller Window (0x8000_0000)
        // =====================================================================
        $display("  [TEST 2] Testing Input Controller Window (0x8000_0000)...");
        d_addr = 32'h8000_0000;
        d_we   = 1'b0;
        #5;
        if (cs_in !== 1'b1 || cs_dmem !== 1'b0) begin
            $display("  [FAIL] cs_in failed to assert!");
            errors = errors + 1;
        end
        @(posedge clk);
        #5;
        if (d_rdata !== 32'h1111_1111) begin
            $display("  [FAIL] Input controller read failed! Got 0x%08h", d_rdata);
            errors = errors + 1;
        end else begin
            $display("  [PASS] Input controller window decoded & read correctly.");
        end

        // =====================================================================
        // Test 3: Cooldown Timers Window (0x8000_0010)
        // =====================================================================
        $display("  [TEST 3] Testing Cooldown Timers Window (0x8000_0014)...");
        d_addr = 32'h8000_0014;
        d_we   = 1'b1;
        #5;
        if (cs_tmr !== 1'b1 || wr_en_tmr !== 1'b1) begin
            $display("  [FAIL] cs_tmr or wr_en_tmr failed!");
            errors = errors + 1;
        end
        @(posedge clk);
        #5;
        if (d_rdata !== 32'h2222_2222) begin
            $display("  [FAIL] Timer read failed! Got 0x%08h", d_rdata);
            errors = errors + 1;
        end else begin
            $display("  [PASS] Timer window decoded & write-enabled correctly.");
        end

        // =====================================================================
        // Test 4: Collision Engine Window (0x8000_0020)
        // =====================================================================
        $display("  [TEST 4] Testing Collision Engine Window (0x8000_0020)...");
        d_addr = 32'h8000_0024;
        d_we   = 1'b1;
        #5;
        if (cs_col !== 1'b1 || wr_en_col !== 1'b1) begin
            $display("  [FAIL] cs_col or wr_en_col failed!");
            errors = errors + 1;
        end
        @(posedge clk);
        #5;
        if (d_rdata !== 32'h3333_3333) begin
            $display("  [FAIL] Collision read failed! Got 0x%08h", d_rdata);
            errors = errors + 1;
        end else begin
            $display("  [PASS] Collision window decoded & read correctly.");
        end

        // =====================================================================
        // Test 5: Sprite & HUD Regfile Window (0x8000_0040)
        // =====================================================================
        $display("  [TEST 5] Testing Sprite Regfile Window (0x8000_0040)...");
        d_addr = 32'h8000_0048;
        d_we   = 1'b1;
        #5;
        if (cs_spr !== 1'b1 || wr_en_spr !== 1'b1) begin
            $display("  [FAIL] cs_spr or wr_en_spr failed!");
            errors = errors + 1;
        end else begin
            $display("  [PASS] Sprite regfile write decoded correctly.");
        end

        // =====================================================================
        // Test 6: Maze Tile RAM Window (0x8000_0100)
        // =====================================================================
        $display("  [TEST 6] Testing Maze Tile RAM Window (0x8000_0100)...");
        d_addr = 32'h8000_0120;
        d_we   = 1'b1;
        #5;
        if (cs_maze !== 1'b1 || wr_en_maze !== 1'b1) begin
            $display("  [FAIL] cs_maze or wr_en_maze failed!");
            errors = errors + 1;
        end
        @(posedge clk);
        #5;
        if (d_rdata !== 32'h4444_4444) begin
            $display("  [FAIL] Maze RAM read failed! Got 0x%08h", d_rdata);
            errors = errors + 1;
        end else begin
            $display("  [PASS] Maze Tile RAM window decoded & read correctly.");
        end

        $display("==========================================================");
        if (errors == 0) begin
            $display(">> TEST PASSED: MMIO Interconnect verified with 0 errors!");
        end else begin
            $display(">> TEST FAILED with %0d errors!", errors);
        end
        $display("==========================================================");

        $finish;
    end

endmodule
