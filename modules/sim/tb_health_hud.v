`timescale 1ns / 1ps
//=============================================================================
// Testbench: Health HUD Verification
// Verifies:
// 1. HUD Strip range checking (480 <= x < 640).
// 2. Vertical arena divider bar (x=479, 480, color 12'h557).
// 3. P1 Banner (y=12..19, blue 12'h029) and P2 Banner (y=420..427, red 12'h902).
// 4. Bit-slice heart slot decoding (dx[7:4]).
// 5. 8x8 Heart shape ROM transparency and fill.
// 6. Full heart vs Depleted heart rendering based on hp1 and hp2.
// 7. Specular highlight rendering.
// 8. P1 & P2 Special Attack Cooldown Bars and Telemetry.
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
    reg  [6:0] bar_p1_spec;
    reg  [6:0] bar_p2_spec;
    reg  [5:0] p1_keys;
    reg  [5:0] p2_keys;

    wire        hud_valid;
    wire [11:0] hud_rgb;

    integer errors = 0;

    health_hud dut (
        .clk         (clk),
        .reset_n     (reset_n),
        .pix_ce      (pix_ce),
        .x           (x),
        .y           (y),
        .active      (active),
        .hp1         (hp1),
        .hp2         (hp2),
        .bar_p1_spec (bar_p1_spec),
        .bar_p2_spec (bar_p2_spec),
        .p1_keys     (p1_keys),
        .p2_keys     (p2_keys),
        .hud_valid   (hud_valid),
        .hud_rgb     (hud_rgb),
        .p1_bcd      (),
        .p2_bcd      ()
    );

    // 50 MHz clock
    initial begin
        clk = 1'b0;
        forever #10 clk = ~clk;
    end

    // 25 MHz pix_ce
    initial begin
        pix_ce = 1'b0;
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
        bar_p1_spec = 7'd100; // P1 Special full
        bar_p2_spec = 7'd50;  // P2 Special half-full
        p1_keys = 6'd0;
        p2_keys = 6'd0;

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
        // Test 2: P1 Banner (y=15, x=500)
        // =====================================================================
        $display("  [TEST 2] Testing P1 Blue Header Banner...");
        x = 10'd500; y = 10'd15; // dx = 20 (between 4 and 80), y between 12 and 19
        @(posedge clk);
        while (!pix_ce) @(posedge clk);
        @(posedge clk);
        if (hud_valid !== 1'b1 || hud_rgb !== 12'h029) begin
            $display("  [FAIL] P1 banner mismatch! valid=%b rgb=0x%03h (expected 1, 0x029)",
                     hud_valid, hud_rgb);
            errors = errors + 1;
        end else begin
            $display("  [PASS] P1 Blue banner correctly rendered (valid=1, rgb=0x029).");
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
        // Test 4: Full Heart in P1 Row A (Slot 0, hp1=10 -> slot < hp1)
        // =====================================================================
        $display("  [TEST 4] Testing P1 Full Heart (Slot 0 < hp1)...");
        // Row A: y=24..31. Center pixel of slot 0:
        // x = 480 + 4 = 484 (slot 0, px_in_heart = 4)
        // y = 24 + 3 = 27   (py_in_heart = 3)
        // At py=3, px=4: ROM row 3 is 16'hFFFF -> heart_shape_bit = 1
        x = 10'd484; y = 10'd27;
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

        // Specular highlight at px=4, py=2 (x=484, y=26)
        x = 10'd484; y = 10'd26;
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
        // Test 5: Depleted Heart in P1 Row B (Slot 5, heart 15 >= hp1=10)
        // =====================================================================
        $display("  [TEST 5] Testing P1 Depleted Heart (Slot 5 + 10 >= hp1)...");
        // Row B: y=32..39. Slot 5: x = 480 + 5*16 + 4 = 564
        // y = 32 + 3 = 35 (py_in_heart = 3)
        x = 10'd564; y = 10'd35;
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
        // In 16x8 cell of slot 1 (x=496..511)
        // at py=0, px=0: ROM row 0 is 16'h3C3C -> px=0 is bit 15 = 0
        x = 10'd496; y = 10'd24;
        @(posedge clk);
        while (!pix_ce) @(posedge clk);
        @(posedge clk);
        if (hud_valid !== 1'b0) begin
            $display("  [FAIL] Transparent corner in heart cell reported hit!");
            errors = errors + 1;
        end else begin
            $display("  [PASS] Transparent area outside heart shape is valid=0.");
        end

        // =====================================================================
        // Test 7: P1 Special Cooldown Bar (Full = 100)
        // =====================================================================
        $display("  [TEST 7] Testing P1 Special Cooldown Bar (Full = 100)...");
        // Test border at x=480+28=508, y=60
        x = 10'd508; y = 10'd60;
        @(posedge clk);
        while (!pix_ce) @(posedge clk);
        @(posedge clk);
        if (hud_valid !== 1'b1 || hud_rgb !== 12'h357) begin
            $display("  [FAIL] P1 Bar border mismatch! valid=%b rgb=0x%03h (expected 1, 0x357)",
                     hud_valid, hud_rgb);
            errors = errors + 1;
        end else begin
            $display("  [PASS] P1 Bar border rendered (valid=1, rgb=0x357).");
        end

        // Test filled pixel inside at x=480+35=515 (bar_px=5 < 100), y=65
        x = 10'd515; y = 10'd65;
        @(posedge clk);
        while (!pix_ce) @(posedge clk);
        @(posedge clk);
        if (hud_valid !== 1'b1 || hud_rgb !== 12'h0DE) begin
            $display("  [FAIL] P1 Bar full body mismatch! valid=%b rgb=0x%03h (expected 1, 0x0DE)",
                     hud_valid, hud_rgb);
            errors = errors + 1;
        end else begin
            $display("  [PASS] P1 Bar full body rendered as Electric Cyan (0x0DE).");
        end

        // =====================================================================
        // Test 8: P2 Special Cooldown Bar (Half-Full = 50)
        // =====================================================================
        $display("  [TEST 8] Testing P2 Special Cooldown Bar (Half-Full = 50)...");
        // Test filled portion at x=480+50=530 (bar_px=20 < 50), y=400
        x = 10'd530; y = 10'd400;
        @(posedge clk);
        while (!pix_ce) @(posedge clk);
        @(posedge clk);
        if (hud_valid !== 1'b1 || hud_rgb !== 12'hC50) begin
            $display("  [FAIL] P2 Bar filled portion mismatch! valid=%b rgb=0x%03h (expected 1, 0xC50)",
                     hud_valid, hud_rgb);
            errors = errors + 1;
        end else begin
            $display("  [PASS] P2 Bar filled portion rendered as Amber (0xC50).");
        end

        // Test empty portion at x=480+90=570 (bar_px=60 >= 50), y=400
        x = 10'd570; y = 10'd400;
        @(posedge clk);
        while (!pix_ce) @(posedge clk);
        @(posedge clk);
        if (hud_valid !== 1'b1 || hud_rgb !== 12'h210) begin
            $display("  [FAIL] P2 Bar empty slot mismatch! valid=%b rgb=0x%03h (expected 1, 0x210)",
                     hud_valid, hud_rgb);
            errors = errors + 1;
        end else begin
            $display("  [PASS] P2 Bar empty slot rendered as Dark Recessed (0x210).");
        end

        // =====================================================================
        // Test 9: P1 'W' Keycap (Unpressed vs Active Keypress Highlight)
        // =====================================================================
        $display("  [TEST 9] Testing P1 'W' Keycap Rendering & Dynamic Illumination...");
        // Border at x = 480 + 29 = 509, y = 94 (unpressed)
        p1_keys = 6'd0;
        x = 10'd509; y = 10'd94;
        @(posedge clk);
        while (!pix_ce) @(posedge clk);
        @(posedge clk);
        if (hud_valid !== 1'b1 || hud_rgb !== 12'h88A) begin
            $display("  [FAIL] P1 W unpressed border mismatch! valid=%b rgb=0x%03h (expected 1, 0x88A)",
                     hud_valid, hud_rgb);
            errors = errors + 1;
        end else begin
            $display("  [PASS] P1 W unpressed border correctly rendered (valid=1, rgb=0x88A).");
        end

        // Border when pressed (p1_keys[0] = 1 -> highlighted border 12'h5DF)
        p1_keys = 6'b000001;
        @(posedge clk);
        while (!pix_ce) @(posedge clk);
        @(posedge clk);
        if (hud_valid !== 1'b1 || hud_rgb !== 12'h5DF) begin
            $display("  [FAIL] P1 W pressed border mismatch! valid=%b rgb=0x%03h (expected 1, 0x5DF)",
                     hud_valid, hud_rgb);
            errors = errors + 1;
        end else begin
            $display("  [PASS] P1 W pressed border correctly highlighted (valid=1, rgb=0x5DF).");
        end

        // Glyph inside 'W' keycap at x = 480 + 32 = 512, y = 97
        x = 10'd512; y = 10'd97;
        @(posedge clk);
        while (!pix_ce) @(posedge clk);
        @(posedge clk);
        if (hud_valid !== 1'b1 || hud_rgb !== 12'hFFF) begin
            $display("  [FAIL] P1 W glyph pixel mismatch! valid=%b rgb=0x%03h (expected 1, 0xFFF)",
                     hud_valid, hud_rgb);
            errors = errors + 1;
        end else begin
            $display("  [PASS] P1 W glyph pixel correctly rendered white (valid=1, rgb=0xFFF).");
        end
        p1_keys = 6'd0;

        // =====================================================================
        // Test 10: System Reset 'ESC' Keycap
        // =====================================================================
        $display("  [TEST 10] Testing System Reset 'ESC' Keycap...");
        // Border at x = 480 + 17 = 497, y = 192
        x = 10'd497; y = 10'd192;
        @(posedge clk);
        while (!pix_ce) @(posedge clk);
        @(posedge clk);
        if (hud_valid !== 1'b1 || hud_rgb !== 12'h88A) begin
            $display("  [FAIL] ESC border mismatch! valid=%b rgb=0x%03h (expected 1, 0x88A)",
                     hud_valid, hud_rgb);
            errors = errors + 1;
        end else begin
            $display("  [PASS] System ESC keycap border correctly rendered (valid=1, rgb=0x88A).");
        end

        // =====================================================================
        // Test 11: P2 'Up Arrow' Keycap (Unpressed vs Active Keypress Highlight)
        // =====================================================================
        $display("  [TEST 11] Testing P2 'Up Arrow' Keycap Rendering & Dynamic Illumination...");
        // Border at x = 480 + 29 = 509, y = 244 (unpressed)
        p2_keys = 6'd0;
        x = 10'd509; y = 10'd244;
        @(posedge clk);
        while (!pix_ce) @(posedge clk);
        @(posedge clk);
        if (hud_valid !== 1'b1 || hud_rgb !== 12'h88A) begin
            $display("  [FAIL] P2 Up Arrow unpressed border mismatch! valid=%b rgb=0x%03h (expected 1, 0x88A)",
                     hud_valid, hud_rgb);
            errors = errors + 1;
        end else begin
            $display("  [PASS] P2 Up Arrow unpressed border correctly rendered (valid=1, rgb=0x88A).");
        end

        // Border when pressed (p2_keys[0] = 1 -> highlighted border 12'hFB4)
        p2_keys = 6'b000001;
        @(posedge clk);
        while (!pix_ce) @(posedge clk);
        @(posedge clk);
        if (hud_valid !== 1'b1 || hud_rgb !== 12'hFB4) begin
            $display("  [FAIL] P2 Up Arrow pressed border mismatch! valid=%b rgb=0x%03h (expected 1, 0xFB4)",
                     hud_valid, hud_rgb);
            errors = errors + 1;
        end else begin
            $display("  [PASS] P2 Up Arrow pressed border correctly highlighted (valid=1, rgb=0xFB4).");
        end
        p2_keys = 6'd0;

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
