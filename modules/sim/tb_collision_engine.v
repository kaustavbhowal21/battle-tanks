`timescale 1ns / 1ps
//=============================================================================
// Testbench: Hardware Collision Engine Verification
// Verifies:
// 1. Part A: Bullet-Bullet 28-Pair AABB Overlap Matrix (Mutual Annihilation).
// 2. Part B: Bullet-Tank 16-Cell AABB Overlap Matrix (Damage Detection).
// 3. Part C: 8-Clock Time-Shared Bullet-Wall Scanner using Maze RAM Copy C.
// 4. Part D: Sticky Hit Registers and Write-1-to-Clear (W1C) Handshake.
// 5. Part E: MMIO Read Multiplexer (0x20, 0x24, 0x28, 0x2C).
//=============================================================================

module tb_collision_engine;

    reg        clk;
    reg        reset_n;

    reg  [9:0] p1_tank_x, p1_tank_y;
    reg  [9:0] p2_tank_x, p2_tank_y;

    reg  [9:0] bullet_x   [0:7];
    reg  [9:0] bullet_y   [0:7];
    reg  [7:0] bullet_act;
    reg  [7:0] bullet_big;

    wire [8:0] maze_c_addr;
    reg  [1:0] maze_c_data;

    reg        wr_en_col;
    reg  [31:0] d_addr;
    reg  [31:0] d_wdata;
    wire [31:0] rd_col;

    integer errors = 0;
    integer bi;

    // Mock 400-word Maze RAM Copy C
    reg [1:0] mock_maze_c [0:399];

    collision_engine dut (
        .clk         (clk),
        .reset_n     (reset_n),
        .p1_tank_x   (p1_tank_x),
        .p1_tank_y   (p1_tank_y),
        .p2_tank_x   (p2_tank_x),
        .p2_tank_y   (p2_tank_y),
        .bullet_x    (bullet_x),
        .bullet_y    (bullet_y),
        .bullet_act  (bullet_act),
        .bullet_big  (bullet_big),
        .maze_c_addr (maze_c_addr),
        .maze_c_data (maze_c_data),
        .wr_en_col   (wr_en_col),
        .d_addr      (d_addr),
        .d_raddr     (d_addr),
        .d_wdata     (d_wdata),
        .rd_col      (rd_col)
    );

    // 50 MHz clock
    initial begin
        clk = 1'b0;
        forever #10 clk = ~clk;
    end

    // Synchronous mock BRAM read
    always @(posedge clk) begin
        if (maze_c_addr < 400)
            maze_c_data <= mock_maze_c[maze_c_addr];
        else
            maze_c_data <= 2'b00;
    end

    initial begin
        $display("==========================================================");
        $display("   TESTBENCH: HARDWARE COLLISION ENGINE VERIFICATION      ");
        $display("==========================================================");

        // Prepopulate maze BRAM: tile (5, 5) is a brick wall (2'b01)
        for (bi = 0; bi < 400; bi = bi + 1) begin
            mock_maze_c[bi] = 2'b00;
        end
        mock_maze_c[5*20 + 5] = 2'b01; // Brick at (row 5, col 5)

        reset_n = 1'b0;
        p1_tank_x = 10'd50;  p1_tank_y = 10'd50;
        p2_tank_x = 10'd400; p2_tank_y = 10'd400;

        for (bi = 0; bi < 8; bi = bi + 1) begin
            bullet_x[bi] = 10'd0;
            bullet_y[bi] = 10'd0;
        end
        bullet_act = 8'b00000000;
        bullet_big = 8'b00000000;

        wr_en_col = 1'b0;
        d_addr = 32'h8000_0020;
        d_wdata = 32'd0;

        #100;
        @(posedge clk);
        reset_n = 1'b1;
        @(posedge clk);

        // =====================================================================
        // Test 1: Bullet-Bullet AABB Overlap (Pair 0: Bullet 0 and Bullet 1)
        // =====================================================================
        $display("  [TEST 1] Testing Bullet-Bullet Mutual Overlap...");
        // Place Bullet 0 at (200, 200) and Bullet 1 at (202, 202) -> 6x6 boxes overlap!
        bullet_x[0] = 10'd200; bullet_y[0] = 10'd200; bullet_act[0] = 1'b1;
        bullet_x[1] = 10'd202; bullet_y[1] = 10'd202; bullet_act[1] = 1'b1;
        @(posedge clk); // Latch into sticky register
        #5;

        // Check MMIO read 0x8000_0028 (BB_MASK)
        d_addr = 32'h8000_0028;
        #5;
        // Bullet 0 and Bullet 1 should both be flagged in BB_MASK (bits 0 and 1 = 2'b11)
        if ((rd_col & 8'h03) !== 8'h03) begin
            $display("  [FAIL] Bullet-Bullet collision failed! Expected bits [1:0]==2'b11, got 0x%02h", rd_col[7:0]);
            errors = errors + 1;
        end else begin
            $display("  [PASS] Bullet 0 and Bullet 1 mutual collision detected (BB_MASK=0x%02h).", rd_col[7:0]);
        end

        // Move bullets apart
        bullet_x[1] = 10'd300; bullet_y[1] = 10'd300;
        @(posedge clk);
        #5;
        // Verify sticky behavior: register should still report hit!
        if ((rd_col & 8'h03) !== 8'h03) begin
            $display("  [FAIL] Collision was not sticky! Dropped prematurely.");
            errors = errors + 1;
        end else begin
            $display("  [PASS] Sticky register correctly retained collision flag after separation.");
        end

        // Write-1-to-Clear (W1C) handshake: Write 0x03 to 0x8000_0028
        wr_en_col = 1'b1;
        d_addr = 32'h8000_0028;
        d_wdata = 32'h0000_0003;
        @(posedge clk);
        #1 wr_en_col = 1'b0;   // hold past the edge: avoids a TB/DUT scheduling race
        #5;
        if ((rd_col & 8'h03) !== 8'h00) begin
            $display("  [FAIL] Write-1-to-Clear failed! Bits still set: 0x%02h", rd_col[7:0]);
            errors = errors + 1;
        end else begin
            $display("  [PASS] Write-1-to-Clear (W1C) cleanly cleared collision bits.");
        end

        // =====================================================================
        // Test 2: Bullet-Tank Overlap (Bullet 0 hits Tank 1)
        // =====================================================================
        $display("  [TEST 2] Testing Bullet-Tank Hit Detection...");
        // Tank 1 is at (50, 50), size 20x20 (x: 50..69, y: 50..69)
        // Place Bullet 0 at (55, 55)
        bullet_x[0] = 10'd55; bullet_y[0] = 10'd55;
        @(posedge clk);
        #5;

        // Read 0x8000_002C (HIT_MASK): bits [7:0] bullet hits, bits [9:8] tank hits
        d_addr = 32'h8000_002C;
        #5;
        // Tank 1 is bit 8, Bullet 0 is bit 0 -> (1 << 8) | (1 << 0) = 0x0101
        if ((rd_col & 32'h0000_0101) !== 32'h0000_0101) begin
            $display("  [FAIL] Bullet-Tank hit failed! Expected 0x101, got 0x%04h", rd_col[15:0]);
            errors = errors + 1;
        end else begin
            $display("  [PASS] Bullet 0 hit Tank 1 detected (HIT_MASK=0x%04h).", rd_col[15:0]);
        end

        // Clear Tank hit register
        bullet_x[0] = 10'd0; bullet_act[0] = 1'b0; // Deactivate bullet
        wr_en_col = 1'b1;
        d_addr = 32'h8000_002C;
        d_wdata = 32'h0000_0101;
        @(posedge clk);
        #1 wr_en_col = 1'b0;   // hold past the edge: avoids a TB/DUT scheduling race
        #5;
        if ((rd_col & 32'h0000_0101) !== 32'd0) begin
            $display("  [FAIL] Clear HIT_MASK failed! Got 0x%04h", rd_col[15:0]);
            errors = errors + 1;
        end else begin
            $display("  [PASS] HIT_MASK cleared via W1C.");
        end

        // =====================================================================
        // Test 3: Time-Shared Bullet-Wall Scanner (Bullet 3 hits Brick)
        // =====================================================================
        $display("  [TEST 3] Testing 8-Clock Time-Shared Bullet-Wall Scanner...");
        // Tile (5, 5) is pixel coordinate x = 5*24 = 120, y = 5*24 = 120.
        // Place active Bullet 3 at (122, 122)
        bullet_x[3] = 10'd122; bullet_y[3] = 10'd122;
        bullet_act[3] = 1'b1;
        bullet_big[3] = 1'b0;

        // Run for 16 clocks (2 complete 8-clock scan cycles + BRAM delay)
        repeat(16) @(posedge clk);

        // Read 0x8000_0024 (WALL_MASK): Bullet 3 should be flagged (bit 3 = 1 << 3 = 0x08)
        d_addr = 32'h8000_0024;
        #5;
        if ((rd_col & 8'h08) !== 8'h08) begin
            $display("  [FAIL] Wall scanner failed to detect bullet 3 hitting brick! Got 0x%02h", rd_col[7:0]);
            errors = errors + 1;
        end else begin
            $display("  [PASS] Bullet-Wall scanner successfully detected collision (WALL_MASK=0x%02h).", rd_col[7:0]);
        end

        // Clear WALL_MASK
        bullet_act[3] = 1'b0;
        wr_en_col = 1'b1;
        d_addr = 32'h8000_0024;
        d_wdata = 32'h0000_0008;
        @(posedge clk);
        #1 wr_en_col = 1'b0;   // hold past the edge: avoids a TB/DUT scheduling race
        #5;
        if ((rd_col & 8'h08) !== 8'h00) begin
            $display("  [FAIL] WALL_MASK clear failed!");
            errors = errors + 1;
        end else begin
            $display("  [PASS] WALL_MASK cleared via W1C.");
        end

        // =====================================================================
        // Test 4: Collision Summary Flags (0x8000_0020)
        // =====================================================================
        $display("  [TEST 4] Testing Top-Level Summary Register (0x8000_0020)...");
        d_addr = 32'h8000_0020;
        #5;
        if (rd_col[2:0] !== 3'b000) begin
            $display("  [FAIL] Summary register should be clean 0, got %b", rd_col[2:0]);
            errors = errors + 1;
        end else begin
            $display("  [PASS] Summary register cleanly reports 0 when all collisions cleared.");
        end

        $display("==========================================================");
        if (errors == 0) begin
            $display(">> TEST PASSED: Hardware Collision Engine verified with 0 errors!");
        end else begin
            $display(">> TEST FAILED with %0d errors!", errors);
        end
        $display("==========================================================");

        $finish;
    end

endmodule
