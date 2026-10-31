`timescale 1ns / 1ps
//=============================================================================
// Testbench: Sprite & HUD Register File Verification
// Verifies:
// 1. Power-on reset defaults (P1, P2 positions, health = 20 hearts, bullets inactive).
// 2. MMIO Register Write & Unpacking:
//    - 0x8000_0040: Tank 1 Position (x, y)
//    - 0x8000_0044: Tank 2 Position (x, y)
//    - 0x8000_0048..0x64: Bullet 0..7 coordinates, active and big flags
//    - 0x8000_0080: Player 1 and Player 2 Health (hp1, hp2)
//    - 0x8000_0084: Tank 1 and Tank 2 Turret Angles (ang1, ang2)
// 3. Continuous live drive to hardware renderers and collision engine.
//=============================================================================

module tb_sprite_hud_regfile;

    reg        clk;
    reg        reset_n;
    reg        wr_en_spr;
    reg  [31:0] d_addr;
    reg  [31:0] d_wdata;

    wire [9:0] p1_tank_x;
    wire [9:0] p1_tank_y;
    wire [9:0] p2_tank_x;
    wire [9:0] p2_tank_y;

    wire [9:0] bullet_x   [0:7];
    wire [9:0] bullet_y   [0:7];
    wire [7:0] bullet_act;
    wire [7:0] bullet_big;

    wire [7:0] hp1;
    wire [7:0] hp2;
    wire [3:0] tank_ang1;
    wire [3:0] tank_ang2;

    integer errors = 0;
    integer bi;

    sprite_hud_regfile dut (
        .clk        (clk),
        .reset_n    (reset_n),
        .wr_en_spr  (wr_en_spr),
        .d_addr     (d_addr),
        .d_wdata    (d_wdata),
        .p1_tank_x  (p1_tank_x),
        .p1_tank_y  (p1_tank_y),
        .p2_tank_x  (p2_tank_x),
        .p2_tank_y  (p2_tank_y),
        .bullet_x   (bullet_x),
        .bullet_y   (bullet_y),
        .bullet_act (bullet_act),
        .bullet_big (bullet_big),
        .hp1        (hp1),
        .hp2        (hp2),
        .tank_ang1  (tank_ang1),
        .tank_ang2  (tank_ang2)
    );

    // 50 MHz clock
    initial begin
        clk = 1'b0;
        forever #10 clk = ~clk;
    end

    task write_reg;
        input [31:0] addr;
        input [31:0] data;
        begin
            @(posedge clk);
            d_addr    <= addr;
            d_wdata   <= data;
            wr_en_spr <= 1'b1;
            @(posedge clk);
            wr_en_spr <= 1'b0;
        end
    endtask

    initial begin
        $display("==========================================================");
        $display("   TESTBENCH: SPRITE & HUD REGFILE VERIFICATION           ");
        $display("==========================================================");

        reset_n = 1'b0;
        wr_en_spr = 1'b0;
        d_addr = 32'h8000_0040;
        d_wdata = 32'd0;

        #100;
        @(posedge clk);
        reset_n = 1'b1;
        @(posedge clk);

        // =====================================================================
        // Test 1: Power-On Reset Defaults
        // =====================================================================
        $display("  [TEST 1] Testing Power-On Reset Defaults...");
        if (p1_tank_x !== 10'd50 || p1_tank_y !== 10'd100) begin
            $display("  [FAIL] Tank 1 initial coords mismatch! Expected (50, 100), got (%0d, %0d)",
                     p1_tank_x, p1_tank_y);
            errors = errors + 1;
        end else begin
            $display("  [PASS] Tank 1 reset position correct (50, 100).");
        end

        if (p2_tank_x !== 10'd400 || p2_tank_y !== 10'd350) begin
            $display("  [FAIL] Tank 2 initial coords mismatch! Expected (400, 350), got (%0d, %0d)",
                     p2_tank_x, p2_tank_y);
            errors = errors + 1;
        end else begin
            $display("  [PASS] Tank 2 reset position correct (400, 350).");
        end

        if (hp1 !== 8'd20 || hp2 !== 8'd20) begin
            $display("  [FAIL] Health reset mismatch! Expected hp1=20, hp2=20, got hp1=%0d, hp2=%0d", hp1, hp2);
            errors = errors + 1;
        end else begin
            $display("  [PASS] Both players initial health = 20 hearts.");
        end

        if (bullet_act !== 8'b00000000) begin
            $display("  [FAIL] Bullets not initially inactive! Got act=%b", bullet_act);
            errors = errors + 1;
        end else begin
            $display("  [PASS] All 8 bullets initially inactive.");
        end

        // =====================================================================
        // Test 2: Writing Tank 1 and Tank 2 Coordinates
        // =====================================================================
        $display("  [TEST 2] Testing Tank Coordinate MMIO Updates...");
        // Update Tank 1 to (x=120, y=85)
        write_reg(32'h8000_0040, {16'd85, 16'd120});

        // Update Tank 2 to (x=300, y=250)
        write_reg(32'h8000_0044, {16'd250, 16'd300});

        @(posedge clk);
        #5;
        if (p1_tank_x !== 10'd120 || p1_tank_y !== 10'd85) begin
            $display("  [FAIL] Tank 1 coordinates not updated! Got (%0d, %0d)", p1_tank_x, p1_tank_y);
            errors = errors + 1;
        end else begin
            $display("  [PASS] Tank 1 coordinates updated to (%0d, %0d).", p1_tank_x, p1_tank_y);
        end

        if (p2_tank_x !== 10'd300 || p2_tank_y !== 10'd250) begin
            $display("  [FAIL] Tank 2 coordinates not updated! Got (%0d, %0d)", p2_tank_x, p2_tank_y);
            errors = errors + 1;
        end else begin
            $display("  [PASS] Tank 2 coordinates updated to (%0d, %0d).", p2_tank_x, p2_tank_y);
        end

        // =====================================================================
        // Test 3: Writing Bullet MMIO Registers
        // =====================================================================
        $display("  [TEST 3] Testing Bullet Coordinate and Flag Unpacking...");
        // Configure Bullet 0: Normal bullet, active, at (x=200, y=150)
        write_reg(32'h8000_0048, {10'd0, 1'b0, 1'b1, 10'd150, 10'd200});

        // Configure Bullet 1: Big bullet, active, at (x=350, y=275)
        write_reg(32'h8000_004C, {10'd0, 1'b1, 1'b1, 10'd275, 10'd350});

        @(posedge clk);
        #5;
        if (bullet_x[0] !== 10'd200 || bullet_y[0] !== 10'd150 || bullet_act[0] !== 1'b1 || bullet_big[0] !== 1'b0) begin
            $display("  [FAIL] Bullet 0 unpacking failed! x=%0d y=%0d act=%b big=%b",
                     bullet_x[0], bullet_y[0], bullet_act[0], bullet_big[0]);
            errors = errors + 1;
        end else begin
            $display("  [PASS] Bullet 0 unpacked: Normal active bullet at (200, 150).");
        end

        if (bullet_x[1] !== 10'd350 || bullet_y[1] !== 10'd275 || bullet_act[1] !== 1'b1 || bullet_big[1] !== 1'b1) begin
            $display("  [FAIL] Bullet 1 unpacking failed! x=%0d y=%0d act=%b big=%b",
                     bullet_x[1], bullet_y[1], bullet_act[1], bullet_big[1]);
            errors = errors + 1;
        end else begin
            $display("  [PASS] Bullet 1 unpacked: Big active bullet at (350, 275).");
        end

        // =====================================================================
        // Test 4: Health and Tank Angles Updates
        // =====================================================================
        $display("  [TEST 4] Testing Health and Angles Unpacking...");
        // 0x80: Health bar {16'd0, hp2[7:0], hp1[7:0]}
        write_reg(32'h8000_0080, {16'd0, 8'd14, 8'd18}); // hp2=14, hp1=18

        // 0x84: Tank angles {24'd0, ang2[3:0], ang1[3:0]}
        write_reg(32'h8000_0084, {24'd0, 4'd11, 4'd5}); // ang2=11, ang1=5

        @(posedge clk);
        #5;
        if (hp1 !== 8'd18 || hp2 !== 8'd14) begin
            $display("  [FAIL] Health register unpack failed! Expected hp1=18, hp2=14, got %0d, %0d", hp1, hp2);
            errors = errors + 1;
        end else begin
            $display("  [PASS] Health registers updated (hp1=18, hp2=14).");
        end

        if (tank_ang1 !== 4'd5 || tank_ang2 !== 4'd11) begin
            $display("  [FAIL] Tank angles unpack failed! Expected ang1=5, ang2=11, got %0d, %0d", tank_ang1, tank_ang2);
            errors = errors + 1;
        end else begin
            $display("  [PASS] Tank angles updated (ang1=5, ang2=11).");
        end

        $display("==========================================================");
        if (errors == 0) begin
            $display(">> TEST PASSED: Sprite & HUD Regfile verified with 0 errors!");
        end else begin
            $display(">> TEST FAILED with %0d errors!", errors);
        end
        $display("==========================================================");

        $finish;
    end

endmodule
