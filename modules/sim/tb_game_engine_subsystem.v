`timescale 1ns / 1ps
//=============================================================================
// Testbench: Full Integrated Game Engine Subsystem Verification
// Instantiates and interconnects all 6 game engine modules:
// 1. mmio_interconnect
// 2. input_controller
// 3. cooldown_timers
// 4. sprite_hud_regfile
// 5. maze_tile_ram
// 6. collision_engine
//
// Simulates realistic CPU MMIO transactions and verifies hardware responses.
//=============================================================================

module tb_game_engine_subsystem;

    reg clk;
    reg reset_n;

    // CPU Memory Bus
    reg  [31:0] cpu_addr;
    reg  [31:0] cpu_wdata;
    reg  [3:0]  cpu_wstrb;
    reg         cpu_we;
    reg         cpu_re;
    wire [31:0] cpu_rdata;

    // External button pins
    reg  [5:0] p1_btn_raw;
    reg  [5:0] p2_btn_raw;

    // Interconnect wires
    wire [31:0] rd_dmem = 32'h0;
    wire [31:0] rd_in;
    wire [31:0] rd_tmr;
    wire [31:0] rd_col;
    wire [31:0] rd_maze;

    wire        cs_dmem;
    wire [3:0]  dmem_we;
    wire        cs_in;
    wire        cs_tmr;
    wire        wr_en_tmr;
    wire        cs_col;
    wire        wr_en_col;
    wire        cs_spr;
    wire        wr_en_spr;
    wire        cs_maze;
    wire        wr_en_maze;

    // Peripherals internal wiring
    wire [5:0] p1_btn_stable, p2_btn_stable;
    wire [9:0] p1_tank_x, p1_tank_y;
    wire [9:0] p2_tank_x, p2_tank_y;
    wire [9:0] bullet_x   [0:7];
    wire [9:0] bullet_y   [0:7];
    wire [7:0] bullet_act;
    wire [7:0] bullet_big;
    wire [7:0] hp1, hp2;
    wire [3:0] tank_ang1, tank_ang2;

    wire [8:0] col_tile_addr;
    wire [1:0] col_tile_data;
    wire [8:0] vga_tile_addr = 9'd0;
    wire [1:0] vga_tile_data;

    integer errors = 0;

    // =========================================================================
    // Module Instantiations
    // =========================================================================
    mmio_interconnect u_mmio (
        .clk        (clk),
        .reset_n    (reset_n),
        .d_addr     (cpu_addr),
        .d_raddr    (cpu_addr),
        .d_wdata    (cpu_wdata),
        .d_wstrb    (cpu_wstrb),
        .d_we       (cpu_we),
        .d_re       (cpu_re),
        .d_rdata    (cpu_rdata),
        .rd_dmem    (rd_dmem),
        .rd_in      (rd_in),
        .rd_tmr     (rd_tmr),
        .rd_col     (rd_col),
        .rd_maze    (rd_maze),
        .cs_dmem    (cs_dmem),
        .dmem_we    (dmem_we),
        .cs_in      (cs_in),
        .cs_tmr     (cs_tmr),
        .wr_en_tmr  (wr_en_tmr),
        .cs_col     (cs_col),
        .wr_en_col  (wr_en_col),
        .cs_spr     (cs_spr),
        .wr_en_spr  (wr_en_spr),
        .cs_maze    (cs_maze),
        .wr_en_maze (wr_en_maze)
    );

    input_controller #(.DEBOUNCE_MAX(20'd5), .MIN_HOLD(21'd0)) u_input (
        .clk           (clk),
        .reset_n       (reset_n),
        .p1_btn_raw    (p1_btn_raw),
        .p2_btn_raw    (p2_btn_raw),
        .d_addr        (cpu_addr),
        .rd_in         (rd_in),
        .p1_btn_stable (p1_btn_stable),
        .p2_btn_stable (p2_btn_stable)
    );

    cooldown_timers #(.CLK_PER_MS(10)) u_timers (
        .clk       (clk),
        .reset_n   (reset_n),
        .wr_en_tmr (wr_en_tmr),
        .d_addr    (cpu_addr),
        .d_wdata   (cpu_wdata),
        .rd_tmr    (rd_tmr)
    );

    sprite_hud_regfile u_sprites (
        .clk        (clk),
        .reset_n    (reset_n),
        .wr_en_spr  (wr_en_spr),
        .d_addr     (cpu_addr),
        .d_wdata    (cpu_wdata),
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

    maze_tile_ram u_maze (
        .clk           (clk),
        .reset_n       (reset_n),
        .wr_en_maze    (wr_en_maze),
        .d_addr        (cpu_addr),
        .d_raddr       (cpu_addr),
        .d_wdata       (cpu_wdata),
        .rd_maze       (rd_maze),
        .vga_tile_addr (vga_tile_addr),
        .vga_tile_data (vga_tile_data),
        .col_tile_addr (col_tile_addr),
        .col_tile_data (col_tile_data)
    );

    collision_engine u_collision (
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
        .maze_c_addr (col_tile_addr),
        .maze_c_data (col_tile_data),
        .wr_en_col   (wr_en_col),
        .d_addr      (cpu_addr),
        .d_raddr     (cpu_addr),
        .d_wdata     (cpu_wdata),
        .rd_col      (rd_col)
    );

    // 50 MHz clock
    initial begin
        clk = 1'b0;
        forever #10 clk = ~clk;
    end

    // Task for simulated CPU bus write
    task cpu_write;
        input [31:0] addr;
        input [31:0] data;
        begin
            @(posedge clk);
            cpu_addr  <= addr;
            cpu_wdata <= data;
            cpu_wstrb <= 4'b1111;
            cpu_we    <= 1'b1;
            cpu_re    <= 1'b0;
            @(posedge clk);
            cpu_we    <= 1'b0;
        end
    endtask

    // Task for simulated CPU bus read
    task cpu_read;
        input  [31:0] addr;
        output [31:0] data;
        begin
            @(posedge clk);
            cpu_addr  <= addr;
            cpu_we    <= 1'b0;
            cpu_re    <= 1'b1;
            @(posedge clk); // Pipeline register in mmio_interconnect
            #5;
            data = cpu_rdata;
            cpu_re    <= 1'b0;
        end
    endtask

    reg [31:0] read_val;

    initial begin
        $display("==========================================================");
        $display("   TESTBENCH: FULL INTEGRATED GAME ENGINE SUBSYSTEM       ");
        $display("==========================================================");

        reset_n = 1'b0;
        cpu_addr = 32'd0;
        cpu_wdata = 32'd0;
        cpu_wstrb = 4'd0;
        cpu_we = 1'b0;
        cpu_re = 1'b0;
        p1_btn_raw = 6'b000000;
        p2_btn_raw = 6'b000000;

        #100;
        @(posedge clk);
        reset_n = 1'b1;
        @(posedge clk);

        // =====================================================================
        // Step 1: Read Debounced Controllers
        // =====================================================================
        $display("  [STEP 1] Testing Controller Input Reading via MMIO...");
        p1_btn_raw = 6'b010001; // Forward + Shoot
        repeat(10) @(posedge clk);

        cpu_read(32'h8000_0000, read_val);
        if (read_val[5:0] !== 6'b010001) begin
            $display("  [FAIL] P1 keys MMIO read failed! Got 0x%08h", read_val);
            errors = errors + 1;
        end else begin
            $display("  [PASS] P1 keys cleanly read via MMIO: 0x%08h", read_val);
        end

        // =====================================================================
        // Step 2: Trigger Weapon Cooldown Timers
        // =====================================================================
        $display("  [STEP 2] Testing Weapon Firing & Cooldown via MMIO...");
        // Check initial timer status (0x8000_0010)
        cpu_read(32'h8000_0010, read_val);
        if (read_val[3:0] !== 4'b1111) begin
            $display("  [FAIL] Initial timer status failed! Got 0x%08h", read_val);
            errors = errors + 1;
        end

        // Trigger P1 Shoot (bit 0 = 1) at 0x8000_0014
        cpu_write(32'h8000_0014, 32'h0000_0001);

        // Verify status reflects busy (bit 0 = 0)
        cpu_read(32'h8000_0010, read_val);
        if (read_val[0] !== 1'b0) begin
            $display("  [FAIL] P1 shoot timer failed to enter cooldown!");
            errors = errors + 1;
        end else begin
            $display("  [PASS] P1 shoot cooldown active (Timer status: 0x%08h).", read_val);
        end

        // =====================================================================
        // Step 3: Update Sprite Regfile and Spawn Bullet on Tank 2
        // =====================================================================
        $display("  [STEP 3] Updating Sprites and Detecting Hardware Tank Hit...");
        // Tank 2 is at (400, 350)
        // Spawn active bullet 0 directly inside Tank 2 at (405, 355)
        // Bullet 0 format: {10'd0, is_big=0, act=1, y=355, x=405}
        cpu_write(32'h8000_0048, {10'd0, 1'b0, 1'b1, 10'd355, 10'd405});

        // Run 2 cycles for collision engine to evaluate overlap
        repeat(2) @(posedge clk);

        // Read Collision Hit register 0x8000_002C
        // Tank 2 hit is bit 9, Bullet 0 hit is bit 0 -> (1<<9)|1 = 0x0201
        cpu_read(32'h8000_002C, read_val);
        if ((read_val & 32'h0000_0201) !== 32'h0000_0201) begin
            $display("  [FAIL] Collision engine failed to detect bullet hitting Tank 2! Got 0x%08h", read_val);
            errors = errors + 1;
        end else begin
            $display("  [PASS] Hardware collision engine flagged Tank 2 hit: 0x%08h", read_val);
        end

        // Deactivate bullet in regfile (as real software does upon damage!)
        cpu_write(32'h8000_0048, 32'd0);

        // Clear collision flag with W1C write to 0x8000_002C
        cpu_write(32'h8000_002C, 32'h0000_0201);
        cpu_read(32'h8000_002C, read_val);
        if ((read_val & 32'h0000_0201) !== 32'h0) begin
            $display("  [FAIL] W1C clear failed! Got 0x%08h", read_val);
            errors = errors + 1;
        end else begin
            $display("  [PASS] Collision register cleared via MMIO W1C handshake.");
        end

        // =====================================================================
        // Step 4: Shatter Maze Brick in Mirrored BRAM
        // =====================================================================
        $display("  [STEP 4] Shattering Brick in Mirrored Maze RAM via MMIO...");
        // Write TILE_EMPTY (0) to tile (10, 10) -> index 10*20+10 = 210
        // Address: 0x8000_0100 + (210 << 2) = 0x8000_0100 + 0x348 = 0x8000_0448
        cpu_write(32'h8000_0100 + (210 << 2), 32'h0000_0000);

        // Read back from CPU port
        cpu_read(32'h8000_0100 + (210 << 2), read_val);
        if (read_val[1:0] !== 2'b00) begin
            $display("  [FAIL] Maze RAM write failed! Got 0x%08h", read_val);
            errors = errors + 1;
        end else begin
            $display("  [PASS] Mirrored maze tile shattered cleanly in BRAM.");
        end

        $display("==========================================================");
        if (errors == 0) begin
            $display(">> ALL INTEGRATED GAME ENGINE SUBSYSTEM TESTS PASSED! <<");
        end else begin
            $display(">> GAME ENGINE SUBSYSTEM TEST FAILED with %0d errors! <<", errors);
        end
        $display("==========================================================");

        $finish;
    end

endmodule
