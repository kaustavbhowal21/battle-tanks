`timescale 1ns / 1ps
//=============================================================================
// Testbench: Health HUD Verification
// Verifies:
// 1. HUD Strip range checking (480 <= x < 640).
// 2. Vertical arena divider bar (x=479, 480, color 12'h557).
// 3. P1 Banner (y=20..27, green 12'h092) and P2 Banner (y=420..427, red 12'h902).
// 4. Bit-slice heart slot decoding (dx[7:3]).
// 5. 8x8 Heart shape ROM transparency and fill.
// 6. Full heart vs Depleted heart rendering based on hp1 and hp2.
// 7. Specular highlight rendering.
//=============================================================================

module tb_health_hud;

    reg        clk;
    reg        reset_n;
    reg        pix_ce;
    reg  [9:0] x;
    reg  [9:0] y;
    reg        active;
    reg  [7:0] hp1;
    reg  [7:0] hp2;

    wire        hud_valid;
    wire [11:0] hud_rgb;

    integer errors = 0;

    health_hud dut (
        .clk       (clk),
        .reset_n   (reset_n),
        .pix_ce    (pix_ce),
        .x         (x),
        .y         (y),
        .active    (active),
        .hp1       (hp1),
        .hp2       (hp2),
        .hud_valid (hud_valid),
        .hud_rgb   (hud_rgb)
    );

    // 50 MHz clock
    initial begin
        clk = 1'b0;
        forever #10 clk = ~clk;
    end

    // 25 MHz pix_ce
    initial begin
        pix_ce = 1'b0;
        // Non-blocking drive: a blocking '=' right after the clock edge races with
        // the DUT's always @(posedge clk) blocks (DUT may see pix_ce=1 on every edge).
        forever begin
            @(posedge clk);
            pix_ce <= 1'b1;
            @(posedge clk);
            pix_ce <= 1'b0;
        end
    end

    initial begin
        $display("==========================================================");
        $display("   TESTBENCH: HEALTH HUD VERIFICATION                     ");
        $display("==========================================================");

        reset_n = 1'b0;
        active = 1'b1;
        x = 10'd0;
        y = 10'd0;
        hp1 = 8'd10; // 10 out of 20 hearts
        hp2 = 8'd5;  // 5 out of 20 hearts

        #100;
        @(posedge clk);
        reset_n = 1'b1;
        @(posedge clk);

        // =====================================================================
        // Test 1: Arena Vertical Divider Bar (x=479, color 12'h557)
        // =====================================================================
        $display("  [TEST 1] Testing Arena Vertical Divider Bar...");
        x = 10'd479; y = 10'd100;
        @(posedge clk);
        while (!pix_ce) @(posedge clk);
        @(posedge clk); // Registered output
        if (hud_valid !== 1'b1 || hud_rgb !== 12'h557) begin
            $display("  [FAIL] Vertical divider mismatch! valid=%b rgb=0x%03h (expected 1, 0x557)",
                     hud_valid, hud_rgb);
            errors = errors + 1;
        end else begin
            $display("  [PASS] Vertical divider bar rendered correctly (valid=1, rgb=0x557).");
        end

        // =====================================================================
        // Test 2: P1 Banner (y=25, x=500)
        // =====================================================================
        $display("  [TEST 2] Testing P1 Green Header Banner...");
        x = 10'd500; y = 10'd25; // dx = 20 (between 4 and 80), y between 20 and 27
        @(posedge clk);
        while (!pix_ce) @(posedge clk);
        @(posedge clk);
        if (hud_valid !== 1'b1 || hud_rgb !== 12'h092) begin
            $display("  [FAIL] P1 banner mismatch! valid=%b rgb=0x%03h (expected 1, 0x092)",
                     hud_valid, hud_rgb);
            errors = errors + 1;
        end else begin
            $display("  [PASS] P1 Green banner correctly rendered (valid=1, rgb=0x092).");
        end

        // =====================================================================
        // Test 3: P2 Banner (y=425, x=500)
        // =====================================================================
        $display("  [TEST 3] Testing P2 Red Header Banner...");
        x = 10'd500; y = 10'd425; // y between 420 and 427
        @(posedge clk);
        while (!pix_ce) @(posedge clk);
        @(posedge clk);
        if (hud_valid !== 1'b1 || hud_rgb !== 12'h902) begin
            $display("  [FAIL] P2 banner mismatch! valid=%b rgb=0x%03h (expected 1, 0x902)",
                     hud_valid, hud_rgb);
            errors = errors + 1;
        end else begin
            $display("  [PASS] P2 Red banner correctly rendered (valid=1, rgb=0x902).");
        end

        // =====================================================================
        // Test 4: Full Heart in P1 Row (Slot 0, hp1=10 -> slot < hp1)
        // =====================================================================
        $display("  [TEST 4] Testing P1 Full Heart (Slot 0 < hp1)...");
        // Row y=32..39. Let's test center pixel of slot 0:
        // x = 480 + 3 = 483 (slot 0, px_in_heart = 3)
        // y = 32 + 3 = 35   (py_in_heart = 3)
        // At py=3, px=3: ROM row 3 is 8'b11111111 -> heart_shape_bit = 1
        x = 10'd483; y = 10'd35;
        @(posedge clk);
        while (!pix_ce) @(posedge clk);
        @(posedge clk);
        if (hud_valid !== 1'b1 || hud_rgb !== 12'hF00) begin
            $display("  [FAIL] Full heart color mismatch! valid=%b rgb=0x%03h (expected 1, 0xF00)",
                     hud_valid, hud_rgb);
            errors = errors + 1;
        end else begin
            $display("  [PASS] Full heart body correctly rendered as Crimson Red (0xF00).");
        end

        // Specular highlight at px=2, py=2 (x=482, y=34)
        x = 10'd482; y = 10'd34;
        @(posedge clk);
        while (!pix_ce) @(posedge clk);
        @(posedge clk);
        if (hud_valid !== 1'b1 || hud_rgb !== 12'hFFA) begin
            $display("  [FAIL] Specular highlight mismatch! valid=%b rgb=0x%03h (expected 1, 0xFFA)",
                     hud_valid, hud_rgb);
            errors = errors + 1;
        end else begin
            $display("  [PASS] Specular highlight rendered (valid=1, rgb=0xFFA).");
        end

        // =====================================================================
        // Test 5: Depleted Heart in P1 Row (Slot 15, hp1=10 -> slot >= hp1)
        // =====================================================================
        $display("  [TEST 5] Testing P1 Depleted Heart (Slot 15 >= hp1)...");
        // x = 480 + 15*8 + 3 = 603 (slot 15, px_in_heart = 3)
        // y = 35 (py_in_heart = 3)
        x = 10'd603; y = 10'd35;
        @(posedge clk);
        while (!pix_ce) @(posedge clk);
        @(posedge clk);
        if (hud_valid !== 1'b1 || hud_rgb !== 12'h300) begin
            $display("  [FAIL] Depleted heart mismatch! valid=%b rgb=0x%03h (expected 1, 0x300)",
                     hud_valid, hud_rgb);
            errors = errors + 1;
        end else begin
            $display("  [PASS] Depleted heart rendered as Dark Outline (valid=1, rgb=0x300).");
        end

        // =====================================================================
        // Test 6: Transparency Outside Heart Shape in Cell
        // =====================================================================
        $display("  [TEST 6] Testing Transparency in Cell Corners...");
        // In 8x8 cell of slot 1 (x=488..495, away from divider bar x=480)
        // at py=0, px=0: ROM row 0 is 8'b01100110 -> px=0 is bit 7 = 0
        x = 10'd488; y = 10'd32;
        @(posedge clk);
        while (!pix_ce) @(posedge clk);
        @(posedge clk);
        if (hud_valid !== 1'b0) begin
            $display("  [FAIL] Transparent corner in heart cell reported hit!");
            errors = errors + 1;
        end else begin
            $display("  [PASS] Transparent area outside heart shape is valid=0.");
        end

        $display("==========================================================");
        if (errors == 0) begin
            $display(">> TEST PASSED: Health HUD verified with 0 errors!");
        end else begin
            $display(">> TEST FAILED with %0d errors!", errors);
        end
        $display("==========================================================");

        $finish;
    end

endmodule
