`timescale 1ns / 1ps
//=============================================================================
// Testbench: Input Controller Verification
// Verifies:
// 1. 2-FF metastability synchronizer.
// 2. Glitch rejection (pulses shorter than DEBOUNCE_MAX do not change output).
// 3. Debouncing: stable signal held >= DEBOUNCE_MAX updates stable output.
// 4. MMIO address decode & register reads (0x8000_0000 for P1, 0x8000_0004 for P2).
// 5. Reset behavior.
//=============================================================================

module tb_input_controller;

    reg        clk;
    reg        reset_n;
    reg  [5:0] p1_btn_raw;
    reg  [5:0] p2_btn_raw;
    reg  [31:0] d_addr;
    wire [31:0] rd_in;
    wire [5:0]  p1_btn_stable;
    wire [5:0]  p2_btn_stable;

    integer errors = 0;

    // Use a small DEBOUNCE_MAX for fast simulation (5 clocks instead of 500,000)
    localparam DEBOUNCE_SIM = 20'd5;
    // Minimum press hold time (clocks). Short so the other tests stay fast.
    localparam HOLD_SIM     = 21'd40;

    input_controller #(
        .DEBOUNCE_MAX(DEBOUNCE_SIM),
        .MIN_HOLD    (HOLD_SIM)
    ) dut (
        .clk           (clk),
        .reset_n       (reset_n),
        .p1_btn_raw    (p1_btn_raw),
        .p2_btn_raw    (p2_btn_raw),
        .d_addr        (d_addr),
        .rd_in         (rd_in),
        .p1_btn_stable (p1_btn_stable),
        .p2_btn_stable (p2_btn_stable)
    );

    // 50 MHz clock
    initial begin
        clk = 1'b0;
        forever #10 clk = ~clk;
    end

    initial begin
        $display("==========================================================");
        $display("   TESTBENCH: INPUT CONTROLLER VERIFICATION               ");
        $display("==========================================================");

        reset_n = 1'b0;
        p1_btn_raw = 6'b000000;
        p2_btn_raw = 6'b000000;
        d_addr = 32'h8000_0000;

        #100;
        @(posedge clk);
        reset_n = 1'b1;
        @(posedge clk);

        // =====================================================================
        // Test 1: Glitch Rejection
        // =====================================================================
        $display("  [TEST 1] Testing Noise Glitch Filtering...");
        // Pulse P1 button 0 for only 2 clocks (less than DEBOUNCE_MAX=5)
        p1_btn_raw[0] = 1'b1;
        @(posedge clk);
        @(posedge clk);
        p1_btn_raw[0] = 1'b0;
        repeat(5) @(posedge clk);

        if (p1_btn_stable[0] !== 1'b0) begin
            $display("  [FAIL] Glitch was not filtered out! Output changed.");
            errors = errors + 1;
        end else begin
            $display("  [PASS] 2-clock noise glitch successfully rejected.");
        end

        // =====================================================================
        // Test 2: Legitimate Button Press Debouncing
        // =====================================================================
        $display("  [TEST 2] Testing Button Debounce Stabilization...");
        // Hold P1 buttons [0]=FWD and [4]=SHOOT for 10 clocks (> DEBOUNCE_MAX=5 + 2 FFs)
        p1_btn_raw = 6'b010001;
        repeat(10) @(posedge clk);

        if (p1_btn_stable !== 6'b010001) begin
            $display("  [FAIL] Debounced output mismatch! Expected 6'b010001, got %b", p1_btn_stable);
            errors = errors + 1;
        end else begin
            $display("  [PASS] Buttons cleanly stabilized to 6'b010001.");
        end

        // Release buttons (wait out the minimum hold time first)
        p1_btn_raw = 6'b000000;
        repeat(HOLD_SIM + 10) @(posedge clk);
        if (p1_btn_stable !== 6'b000000) begin
            $display("  [FAIL] Release debounce failed! Expected 0, got %b", p1_btn_stable);
            errors = errors + 1;
        end else begin
            $display("  [PASS] Button release cleanly debounced back to 0.");
        end

        // =====================================================================
        // Test 2b: Short tap is stretched to MIN_HOLD (so the CPU cannot miss it)
        // =====================================================================
        $display("  [TEST 2b] Testing short-tap stretching...");
        p1_btn_raw[3] = 1'b1;
        repeat(12) @(posedge clk);      // tap just longer than the debounce time
        p1_btn_raw[3] = 1'b0;
        repeat(12) @(posedge clk);      // released, but hold time not over yet
        if (p1_btn_stable[3] !== 1'b1) begin
            $display("  [FAIL] Short tap was not held on the output!");
            errors = errors + 1;
        end else begin
            $display("  [PASS] Short tap still visible on the output after release.");
        end
        repeat(HOLD_SIM + 10) @(posedge clk);
        if (p1_btn_stable[3] !== 1'b0) begin
            $display("  [FAIL] Output did not return to 0 after the hold time!");
            errors = errors + 1;
        end else begin
            $display("  [PASS] Output released after the minimum hold time.");
        end

        // =====================================================================
        // Test 3: Player 2 Button Independence
        // =====================================================================
        $display("  [TEST 3] Testing Player 2 Channel Debouncing...");
        p2_btn_raw = 6'b100100; // Turn Left + Special
        repeat(10) @(posedge clk);

        if (p2_btn_stable !== 6'b100100) begin
            $display("  [FAIL] P2 debounced output mismatch! Expected 6'b100100, got %b", p2_btn_stable);
            errors = errors + 1;
        end else begin
            $display("  [PASS] P2 channels debounced independently.");
        end

        // =====================================================================
        // Test 4: MMIO Register Read Mapping
        // =====================================================================
        $display("  [TEST 4] Testing MMIO Read Decode...");
        // Set both players active
        p1_btn_raw = 6'b000001; // P1 FWD
        p2_btn_raw = 6'b000010; // P2 BWD
        repeat(HOLD_SIM + 10) @(posedge clk);

        // Read 0x8000_0000 (P1 Input Register)
        d_addr = 32'h8000_0000;
        #5;
        if (rd_in !== 32'h0000_0001) begin
            $display("  [FAIL] MMIO read 0x8000_0000 mismatch! Expected 0x1, got 0x%08h", rd_in);
            errors = errors + 1;
        end else begin
            $display("  [PASS] MMIO read 0x8000_0000 correctly returned P1 button mask (0x1).");
        end

        // Read 0x8000_0004 (P2 Input Register)
        d_addr = 32'h8000_0004;
        #5;
        if (rd_in !== 32'h0000_0002) begin
            $display("  [FAIL] MMIO read 0x8000_0004 mismatch! Expected 0x2, got 0x%08h", rd_in);
            errors = errors + 1;
        end else begin
            $display("  [PASS] MMIO read 0x8000_0004 correctly returned P2 button mask (0x2).");
        end

        $display("==========================================================");
        if (errors == 0) begin
            $display(">> TEST PASSED: Input Controller verified with 0 errors!");
        end else begin
            $display(">> TEST FAILED with %0d errors!", errors);
        end
        $display("==========================================================");

        $finish;
    end

endmodule
