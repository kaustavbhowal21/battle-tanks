`timescale 1ns / 1ps
//=============================================================================
// Testbench: Maze Tile Renderer - Full-Frame Regression
//
// Drives maze_tile_renderer with the REAL vga_timing_gen (including horizontal
// and vertical blanking) for two full frames and checks that, in the interior
// of every 24x24 tile, the tile RAM address equals (y/24)*20 + (x/24) and never
// leaves 0..399.
//
// Regression for: the old tile_y/sub_y counters advanced whenever x == 0, but the timing
// generator holds x at 0 for the entire horizontal blanking interval (~160
// pixel clocks), so the row counter ran away every line and the playfield was
// rendered as garbled horizontal stripes instead of a clean green arena.
//=============================================================================

module tb_maze_tile_renderer_frame;

    reg clk = 1'b0;
    reg reset_n = 1'b0;
    reg pix_ce = 1'b0;

    always #10 clk = ~clk;                 // 50 MHz
    always @(posedge clk) pix_ce <= ~pix_ce; // 25 MHz enable

    wire [9:0] x, y;
    wire       active;
    wire       frame_tick;

    vga_timing_gen u_timing (
        .clk(clk), .reset_n(reset_n), .pix_ce(pix_ce),
        .x(x), .y(y), .hcnt(), .vcnt(),
        .hsync_n(), .vsync_n(), .active(active),
        .h_end(), .v_end(), .frame_tick(frame_tick)
    );

    wire [8:0] maze_vga_addr;
    wire [1:0] maze_vga_data;

    maze_tile_ram u_ram (
        .clk(clk), .reset_n(reset_n),
        .wr_en_maze(1'b0), .d_addr(32'h8000_0100), .d_wdata(32'd0), .rd_maze(),
        .vga_tile_addr(maze_vga_addr), .vga_tile_data(maze_vga_data),
        .col_tile_addr(9'd0), .col_tile_data()
    );

    wire        maze_wall;
    wire [11:0] maze_rgb;

    maze_tile_renderer dut (
        .clk(clk), .reset_n(reset_n), .pix_ce(pix_ce),
        .x(x), .y(y), .active(active),
        .maze_vga_addr(maze_vga_addr), .maze_vga_data(maze_vga_data),
        .maze_wall(maze_wall), .maze_rgb(maze_rgb)
    );

    integer errors  = 0;
    integer checks  = 0;
    integer frames  = 0;
    integer exp_row, exp_col, exp_addr;
    integer sx, sy;

    always @(posedge clk) begin
        if (reset_n && pix_ce) begin
            if (frame_tick)
                frames = frames + 1;

            // Out-of-range address is always a failure
            if (maze_vga_addr > 9'd399) begin
                if (errors < 10)
                    $display("  [FAIL] x=%0d y=%0d: tile addr %0d out of range", x, y, maze_vga_addr);
                errors = errors + 1;
            end

            // Check the tile interior (sub-pixel 4..19) so the 1-2 pixel
            // pipeline skew at tile edges is irrelevant.
            if (frames >= 1 && active && x < 480 && y < 480) begin
                sx = x % 24;
                sy = y % 24;
                if (sx >= 4 && sx <= 19 && sy >= 1 && sy <= 22) begin
                    exp_row  = y / 24;
                    exp_col  = x / 24;
                    exp_addr = exp_row * 20 + exp_col;
                    checks = checks + 1;
                    if (maze_vga_addr !== exp_addr[8:0]) begin
                        if (errors < 10)
                            $display("  [FAIL] x=%0d y=%0d: tile addr %0d, expected %0d", x, y, maze_vga_addr, exp_addr);
                        errors = errors + 1;
                    end
                end
            end

            if (frames >= 3) begin
                $display("==========================================================");
                $display("   Maze Tile Renderer full-frame check: %0d samples", checks);
                if (errors == 0)
                    $display(">> TEST PASSED: tile addressing correct over full frames (0 errors)");
                else
                    $display(">> TEST FAILED with %0d errors!", errors);
                $display("==========================================================");
                $finish;
            end
        end
    end

    initial begin
        #100;
        reset_n = 1'b1;
    end

    initial begin
        #200_000_000;
        $display(">> TEST FAILED: timeout");
        $finish;
    end

endmodule
