`timescale 1ns / 1ps
//=============================================================================
// Testbench: Maze Tile RAM (Mirrored BRAM) Verification
// Verifies:
// 1. Initial maze contents (perimeter walls and pillars).
// 2. CPU Port A simultaneous write to both Copy V and Copy C.
// 3. CPU synchronous read (rd_maze) from Copy V.
// 4. VGA Port B independent read from Copy V.
// 5. Collision Port B independent read from Copy C.
// 6. Zero-contention simultaneous dual reads across copies.
//=============================================================================

module tb_maze_tile_ram;

    reg        clk;
    reg        reset_n;
    reg        wr_en_maze;
    reg  [31:0] d_addr;
    reg  [31:0] d_wdata;
    wire [31:0] rd_maze;

    reg  [8:0]  vga_tile_addr;
    wire [1:0]  vga_tile_data;

    reg  [8:0]  col_tile_addr;
    wire [1:0]  col_tile_data;

    integer errors = 0;

    maze_tile_ram dut (
        .clk           (clk),
        .reset_n       (reset_n),
        .wr_en_maze    (wr_en_maze),
        .d_raddr       (d_addr),
        .d_addr        (d_addr),
        .d_wdata       (d_wdata),
        .rd_maze       (rd_maze),
        .vga_tile_addr (vga_tile_addr),
        .vga_tile_data (vga_tile_data),
        .col_tile_addr (col_tile_addr),
        .col_tile_data (col_tile_data)
    );

    // 50 MHz clock
    initial begin
        clk = 1'b0;
        forever #10 clk = ~clk;
    end

    initial begin
        $display("==========================================================");
        $display("   TESTBENCH: MAZE TILE RAM (MIRRORED BRAM) VERIFICATION  ");
        $display("==========================================================");

        reset_n = 1'b0;
        wr_en_maze = 1'b0;
        d_addr = 32'h8000_0100;
        d_wdata = 32'd0;
        vga_tile_addr = 9'd0;
        col_tile_addr = 9'd0;

        #100;
        @(posedge clk);
        reset_n = 1'b1;
        @(posedge clk);

        // =====================================================================
        // Test 1: Check Pre-Initialized Perimeter Wall
        // =====================================================================
        $display("  [TEST 1] Testing Pre-Initialized Perimeter Wall (Tile 0)...");
        vga_tile_addr = 9'd0; // Tile (0, 0) is top-left perimeter
        col_tile_addr = 9'd0;
        @(posedge clk); // Synchronous read
        #5;

        if (vga_tile_data !== 2'b10 || col_tile_data !== 2'b10) begin
            $display("  [FAIL] Perimeter tile mismatch! VGA=2'b%b, Col=2'b%b (expected 2'b10 steel)",
                     vga_tile_data, col_tile_data);
            errors = errors + 1;
        end else begin
            $display("  [PASS] Both Copy V and Copy C hold initial perimeter steel wall (2'b10).");
        end

        // =====================================================================
        // Test 2: CPU Port A Write to Mirrored BRAMs
        // =====================================================================
        $display("  [TEST 2] Testing CPU Simultaneous Dual-Copy Write...");
        // Tile (5, 5) is index 5*20 + 5 = 105.
        // Base MMIO address is 0x8000_0100.
        // Word address: 0x8000_0100 + (105 << 2) = 0x8000_0100 + 0x1A4 = 0x8000_02A4.
        d_addr = 32'h8000_0100 + (105 << 2);
        d_wdata = 32'h0000_0002; // Write steel wall (2'b10)
        wr_en_maze = 1'b1;
        @(posedge clk);
        wr_en_maze = 1'b0;

        // Verify CPU read from Copy V
        @(posedge clk);
        #5;
        if (rd_maze[1:0] !== 2'b10) begin
            $display("  [FAIL] CPU read from Copy V failed! Expected 2'b10, got 2'b%b", rd_maze[1:0]);
            errors = errors + 1;
        end else begin
            $display("  [PASS] CPU read (rd_maze) returned written value 2'b10.");
        end

        // Verify independent VGA read from Copy V and Collision read from Copy C
        vga_tile_addr = 9'd105;
        col_tile_addr = 9'd105;
        @(posedge clk);
        #5;
        if (vga_tile_data !== 2'b10 || col_tile_data !== 2'b10) begin
            $display("  [FAIL] Mirrored copies out of sync! VGA=2'b%b, Col=2'b%b (expected 2'b10)",
                     vga_tile_data, col_tile_data);
            errors = errors + 1;
        end else begin
            $display("  [PASS] Both Copy V (VGA) and Copy C (Collision) successfully updated to 2'b10.");
        end

        // =====================================================================
        // Test 3: Shattering Destructible Brick to Empty Floor
        // =====================================================================
        $display("  [TEST 3] Testing Brick Shattering (Writing TILE_EMPTY = 0)...");
        d_wdata = 32'h0000_0000; // Clear to empty floor (2'b00)
        wr_en_maze = 1'b1;
        @(posedge clk);
        wr_en_maze = 1'b0;

        @(posedge clk);
        #5;
        if (vga_tile_data !== 2'b00 || col_tile_data !== 2'b00) begin
            $display("  [FAIL] Brick shattering failed! VGA=2'b%b, Col=2'b%b (expected 2'b00)",
                     vga_tile_data, col_tile_data);
            errors = errors + 1;
        end else begin
            $display("  [PASS] Tile 105 cleanly shattered to empty floor in both mirrored copies.");
        end

        // =====================================================================
        // Test 4: Concurrent Dual-Port Reads Without Contention
        // =====================================================================
        $display("  [TEST 4] Testing Simultaneous Independent Reads...");
        // VGA reads tile 0, Collision reads tile 19*20+19 = 399 at the same cycle
        vga_tile_addr = 9'd0;
        col_tile_addr = 9'd399;
        @(posedge clk);
        #5;
        // Both corner tiles are perimeter steel walls (2'b10)
        if (vga_tile_data !== 2'b10 || col_tile_data !== 2'b10) begin
            $display("  [FAIL] Concurrent dual read failed!");
            errors = errors + 1;
        end else begin
            $display("  [PASS] VGA Port B and Collision Port B read simultaneously with zero contention.");
        end

        $display("==========================================================");
        if (errors == 0) begin
            $display(">> TEST PASSED: Maze Tile RAM verified with 0 errors!");
        end else begin
            $display(">> TEST FAILED with %0d errors!", errors);
        end
        $display("==========================================================");

        $finish;
    end

endmodule
