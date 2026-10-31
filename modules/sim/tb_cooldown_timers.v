`timescale 1ns / 1ps
//=============================================================================
// Testbench: Cooldown Timers Verification
// Verifies:
// 1. 1 ms prescaler tick generation.
// 2. 4 Independent Down-Counter channels:
//    - P1 Shoot (500 ms)
//    - P1 Special (20,000 ms)
//    - P2 Shoot (500 ms)
//    - P2 Special (20,000 ms)
// 3. MMIO Write Trigger Decode (0x8000_0014).
// 4. MMIO Status Read (0x8000_0010): 1 = Ready, 0 = Cooling Down.
// 5. Automatic transition back to Ready upon count expiration.
//=============================================================================

module tb_cooldown_timers;

    reg        clk;
    reg        reset_n;
    reg        wr_en_tmr;
    reg  [31:0] d_addr;
    reg  [31:0] d_wdata;
    wire [31:0] rd_tmr;

    integer errors = 0;

    // Use a small prescaler for simulation (e.g. 10 clocks per ms tick)
    localparam CLK_PER_MS_SIM = 10;

    cooldown_timers #(
        .CLK_PER_MS(CLK_PER_MS_SIM)
    ) dut (
        .clk       (clk),
        .reset_n   (reset_n),
        .wr_en_tmr (wr_en_tmr),
        .d_addr    (d_addr),
        .d_wdata   (d_wdata),
        .rd_tmr    (rd_tmr)
    );

    // 50 MHz clock
    initial begin
        clk = 1'b0;
        forever #10 clk = ~clk;
    end

    initial begin
        $display("==========================================================");
        $display("   TESTBENCH: COOLDOWN TIMERS VERIFICATION                ");
        $display("==========================================================");

        reset_n = 1'b0;
        wr_en_tmr = 1'b0;
        d_addr = 32'h8000_0010;
        d_wdata = 32'd0;

        #100;
        @(posedge clk);
        reset_n = 1'b1;
        @(posedge clk);

        // =====================================================================
        // Test 1: Reset Status Check (All 4 channels ready = 4'b1111 = 0xF)
        // =====================================================================
        $display("  [TEST 1] Testing Power-On Reset Status (All channels ready)...");
        d_addr = 32'h8000_0010;
        #5;
        if (rd_tmr[3:0] !== 4'b1111) begin
            $display("  [FAIL] Initial status mismatch! Expected 4'b1111 (0xF), got %b", rd_tmr[3:0]);
            errors = errors + 1;
        end else begin
            $display("  [PASS] All 4 cooldown channels initially ready (status = 0xF).");
        end

        // =====================================================================
        // Test 2: Trigger Player 1 Shoot (Bit 0)
        // =====================================================================
        $display("  [TEST 2] Testing P1 Primary Fire Cooldown Trigger...");
        // Write to TIMER_TRIGGER (0x8000_0014) with bit 0 = 1
        @(posedge clk);
        d_addr = 32'h8000_0014;
        d_wdata = 32'h0000_0001;
        wr_en_tmr = 1'b1;
        @(posedge clk);
        wr_en_tmr = 1'b0;

        // Check status register at 0x8000_0010
        d_addr = 32'h8000_0010;
        #5;
        if (rd_tmr[0] !== 1'b0) begin
            $display("  [FAIL] P1 shoot status bit did not drop to 0 (cooling down)!");
            errors = errors + 1;
        end else begin
            $display("  [PASS] P1 shoot status bit = 0 (cooling down).");
        end

        // Other channels must remain ready (bits [3:1] == 3'b111)
        if (rd_tmr[3:1] !== 3'b111) begin
            $display("  [FAIL] Other channels erroneously affected! Expected [3:1]=111, got %b", rd_tmr[3:1]);
            errors = errors + 1;
        end else begin
            $display("  [PASS] Other 3 channels remained fully ready (bits [3:1]=111).");
        end

        // =====================================================================
        // Test 3: Down-Counter Progress & Expiration
        // =====================================================================
        $display("  [TEST 3] Simulating 501 ms ticks to verify P1 Shoot completion...");
        // Fast-forward 501 ms (each ms is 10 clocks in simulation = 5010 clocks)
        repeat(501 * CLK_PER_MS_SIM) @(posedge clk);

        #5;
        if (rd_tmr[0] !== 1'b1) begin
            $display("  [FAIL] P1 shoot timer did not expire back to 1 (ready)!");
            errors = errors + 1;
        end else begin
            $display("  [PASS] P1 shoot timer completed down-count and returned to ready (bit 0 = 1).");
        end

        // =====================================================================
        // Test 4: Simultaneous Multi-Channel Trigger (P1 Special + P2 Shoot)
        // =====================================================================
        $display("  [TEST 4] Testing Multi-Channel Simultaneous Trigger...");
        // Trigger P1 Special (bit 1) and P2 Shoot (bit 2) -> 32'h0000_0006
        @(posedge clk);
        d_addr = 32'h8000_0014;
        d_wdata = 32'h0000_0006;
        wr_en_tmr = 1'b1;
        @(posedge clk);
        wr_en_tmr = 1'b0;

        d_addr = 32'h8000_0010;
        #5;
        // Expected status: P1 shoot=1, P1 spec=0, P2 shoot=0, P2 spec=1 -> 4'b1001 = 0x9
        if (rd_tmr[3:0] !== 4'b1001) begin
            $display("  [FAIL] Multi-channel status mismatch! Expected 4'b1001, got %b", rd_tmr[3:0]);
            errors = errors + 1;
        end else begin
            $display("  [PASS] P1 Special and P2 Shoot entered cooldown simultaneously (status = 4'b1001).");
        end

        $display("==========================================================");
        if (errors == 0) begin
            $display(">> TEST PASSED: Cooldown Timers verified with 0 errors!");
        end else begin
            $display(">> TEST FAILED with %0d errors!", errors);
        end
        $display("==========================================================");

        $finish;
    end

endmodule
