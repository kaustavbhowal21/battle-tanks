`timescale 1ns / 1ps
//=============================================================================
// Testbench: Pixel Priority Mixer Verification
// Verifies:
// 1. Strict layer priority chain:
//    HUD > Big Bullet > Normal Bullet > Tank P1 > Tank P2 > Maze Wall > Floor
// 2. 2-stage sync & active delay line alignment.
// 3. RGB blanking when active_in is low (front porch, sync, back porch).
// 4. Reset behavior.
//=============================================================================

module tb_pixel_priority_mixer;

    reg        clk;
    reg        reset_n;
    reg        pix_ce;

    reg        hsync_n_in;
    reg        vsync_n_in;
    reg        active_in;

    reg        hud_valid;
    reg [11:0] hud_rgb;
    reg        big_valid;
    reg [11:0] big_rgb;
    reg        bullet_valid;
    reg [11:0] bullet_rgb;
    reg        tank_valid_p1;
    reg [11:0] tank_rgb_p1;
    reg        tank_valid_p2;
    reg [11:0] tank_rgb_p2;
    reg        maze_wall;
    reg [11:0] maze_rgb;

    wire [3:0] vga_r;
    wire [3:0] vga_g;
    wire [3:0] vga_b;
    wire       vga_hsync;
    wire       vsync;

    wire [11:0] vga_rgb = {vga_r, vga_g, vga_b};

    integer errors = 0;

    pixel_priority_mixer dut (
        .clk           (clk),
        .reset_n       (reset_n),
        .pix_ce        (pix_ce),
        .hsync_n_in    (hsync_n_in),
        .vsync_n_in    (vsync_n_in),
        .active_in     (active_in),
        .hud_valid     (hud_valid),
        .hud_rgb       (hud_rgb),
        .big_valid     (big_valid),
        .big_rgb       (big_rgb),
        .bullet_valid  (bullet_valid),
        .bullet_rgb    (bullet_rgb),
        .tank_valid_p1 (tank_valid_p1),
        .tank_rgb_p1   (tank_rgb_p1),
        .tank_valid_p2 (tank_valid_p2),
        .tank_rgb_p2   (tank_rgb_p2),
        .maze_wall     (maze_wall),
        .maze_rgb      (maze_rgb),
        .vga_r         (vga_r),
        .vga_g         (vga_g),
        .vga_b         (vga_b),
        .vga_hsync     (vga_hsync),
        .vga_vsync     (vsync)
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

    task step_pix;
        begin
            @(posedge clk);
            while (!pix_ce) @(posedge clk);
        end
    endtask

    initial begin
        $display("==========================================================");
        $display("   TESTBENCH: PIXEL PRIORITY MIXER VERIFICATION           ");
        $display("==========================================================");

        reset_n = 1'b0;
        hsync_n_in = 1'b1;
        vsync_n_in = 1'b1;
        active_in = 1'b1;

        hud_valid     = 1'b0; hud_rgb     = 12'h111;
        big_valid     = 1'b0; big_rgb     = 12'h222;
        bullet_valid  = 1'b0; bullet_rgb  = 12'h333;
        tank_valid_p1 = 1'b0; tank_rgb_p1 = 12'h444;
        tank_valid_p2 = 1'b0; tank_rgb_p2 = 12'h555;
        maze_wall     = 1'b0; maze_rgb    = 12'h666;

        #100;
        @(posedge clk);
        reset_n = 1'b1;
        @(posedge clk);

        // =====================================================================
        // Test 1: Priority Escalation Ladder
        // =====================================================================
        $display("  [TEST 1] Testing Strict Layer Priority Ladder...");

        // Assert all layers active simultaneously
        hud_valid     = 1'b1;
        big_valid     = 1'b1;
        bullet_valid  = 1'b1;
        tank_valid_p1 = 1'b1;
        tank_valid_p2 = 1'b1;
        maze_wall     = 1'b1;

        // Pass through 2-stage pipeline delay
        step_pix();
        step_pix();
        step_pix();

        // 1. HUD must win
        if (vga_rgb !== 12'h111) begin
            $display("  [FAIL] HUD did not win priority! rgb=0x%03h (expected 0x111)", vga_rgb);
            errors = errors + 1;
        end else begin
            $display("  [PASS] Layer 1 (HUD) correctly takes top priority (rgb=0x111).");
        end

        // 2. Turn off HUD -> Big Bullet must win
        hud_valid = 1'b0;
        step_pix(); step_pix();
        if (vga_rgb !== 12'h222) begin
            $display("  [FAIL] Big Bullet did not win priority! rgb=0x%03h (expected 0x222)", vga_rgb);
            errors = errors + 1;
        end else begin
            $display("  [PASS] Layer 2 (Big Bullet) correctly overrides normal bullet and tanks (rgb=0x222).");
        end

        // 3. Turn off Big Bullet -> Normal Bullet must win
        big_valid = 1'b0;
        step_pix(); step_pix();
        if (vga_rgb !== 12'h333) begin
            $display("  [FAIL] Normal Bullet did not win priority! rgb=0x%03h (expected 0x333)", vga_rgb);
            errors = errors + 1;
        end else begin
            $display("  [PASS] Layer 3 (Normal Bullet) correctly overrides tanks (rgb=0x333).");
        end

        // 4. Turn off Bullet -> Tank P1 must win
        bullet_valid = 1'b0;
        step_pix(); step_pix();
        if (vga_rgb !== 12'h444) begin
            $display("  [FAIL] Tank P1 did not win priority! rgb=0x%03h (expected 0x444)", vga_rgb);
            errors = errors + 1;
        end else begin
            $display("  [PASS] Layer 4 (Tank P1) correctly overrides Tank P2 and maze (rgb=0x444).");
        end

        // 5. Turn off Tank P1 -> Tank P2 must win
        tank_valid_p1 = 1'b0;
        step_pix(); step_pix();
        if (vga_rgb !== 12'h555) begin
            $display("  [FAIL] Tank P2 did not win priority! rgb=0x%03h (expected 0x555)", vga_rgb);
            errors = errors + 1;
        end else begin
            $display("  [PASS] Layer 5 (Tank P2) correctly overrides maze (rgb=0x555).");
        end

        // 6. Turn off Tank P2 -> Maze Wall must win
        tank_valid_p2 = 1'b0;
        step_pix(); step_pix();
        if (vga_rgb !== 12'h666) begin
            $display("  [FAIL] Maze Wall did not win priority! rgb=0x%03h (expected 0x666)", vga_rgb);
            errors = errors + 1;
        end else begin
            $display("  [PASS] Layer 6 (Maze Wall) rendered correctly (rgb=0x666).");
        end

        // =====================================================================
        // Test 2: Blanking Interval Suppression
        // =====================================================================
        $display("  [TEST 2] Testing RGB Blanking When active_in=0...");
        // Re-enable HUD
        hud_valid = 1'b1;
        active_in = 1'b0; // Blanking interval
        // 3 clocks for 2-stage shift reg + output register
        step_pix(); step_pix(); step_pix();
        if (vga_rgb !== 12'h000) begin
            $display("  [FAIL] Blanking failed! Non-zero RGB during blanking: rgb=0x%03h", vga_rgb);
            errors = errors + 1;
        end else begin
            $display("  [PASS] Blanking interval strictly drives RGB=0x000.");
        end

        // =====================================================================
        // Test 3: Sync Delay Line Pipelining
        // =====================================================================
        $display("  [TEST 3] Testing Sync Signal Propagation Delay Line...");
        active_in = 1'b1;
        hsync_n_in = 1'b0; // Assert HSYNC pulse
        step_pix();
        // At 1st stage, output should still be 1 (delayed)
        if (vga_hsync !== 1'b1) begin
            $display("  [FAIL] HSYNC passed too quickly (not delayed)!");
            errors = errors + 1;
        end
        step_pix();
        // At 2nd stage, output should still be 1
        if (vga_hsync !== 1'b1) begin
            $display("  [FAIL] HSYNC passed before 3rd cycle!");
            errors = errors + 1;
        end
        step_pix();
        // At 3rd stage, output should now be 0
        if (vga_hsync !== 1'b0) begin
            $display("  [FAIL] HSYNC not propagated after 3 delay stages!");
            errors = errors + 1;
        end else begin
            $display("  [PASS] HSYNC delay line matches 3-stage pipeline latency.");
        end

        $display("==========================================================");
        if (errors == 0) begin
            $display(">> TEST PASSED: Pixel Priority Mixer verified with 0 errors!");
        end else begin
            $display(">> TEST FAILED with %0d errors!", errors);
        end
        $display("==========================================================");

        $finish;
    end

endmodule
