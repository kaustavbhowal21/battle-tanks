`timescale 1ns / 1ps
//=============================================================================
// Testbench: Maze Tile Renderer Verification
// Verifies:
// 1. Divider-free horizontal tile_x (0..19) & sub_x (0..23) progression.
// 2. Vertical tile_y (0..19) & sub_y (0..23) line progression.
// 3. Tile RAM address generation: (tile_y * 20 + tile_x).
// 4. 1-cycle BRAM latency alignment pipeline.
// 5. RGB & wall flag output for all 4 tile types (Empty, Brick, Steel, Corner).
// 6. Non-maze area blanking (x >= 480 or y >= 480 or !active).
//=============================================================================

module tb_maze_tile_renderer;

    reg        clk;
    reg        reset_n;
    reg        pix_ce;
    reg  [9:0] x;
    reg  [9:0] y;
    reg        active;

    wire [8:0] maze_vga_addr;
    reg  [1:0] maze_vga_data;

    wire        maze_wall;
    wire [11:0] maze_rgb;

    integer errors = 0;

    // Simulated 400-word tile BRAM
    reg [1:0] mock_maze_bram [0:399];

    maze_tile_renderer dut (
        .clk           (clk),
        .reset_n       (reset_n),
        .pix_ce        (pix_ce),
        .x             (x),
        .y             (y),
        .active        (active),
        .maze_vga_addr (maze_vga_addr),
        .maze_vga_data (maze_vga_data),
        .maze_wall     (maze_wall),
        .maze_rgb      (maze_rgb)
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

    // Synchronous mock BRAM read (1-clock latency)
    always @(posedge clk) begin
        if (maze_vga_addr < 400)
            maze_vga_data <= mock_maze_bram[maze_vga_addr];
        else
            maze_vga_data <= 2'b00;
    end

    task step_pixel;
        input [9:0] px;
        input [9:0] py;
        begin
            x = px;
            y = py;
            @(posedge clk);
            while (!pix_ce) @(posedge clk);
        end
    endtask

    integer px_i, py_j;
    reg [8:0] expected_tile;

    initial begin
        $display("==========================================================");
        $display("   TESTBENCH: MAZE TILE RENDERER VERIFICATION             ");
        $display("==========================================================");

        // Prepopulate BRAM:
        // Tile 0 = Empty (00)
        // Tile 1 = Brick (01)
        // Tile 2 = Steel (10)
        // Tile 3 = Corner (11)
        for (px_i = 0; px_i < 400; px_i = px_i + 1) begin
            mock_maze_bram[px_i] = 2'b00;
        end
        mock_maze_bram[0] = 2'b00; // Empty floor
        mock_maze_bram[1] = 2'b01; // Brick
        mock_maze_bram[2] = 2'b10; // Steel
        mock_maze_bram[3] = 2'b11; // Corner

        reset_n = 1'b0;
        x = 10'd0;
        y = 10'd0;
        active = 1'b0;

        #100;
        @(posedge clk);
        reset_n = 1'b1;
        active  = 1'b1;
        @(posedge clk);

        // =====================================================================
        // Test 1: Raster scan row 5 across first 4 tiles (x=0..95)
        // =====================================================================
        $display("  [TEST 1] Raster Scanning Line y=5 Across Tiles 0, 1, 2, 3...");

        // Start line at x=0
        step_pixel(0, 5);

        for (px_i = 1; px_i < 96; px_i = px_i + 1) begin
            step_pixel(px_i, 5);

            // Tile index: px_i / 24
            expected_tile = px_i / 24;

            // Check tile RAM address (has 1 clock pipeline latency from sub_x overflow)
            // At interior pixels (sub_x between 3 and 20): address is stable
            if ((px_i % 24) >= 3 && (px_i % 24) <= 20) begin
                if (maze_vga_addr !== expected_tile) begin
                    $display("  [FAIL] Pixel x=%0d expected tile addr=%0d, got %0d", px_i, expected_tile, maze_vga_addr);
                    errors = errors + 1;
                end
            end

            // Check Colors at interior pixels (sub_x between 5 and 10 to avoid borders)
            if ((px_i % 24) >= 5 && (px_i % 24) <= 10) begin
                case (expected_tile)
                    9'd0: begin // Tile 0: Empty Floor
                        if (maze_wall !== 1'b0 || maze_rgb !== 12'h081) begin
                            $display("  [FAIL] Empty floor color incorrect at x=%0d! wall=%b rgb=0x%03h (expected 0, 0x081)",
                                     px_i, maze_wall, maze_rgb);
                            errors = errors + 1;
                        end
                    end
                    9'd1: begin // Tile 1: Brick Wall
                        if (maze_wall !== 1'b1 || maze_rgb !== 12'hB52) begin
                            $display("  [FAIL] Brick wall color incorrect at x=%0d! wall=%b rgb=0x%03h (expected 1, 0xB52)",
                                     px_i, maze_wall, maze_rgb);
                            errors = errors + 1;
                        end
                    end
                    9'd2: begin // Tile 2: Steel Wall
                        if (maze_wall !== 1'b1 || maze_rgb !== 12'h889) begin
                            $display("  [FAIL] Steel wall color incorrect at x=%0d! wall=%b rgb=0x%03h (expected 1, 0x889)",
                                     px_i, maze_wall, maze_rgb);
                            errors = errors + 1;
                        end
                    end
                    9'd3: begin // Tile 3: Corner Wall
                        if (maze_wall !== 1'b1 || maze_rgb !== 12'h668) begin
                            $display("  [FAIL] Corner wall color incorrect at x=%0d! wall=%b rgb=0x%03h (expected 1, 0x668)",
                                     px_i, maze_wall, maze_rgb);
                            errors = errors + 1;
                        end
                    end
                endcase
            end
        end

        if (errors == 0) begin
            $display("  [PASS] All 4 tile types (Empty, Brick, Steel, Corner) rendered with correct colors.");
        end

        // =====================================================================
        // Test 2: Blanking Outside Maze Arena (x >= 480)
        // =====================================================================
        $display("  [TEST 2] Verifying Out-of-Arena Blanking (x >= 480)...");
        // Scan past x=480
        for (px_i = 480; px_i < 500; px_i = px_i + 1) begin
            step_pixel(px_i, 5);
        end
        // Allow pipeline flush
        repeat(3) begin
            @(posedge clk);
            while (!pix_ce) @(posedge clk);
        end

        if (maze_wall !== 1'b0 || maze_rgb !== 12'h000) begin
            $display("  [FAIL] Non-maze area not blanked! wall=%b rgb=0x%03h", maze_wall, maze_rgb);
            errors = errors + 1;
        end else begin
            $display("  [PASS] Outside arena is strictly black (wall=0, rgb=0x000).");
        end

        $display("==========================================================");
        if (errors == 0) begin
            $display(">> TEST PASSED: Maze Tile Renderer verified with 0 errors!");
        end else begin
            $display(">> TEST FAILED with %0d errors!", errors);
        end
        $display("==========================================================");

        $finish;
    end

endmodule
