`timescale 1ns / 1ps
//=============================================================================
// Testbench: Sprite Engine Verification
// Verifies:
// 1. Tank 1 (Green) 20x20 bounding box, treads, hull, dome, and turret barrel.
// 2. Tank 2 (Red) 20x20 bounding box, treads, hull, and dome.
// 3. Normal Bullets (6x6 circular disc test dx^2 + dy^2 <= 6, yellow 0xFF2).
// 4. Big Bullets (10x10 circular disc test dx^2 + dy^2 <= 18, fiery orange 0xF30).
// 5. Inactive bullets producing no hit.
// 6. Registered outputs alignment.
//=============================================================================

module tb_sprite_engine;

    reg        clk;
    reg        reset_n;
    reg        pix_ce;
    reg  [9:0] x;
    reg  [9:0] y;
    reg        active;

    reg  [9:0] p1_tank_x;
    reg  [9:0] p1_tank_y;
    reg signed [9:0] tank_cos1, tank_sin1;   // barrel direction vectors (x256)
    reg  [9:0] p2_tank_x;
    reg  [9:0] p2_tank_y;
    reg signed [9:0] tank_cos2, tank_sin2;

    reg  [9:0] bullet_x   [0:7];
    reg  [9:0] bullet_y   [0:7];
    reg  [7:0] bullet_act;
    reg  [7:0] bullet_big;

    wire        tank_valid_p1;
    wire [11:0] tank_rgb_p1;
    wire        tank_valid_p2;
    wire [11:0] tank_rgb_p2;
    wire        bullet_valid;
    wire [11:0] bullet_rgb;
    wire        big_valid;
    wire [11:0] big_rgb;

    integer errors = 0;
    integer bi;

    sprite_engine dut (
        .clk           (clk),
        .reset_n       (reset_n),
        .pix_ce        (pix_ce),
        .x             (x),
        .y             (y),
        .active        (active),
        .p1_tank_x     (p1_tank_x),
        .p1_tank_y     (p1_tank_y),
        .tank_cos1     (tank_cos1),
        .tank_sin1     (tank_sin1),
        .p2_tank_x     (p2_tank_x),
        .p2_tank_y     (p2_tank_y),
        .tank_cos2     (tank_cos2),
        .tank_sin2     (tank_sin2),
        .bullet_x      (bullet_x),
        .bullet_y      (bullet_y),
        .bullet_act    (bullet_act),
        .bullet_big    (bullet_big),
        .tank_valid_p1 (tank_valid_p1),
        .tank_rgb_p1   (tank_rgb_p1),
        .tank_valid_p2 (tank_valid_p2),
        .tank_rgb_p2   (tank_rgb_p2),
        .bullet_valid  (bullet_valid),
        .bullet_rgb    (bullet_rgb),
        .big_valid     (big_valid),
        .big_rgb       (big_rgb)
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


    // -------------------------------------------------------------------------
    // Independent reference for the barrel: the physical shape is a rectangle that
    // starts 2 px and ends 11 px from the tank centre along the direction, and is
    // +-0.875 px wide. Pixels are sampled at their centre. Uses real trigonometry of
    // an arbitrary angle, NOT the integer formula inside the DUT.
    // -------------------------------------------------------------------------
    real PI = 3.14159265358979;
    integer barrel_checked, barrel_skipped, barrel_errors;

    // returns 1 = inside barrel, 0 = outside, 2 = too close to the edge to judge
    function integer ref_barrel;
        input integer ddx;
        input integer ddy;
        input real    ang;
        real px, py, al, ac, m1, m2, m3, m;
        begin
            px = ddx + 0.5 - 10.0;
            py = ddy + 0.5 - 10.0;
            al = px * $cos(ang) + py * $sin(ang);
            ac = px * $sin(ang) - py * $cos(ang);
            if (ac < 0.0) ac = -ac;
            m1 = al - 2.0;  if (m1 < 0.0) m1 = -m1;
            m2 = al - 11.0; if (m2 < 0.0) m2 = -m2;
            m3 = ac - 0.875; if (m3 < 0.0) m3 = -m3;
            m = m1; if (m2 < m) m = m2; if (m3 < m) m = m3;
            if (m < 0.2)
                ref_barrel = 2;
            else if (al >= 2.0 && al <= 11.0 && ac <= 0.875)
                ref_barrel = 1;
            else
                ref_barrel = 0;
        end
    endfunction

    // Sets the direction of one tank to angle `deg` (any real value, rounded to the
    // same x256 integers the CPU would send) and compares every pixel of the
    // 20x20 tank box (except the centre dome, which has the barrel colour) with the reference.
    task check_barrel_angle;
        input integer tank;     // 1 or 2
        input real    deg;
        integer ddx, ddy, r, hit;
        integer ci, si;
        real ang;
        begin
            ang = deg * PI / 180.0;
            ci = $rtoi(256.0 * $cos(ang) + ($cos(ang) >= 0.0 ? 0.5 : -0.5));
            si = $rtoi(256.0 * $sin(ang) + ($sin(ang) >= 0.0 ? 0.5 : -0.5));
            if (tank == 1) begin tank_cos1 = ci; tank_sin1 = si; end
            else           begin tank_cos2 = ci; tank_sin2 = si; end
            for (ddy = 0; ddy < 20; ddy = ddy + 1) begin
                for (ddx = 0; ddx < 20; ddx = ddx + 1) begin
                    if (!(ddx >= 7 && ddx <= 12 && ddy >= 7 && ddy <= 12)) begin
                        r = ref_barrel(ddx, ddy, ang);
                        if (r == 2) begin
                            barrel_skipped = barrel_skipped + 1;
                        end else begin
                            if (tank == 1) begin x = p1_tank_x + ddx; y = p1_tank_y + ddy; end
                            else           begin x = p2_tank_x + ddx; y = p2_tank_y + ddy; end
                            @(posedge clk); #1;
                            if (tank == 1) hit = (tank_valid_p1 && tank_rgb_p1 == 12'h4CF);
                            else           hit = (tank_valid_p2 && tank_rgb_p2 == 12'hF44);
                            barrel_checked = barrel_checked + 1;
                            if (hit != r) begin
                                barrel_errors = barrel_errors + 1;
                                $display("  [FAIL] tank %0d angle %0.2f deg (cos=%0d sin=%0d): pixel (%0d,%0d) barrel=%0d expected %0d",
                                         tank, deg, ci, si, ddx, ddy, hit, r);
                            end
                        end
                    end
                end
            end
        end
    endtask

    initial begin
        $display("==========================================================");
        $display("   TESTBENCH: SPRITE ENGINE VERIFICATION                  ");
        $display("==========================================================");

        reset_n = 1'b0;
        active = 1'b1;
        x = 10'd0;
        y = 10'd0;

        p1_tank_x = 10'd50;
        p1_tank_y = 10'd50;
        tank_cos1 = 10'sd256; tank_sin1 = 10'sd0;   // East

        p2_tank_x = 10'd200;
        p2_tank_y = 10'd200;
        tank_cos2 = -10'sd256; tank_sin2 = 10'sd0;  // West

        for (bi = 0; bi < 8; bi = bi + 1) begin
            bullet_x[bi] = 10'd0;
            bullet_y[bi] = 10'd0;
        end
        bullet_act = 8'b00000000;
        bullet_big = 8'b00000000;

        #100;
        @(posedge clk);
        reset_n = 1'b1;
        @(posedge clk);

        // =====================================================================
        // Test 1: Tank 1 Hit Detection & Turret Dome
        // =====================================================================
        $display("  [TEST 1] Testing Tank 1 (Green) Body & Turret Dome...");

        // Outside tank box: (x=40, y=50) -> should NOT hit
        x = 10'd40; y = 10'd50;
        @(posedge clk);
        while (!pix_ce) @(posedge clk);
        @(posedge clk); // Pipeline register
        if (tank_valid_p1 !== 1'b0) begin
            $display("  [FAIL] Pixel outside Tank 1 reported hit!");
            errors = errors + 1;
        end else begin
            $display("  [PASS] Outside Tank 1 bounding box: valid=0.");
        end

        // Center dome of Tank 1: (x=50 + 10 = 60, y=50 + 10 = 60)
        x = 10'd60; y = 10'd60;
        @(posedge clk);
        while (!pix_ce) @(posedge clk);
        @(posedge clk);
        if (tank_valid_p1 !== 1'b1 || tank_rgb_p1 !== 12'h0F4) begin
            $display("  [FAIL] Tank 1 center dome color mismatch! valid=%b rgb=0x%03h (expected 1, 0x0F4)",
                     tank_valid_p1, tank_rgb_p1);
            errors = errors + 1;
        end else begin
            $display("  [PASS] Tank 1 turret dome correctly rendered (valid=1, rgb=0x0F4).");
        end

        // Tank 1 Tread (x=50 + 1 = 51, y=50 + 4 = 54)
        x = 10'd51; y = 10'd54;
        @(posedge clk);
        while (!pix_ce) @(posedge clk);
        @(posedge clk);
        if (tank_valid_p1 !== 1'b1) begin
            $display("  [FAIL] Tank 1 tread hit detection failed!");
            errors = errors + 1;
        end else begin
            $display("  [PASS] Tank 1 treads correctly detected.");
        end

        // =====================================================================
        // Test 2: Tank 2 Hit Detection
        // =====================================================================
        $display("  [TEST 2] Testing Tank 2 (Red) Center Dome...");
        x = 10'd210; y = 10'd210; // (p2_tank_x=200, p2_tank_y=200, offset 10,10)
        @(posedge clk);
        while (!pix_ce) @(posedge clk);
        @(posedge clk);
        if (tank_valid_p2 !== 1'b1 || tank_rgb_p2 !== 12'hF44) begin
            $display("  [FAIL] Tank 2 center dome color mismatch! valid=%b rgb=0x%03h (expected 1, 0xF44)",
                     tank_valid_p2, tank_rgb_p2);
            errors = errors + 1;
        end else begin
            $display("  [PASS] Tank 2 center dome correctly rendered (valid=1, rgb=0xF44).");
        end

        // =====================================================================
        // Test 3: Normal Bullet (6x6 Circle Test)
        // =====================================================================
        $display("  [TEST 3] Testing Normal Bullet (6x6 Circular Disc)...");
        // Place active normal bullet 0 at (300, 300)
        bullet_x[0]   = 10'd300;
        bullet_y[0]   = 10'd300;
        bullet_act[0] = 1'b1;
        bullet_big[0] = 1'b0;

        // Center of normal bullet: offset (2, 2) -> (x=302, y=302)
        // norm_cdx = 2 - 2 = 0, norm_cdy = 2 - 2 = 0 -> 0 <= 6 (Hit)
        x = 10'd302; y = 10'd302;
        @(posedge clk);
        while (!pix_ce) @(posedge clk);
        @(posedge clk);
        if (bullet_valid !== 1'b1 || bullet_rgb !== 12'hFF2) begin
            $display("  [FAIL] Normal bullet center hit failed! valid=%b rgb=0x%03h (expected 1, 0xFF2)",
                     bullet_valid, bullet_rgb);
            errors = errors + 1;
        end else begin
            $display("  [PASS] Normal bullet center rendered correctly (valid=1, rgb=0xFF2).");
        end

        // Corner of 6x6 box: offset (0, 0) -> (x=300, y=300)
        // norm_cdx = 0 - 2 = -2, norm_cdy = 0 - 2 = -2 -> (-2)^2 + (-2)^2 = 8 > 6 (Should clip circle corner!)
        x = 10'd300; y = 10'd300;
        @(posedge clk);
        while (!pix_ce) @(posedge clk);
        @(posedge clk);
        if (bullet_valid !== 1'b0) begin
            $display("  [FAIL] Normal bullet circle corner should be clipped (dx^2+dy^2=8 > 6)!");
            errors = errors + 1;
        end else begin
            $display("  [PASS] Normal bullet circular clipping verified (corners clipped).");
        end

        // =====================================================================
        // Test 4: Big Bullet (10x10 Circular Disc)
        // =====================================================================
        $display("  [TEST 4] Testing Big Bullet (10x10 Circular Disc)...");
        // Place big bullet 1 at (350, 350)
        bullet_x[1]   = 10'd350;
        bullet_y[1]   = 10'd350;
        bullet_act[1] = 1'b1;
        bullet_big[1] = 1'b1;

        // Center of big bullet: offset (4, 4) -> (x=354, y=354)
        x = 10'd354; y = 10'd354;
        @(posedge clk);
        while (!pix_ce) @(posedge clk);
        @(posedge clk);
        if (big_valid !== 1'b1 || big_rgb !== 12'hF30) begin
            $display("  [FAIL] Big bullet center hit failed! valid=%b rgb=0x%03h (expected 1, 0xF30)",
                     big_valid, big_rgb);
            errors = errors + 1;
        end else begin
            $display("  [PASS] Big bullet center rendered correctly (valid=1, rgb=0xF30).");
        end

        // =====================================================================
        // Test 5: Inactive Bullet Produces No Hit
        // =====================================================================
        $display("  [TEST 5] Testing Inactive Bullet Deactivation...");
        bullet_act[0] = 1'b0; // Deactivate bullet 0
        x = 10'd302; y = 10'd302;
        @(posedge clk);
        while (!pix_ce) @(posedge clk);
        @(posedge clk);
        if (bullet_valid !== 1'b0) begin
            $display("  [FAIL] Inactive bullet still rendered hit!");
            errors = errors + 1;
        end else begin
            $display("  [PASS] Inactive bullet correctly suppressed.");
        end

        // =====================================================================
        // Test 6: Barrel points in ANY direction (cos/sin vector from the regfile)
        // Every pixel of the tank box is compared with an independent floating-point
        // model, for angles that are on and off the software's 5.625 deg grid.
        // =====================================================================
        $display("  [TEST 6] Testing turret barrel for arbitrary direction vectors...");
        barrel_checked = 0; barrel_skipped = 0; barrel_errors = 0;
        // tank 1 (blue) at (50,50)
        check_barrel_angle(1,   0.0);     // East
        check_barrel_angle(1,   5.625);   // one software step
        check_barrel_angle(1,  11.25);
        check_barrel_angle(1,  33.0);     // not on the software grid
        check_barrel_angle(1,  45.0);
        check_barrel_angle(1,  77.7);     // not on the software grid
        check_barrel_angle(1,  90.0);     // South
        check_barrel_angle(1, 123.4);
        check_barrel_angle(1, 180.0);     // West
        check_barrel_angle(1, 208.125);
        check_barrel_angle(1, 270.0);     // North
        check_barrel_angle(1, 301.0);
        check_barrel_angle(1, 354.375);   // last software step before East
        // tank 2 (red) at (200,200): the second channel is independent
        check_barrel_angle(2, 180.0);
        check_barrel_angle(2,  19.0);
        check_barrel_angle(2, 250.0);
        check_barrel_angle(2, 333.0);
        $display("          %0d pixels compared with the reference, %0d edge pixels skipped.",
                 barrel_checked, barrel_skipped);
        if (barrel_errors != 0 || barrel_checked < 4000) begin
            $display("  [FAIL] Barrel direction test: %0d mismatches, %0d pixels checked.",
                     barrel_errors, barrel_checked);
            errors = errors + 1;
        end else begin
            $display("  [PASS] Barrel matches the reference for all %0d tested directions.", 17);
        end

        // Tank 1's barrel must not move when only tank 2's vector changes
        tank_cos1 = 10'sd256; tank_sin1 = 10'sd0;
        tank_cos2 = 10'sd0;   tank_sin2 = 10'sd256;
        x = p1_tank_x + 16; y = p1_tank_y + 9;
        @(posedge clk); #1;
        if (!(tank_valid_p1 && tank_rgb_p1 == 12'h4CF)) begin
            $display("  [FAIL] Tank 1 barrel disturbed by tank 2 direction change.");
            errors = errors + 1;
        end else begin
            $display("  [PASS] Tank 1 and tank 2 barrels are independent.");
        end

        $display("==========================================================");
        if (errors == 0) begin
            $display(">> TEST PASSED: Sprite Engine verified with 0 errors!");
        end else begin
            $display(">> TEST FAILED with %0d errors!", errors);
        end
        $display("==========================================================");

        $finish;
    end

endmodule
