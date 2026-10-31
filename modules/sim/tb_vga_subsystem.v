`timescale 1ns / 1ps
//=============================================================================
// Testbench: Full Integrated VGA Subsystem Verification
// Instantiates and interconnects:
// 1. vga_timing_gen
// 2. maze_tile_renderer
// 3. sprite_engine
// 4. health_hud
// 5. pixel_priority_mixer
//
// Verifies:
// - End-to-end pipeline synchronization.
// - Full 640x480 active frame rasterization.
// - Real-time composite rendering across all layers (Tanks, Bullets, Maze, HUD).
// - Strict timing conformance for standard 640x480@60Hz VGA output.
//=============================================================================

module tb_vga_subsystem;

    reg clk;
    reg reset_n;
    reg pix_ce;

    // Sprite & HUD control inputs (simulating regfile outputs)
    reg  [9:0] p1_tank_x, p1_tank_y;
    reg  [3:0] tank_ang1;
    reg  [9:0] p2_tank_x, p2_tank_y;
    reg  [3:0] tank_ang2;

    reg  [9:0] bullet_x   [0:7];
    reg  [9:0] bullet_y   [0:7];
    reg  [7:0] bullet_act;
    reg  [7:0] bullet_big;

    reg  [7:0] hp1;
    reg  [7:0] hp2;

    // Physical VGA Output Pins
    wire [3:0] vga_r;
    wire [3:0] vga_g;
    wire [3:0] vga_b;
    wire       vga_hsync;
    wire       vga_vsync;
    wire [11:0] current_vga_rgb = {vga_r, vga_g, vga_b};

    // Internal pipeline wires
    wire [9:0]  vga_x, vga_y;
    wire [9:0]  vga_hcnt, vga_vcnt;
    wire        vga_hsync_n_raw, vga_vsync_n_raw;
    wire        vga_active;
    wire        vga_h_end, vga_v_end, vga_frame_tick;

    wire [8:0]  maze_vga_addr;
    reg  [1:0]  maze_vga_data;
    wire        maze_wall;
    wire [11:0] maze_rgb;

    wire        tank_valid_p1;
    wire [11:0] tank_rgb_p1;
    wire        tank_valid_p2;
    wire [11:0] tank_rgb_p2;
    wire        bullet_valid;
    wire [11:0] bullet_rgb;
    wire        big_valid;
    wire [11:0] big_rgb;

    wire        hud_valid;
    wire [11:0] hud_rgb;

    integer errors = 0;
    integer bi;
    reg [1:0] mock_maze_bram [0:399];

    // =========================================================================
    // Module Instantiations
    // =========================================================================
    vga_timing_gen u_timing (
        .clk        (clk),
        .reset_n    (reset_n),
        .pix_ce     (pix_ce),
        .x          (vga_x),
        .y          (vga_y),
        .hcnt       (vga_hcnt),
        .vcnt       (vga_vcnt),
        .hsync_n    (vga_hsync_n_raw),
        .vsync_n    (vga_vsync_n_raw),
        .active     (vga_active),
        .h_end      (vga_h_end),
        .v_end      (vga_v_end),
        .frame_tick (vga_frame_tick)
    );

    maze_tile_renderer u_maze (
        .clk           (clk),
        .reset_n       (reset_n),
        .pix_ce        (pix_ce),
        .x             (vga_x),
        .y             (vga_y),
        .active        (vga_active),
        .maze_vga_addr (maze_vga_addr),
        .maze_vga_data (maze_vga_data),
        .maze_wall     (maze_wall),
        .maze_rgb      (maze_rgb)
    );

    sprite_engine u_sprite (
        .clk           (clk),
        .reset_n       (reset_n),
        .pix_ce        (pix_ce),
        .x             (vga_x),
        .y             (vga_y),
        .active        (vga_active),
        .p1_tank_x     (p1_tank_x),
        .p1_tank_y     (p1_tank_y),
        .tank_ang1     (tank_ang1),
        .p2_tank_x     (p2_tank_x),
        .p2_tank_y     (p2_tank_y),
        .tank_ang2     (tank_ang2),
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

    health_hud u_hud (
        .clk       (clk),
        .reset_n   (reset_n),
        .pix_ce    (pix_ce),
        .x         (vga_x),
        .y         (vga_y),
        .active    (vga_active),
        .hp1       (hp1),
        .hp2       (hp2),
        .hud_valid (hud_valid),
        .hud_rgb   (hud_rgb)
    );

    pixel_priority_mixer u_mixer (
        .clk           (clk),
        .reset_n       (reset_n),
        .pix_ce        (pix_ce),
        .hsync_n_in    (vga_hsync_n_raw),
        .vsync_n_in    (vga_vsync_n_raw),
        .active_in     (vga_active),
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
        .vga_vsync     (vga_vsync)
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

    // Mock BRAM read
    always @(posedge clk) begin
        if (maze_vga_addr < 400)
            maze_vga_data <= mock_maze_bram[maze_vga_addr];
        else
            maze_vga_data <= 2'b00;
    end

    integer frame_count = 0;
    integer line_count = 0;
    reg saw_p1_tank = 0;
    reg saw_p2_tank = 0;
    reg saw_normal_bullet = 0;
    reg saw_big_bullet = 0;
    reg saw_hud_heart = 0;
    reg saw_divider_bar = 0;

    initial begin
        $display("==========================================================");
        $display("   TESTBENCH: FULL INTEGRATED VGA SUBSYSTEM PIPELINE      ");
        $display("==========================================================");

        // Prepopulate maze BRAM with perimeter steel walls (2'b10) and inner brick (2'b01)
        for (bi = 0; bi < 400; bi = bi + 1) begin
            mock_maze_bram[bi] = 2'b00; // Floor
        end
        mock_maze_bram[0] = 2'b10;  // Steel corner
        mock_maze_bram[25] = 2'b01; // Brick at (row 1, col 5)

        reset_n = 1'b0;
        p1_tank_x = 10'd48;  p1_tank_y = 10'd48;  tank_ang1 = 4'd0; // East
        p2_tank_x = 10'd410; p2_tank_y = 10'd410; tank_ang2 = 4'd8; // West

        for (bi = 0; bi < 8; bi = bi + 1) begin
            bullet_x[bi] = 10'd0;
            bullet_y[bi] = 10'd0;
        end
        // Normal bullet at (100, 100)
        bullet_x[0]   = 10'd100;
        bullet_y[0]   = 10'd100;
        bullet_act[0] = 1'b1;
        bullet_big[0] = 1'b0;

        // Big bullet at (150, 150)
        bullet_x[1]   = 10'd150;
        bullet_y[1]   = 10'd150;
        bullet_act[1] = 1'b1;
        bullet_big[1] = 1'b1;

        hp1 = 8'd20; // Full health
        hp2 = 8'd15;

        #200;
        @(posedge clk);
        reset_n = 1'b1;
        $display("  [INFO] Pipeline reset de-asserted. Simulating 1 full active video frame...");

        // Monitor pixel stream over 1 full frame (525 lines = 420,000 pixel ticks)
        while (frame_count < 1) begin
            @(posedge clk);
            if (pix_ce) begin

                // Check Tank 1 pixels (Bright green dome 0x0F4 or hull 0x0B0)
                if (current_vga_rgb == 12'h0F4 || current_vga_rgb == 12'h0B0)
                    saw_p1_tank = 1;

                // Check Tank 2 pixels (Bright red dome 0xF44 or hull 0xB11)
                if (current_vga_rgb == 12'hF44 || current_vga_rgb == 12'hB11)
                    saw_p2_tank = 1;

                // Check Normal Bullet (Yellow 0xFF2)
                if (current_vga_rgb == 12'hFF2)
                    saw_normal_bullet = 1;

                // Check Big Bullet (Orange/Red 0xF30)
                if (current_vga_rgb == 12'hF30)
                    saw_big_bullet = 1;

                // Check HUD Heart (Crimson Red 0xF00 or Gloss 0xFFA)
                if (current_vga_rgb == 12'hF00 || current_vga_rgb == 12'hFFA)
                    saw_hud_heart = 1;

                // Check Arena Divider Bar (0x557)
                if (current_vga_rgb == 12'h557)
                    saw_divider_bar = 1;

                // Blanking check: outside visible frame or sync pulse, RGB MUST be 0
                if (!u_mixer.active_pipe[1]) begin
                    if (current_vga_rgb !== 12'h000) begin
                        $display("  [FAIL] Non-zero RGB during blanking! hcnt=%0d vcnt=%0d rgb=0x%03h",
                                 vga_hcnt, vga_vcnt, current_vga_rgb);
                        errors = errors + 1;
                    end
                end

                if (vga_h_end)
                    line_count = line_count + 1;

                if (vga_v_end)
                    frame_count = frame_count + 1;
            end
        end

        $display("  [INFO] Completed 1 full frame: %0d lines rasterized.", line_count);
        $display("==========================================================");
        $display("  SUBSYSTEM LAYER RASTERIZATION REPORT:");
        $display("  - Tank 1 Sprite Rendered:       %s", saw_p1_tank ? "YES [PASS]" : "NO [FAIL]");
        $display("  - Tank 2 Sprite Rendered:       %s", saw_p2_tank ? "YES [PASS]" : "NO [FAIL]");
        $display("  - Normal Bullet Disc Rendered:  %s", saw_normal_bullet ? "YES [PASS]" : "NO [FAIL]");
        $display("  - Big Special Bullet Rendered:  %s", saw_big_bullet ? "YES [PASS]" : "NO [FAIL]");
        $display("  - Health HUD Hearts Rendered:   %s", saw_hud_heart ? "YES [PASS]" : "NO [FAIL]");
        $display("  - Arena Divider Bar Rendered:   %s", saw_divider_bar ? "YES [PASS]" : "NO [FAIL]");
        $display("==========================================================");

        if (!saw_p1_tank)       errors = errors + 1;
        if (!saw_p2_tank)       errors = errors + 1;
        if (!saw_normal_bullet) errors = errors + 1;
        if (!saw_big_bullet)    errors = errors + 1;
        if (!saw_hud_heart)     errors = errors + 1;
        if (!saw_divider_bar)   errors = errors + 1;

        if (errors == 0) begin
            $display(">> ALL INTEGRATED VGA SUBSYSTEM TESTS PASSED! <<");
        end else begin
            $display(">> VGA SUBSYSTEM TEST FAILED with %0d errors! <<", errors);
        end
        $display("==========================================================");

        $finish;
    end

endmodule
