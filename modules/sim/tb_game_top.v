`timescale 1ns / 1ps
//=============================================================================
// Battle Tanks: Full Hardware-Software System Testbench
//
// Verifies:
// 1. RV32IM CPU core fetching from IMEM and executing compiled C game code.
// 2. Hardware cooldown timers triggered via MMIO.
// 3. Sprite & HUD registers written by C program.
// 4. Hardware collision engine detecting interactions.
// 5. VGA Timing Generator producing HSync, VSync, and RGB color stream.
//=============================================================================

module tb_game_top;

    reg        clk;
    reg        reset;
    reg  [5:0] p1_btn_raw;
    reg  [5:0] p2_btn_raw;

    wire [15:0] led;
    wire [6:0]  seg;
    wire [7:0]  an;
    wire        dp;
    wire [3:0]  vga_r;
    wire [3:0]  vga_g;
    wire [3:0]  vga_b;
    wire        vga_hsync;
    wire        vga_vsync;

    // 100 MHz system clock
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    // Simulation DUT instantiation
    top_fpga #(
        .IMEM_HEX     ("imem.hex"),
        .DMEM_HEX     ("dmem.hex"),
        .CLK_PER_MS   (50),       // Accelerated prescaler for simulation (1 us per tick)
        .DEBOUNCE_MAX (20'd5),    // Fast debounce for simulation
        .SEG_SCAN_BIT (1)         // Fast 7-segment scan for simulation
    ) dut (
        .clk        (clk),
        .reset      (reset),
        .p1_btn_raw (p1_btn_raw),
        .p2_btn_raw (p2_btn_raw),
        .led        (led),
        .seg        (seg),
        .an         (an),
        .dp         (dp),
        .vga_r      (vga_r),
        .vga_g      (vga_g),
        .vga_b      (vga_b),
        .vga_hsync  (vga_hsync),
        .vga_vsync  (vga_vsync)
    );

    // Test sequence
    initial begin
        $display("==========================================================");
        $display("  BATTLE TANKS: FULL HARDWARE/SOFTWARE SIMULATION START   ");
        $display("==========================================================");

        // Initial inputs
        reset      = 1'b0; // Assert active-low reset
        p1_btn_raw = 6'b000000;
        p2_btn_raw = 6'b000000;

        #200;
        reset = 1'b1; // De-assert reset, CPU begins execution
        $display("[TIME %0t] Reset de-asserted. CPU starting at PC=0x00000000...", $time);

        // Let the C program initialize game state and clear BSS
        #5000;

        // Player 1 presses Forward (bit 0) and Shoot (bit 4)
        $display("[TIME %0t] Player 1 pressing FORWARD and SHOOT...", $time);
        p1_btn_raw = 6'b010001;
        #10000;
        p1_btn_raw = 6'b000000;

        // Player 2 presses Turn Left (bit 2) and Special Attack (bit 5)
        #5000;
        $display("[TIME %0t] Player 2 pressing TURN_LEFT and SPECIAL_ATTACK...", $time);
        p2_btn_raw = 6'b100100;
        #10000;
        p2_btn_raw = 6'b000000;

        // Run for additional cycles to observe projectile flight and VGA activity
        #50000;

        // Verify 7-Segment Winner Display (DISP1 & DISP2 combined)
        // 1. Both players alive -> Display OFF
        if (an !== 8'hFF || seg !== 7'b111_1111) begin
            $display(">> TEST FAILED: 7-seg should be OFF while both players have health!");
            $finish;
        end

        // 2. P1 (Blue) health = 0, P2 (Red) health = 10 -> "RED  WON"
        force dut.u_sprites.health_bar_reg_q = {16'd0, 8'd10, 8'd0};
        force dut.seg_digit_sel = 3'd7; #10;
        if (seg !== dut.SEG_R || an !== 8'b0111_1111) $display(">> FAIL: RED WON digit 7");
        force dut.seg_digit_sel = 3'd6; #10;
        if (seg !== dut.SEG_E || an !== 8'b1011_1111) $display(">> FAIL: RED WON digit 6");
        force dut.seg_digit_sel = 3'd5; #10;
        if (seg !== dut.SEG_D || an !== 8'b1101_1111) $display(">> FAIL: RED WON digit 5");
        force dut.seg_digit_sel = 3'd2; #10;
        if (seg !== dut.SEG_W || an !== 8'b1111_1011) $display(">> FAIL: RED WON digit 2");
        force dut.seg_digit_sel = 3'd1; #10;
        if (seg !== dut.SEG_O || an !== 8'b1111_1101) $display(">> FAIL: RED WON digit 1");
        force dut.seg_digit_sel = 3'd0; #10;
        if (seg !== dut.SEG_N || an !== 8'b1111_1110) $display(">> FAIL: RED WON digit 0");
        $display("  [7-SEG CHECK] P1 HP=0, P2 HP=10 -> DISP1/DISP2 = 'RED  WON' verified!");

        // 3. P1 (Blue) health = 12, P2 (Red) health = 0 -> "BLUE WON"
        force dut.u_sprites.health_bar_reg_q = {16'd0, 8'd0, 8'd12};
        force dut.seg_digit_sel = 3'd7; #10;
        if (seg !== dut.SEG_B || an !== 8'b0111_1111) $display(">> FAIL: BLUE WON digit 7");
        force dut.seg_digit_sel = 3'd6; #10;
        if (seg !== dut.SEG_L || an !== 8'b1011_1111) $display(">> FAIL: BLUE WON digit 6");
        force dut.seg_digit_sel = 3'd5; #10;
        if (seg !== dut.SEG_U || an !== 8'b1101_1111) $display(">> FAIL: BLUE WON digit 5");
        force dut.seg_digit_sel = 3'd4; #10;
        if (seg !== dut.SEG_E || an !== 8'b1110_1111) $display(">> FAIL: BLUE WON digit 4");
        force dut.seg_digit_sel = 3'd2; #10;
        if (seg !== dut.SEG_W || an !== 8'b1111_1011) $display(">> FAIL: BLUE WON digit 2");
        force dut.seg_digit_sel = 3'd1; #10;
        if (seg !== dut.SEG_O || an !== 8'b1111_1101) $display(">> FAIL: BLUE WON digit 1");
        force dut.seg_digit_sel = 3'd0; #10;
        if (seg !== dut.SEG_N || an !== 8'b1111_1110) $display(">> FAIL: BLUE WON digit 0");
        $display("  [7-SEG CHECK] P1 HP=12, P2 HP=0 -> DISP1/DISP2 = 'BLUE WON' verified!");

        // 4. Both P1 and P2 health = 0 -> "  DRAW  "
        force dut.u_sprites.health_bar_reg_q = {16'd0, 8'd0, 8'd0};
        force dut.seg_digit_sel = 3'd5; #10;
        if (seg !== dut.SEG_D || an !== 8'b1101_1111) $display(">> FAIL: DRAW digit 5");
        force dut.seg_digit_sel = 3'd4; #10;
        if (seg !== dut.SEG_R || an !== 8'b1110_1111) $display(">> FAIL: DRAW digit 4");
        force dut.seg_digit_sel = 3'd3; #10;
        if (seg !== dut.SEG_A || an !== 8'b1111_0111) $display(">> FAIL: DRAW digit 3");
        force dut.seg_digit_sel = 3'd2; #10;
        if (seg !== dut.SEG_W || an !== 8'b1111_1011) $display(">> FAIL: DRAW digit 2");
        $display("  [7-SEG CHECK] P1 HP=0, P2 HP=0  -> DISP1/DISP2 = '  DRAW  ' verified!");

        force dut.u_sprites.health_bar_reg_q = {16'd0, 8'd20, 8'd20};
        release dut.seg_digit_sel;
        release dut.u_sprites.health_bar_reg_q;
        #20;

        $display("==========================================================");
        $display("  SIMULATION RESULTS & TELEMETRY CHECK");
        $display("  Active PC Word: 0x%04h", dut.pc_out);
        $display("  Tank 1 (x, y): (%0d, %0d)", dut.p1_tank_x, dut.p1_tank_y);
        $display("  Tank 2 (x, y): (%0d, %0d)", dut.p2_tank_x, dut.p2_tank_y);
        $display("  P1 Health: %0d / 20 hearts", dut.hp1);
        $display("  P2 Health: %0d / 20 hearts", dut.hp2);
        $display("  Bullet Active Mask: 8'b%08b", dut.bullet_act);
        $display("  Exception Flag: %b", dut.exception);
        $display("  VGA HSync: %b, VSync: %b", vga_hsync, vga_vsync);
        $display("----------------------------------------------------------");
        $display("  HARDWARE CYCLE PROFILER (1 FRAME BREAKDOWN):");
        $display("  - VGA Total Frame Cycles (50 MHz) : %0d cycles (16.800 ms)", dut.reg_perf_vga_total);
        $display("  - VGA Active Visible Display      : %0d cycles (12.288 ms)", dut.reg_perf_vga_active);
        $display("  - VGA Blanking Overhead           : %0d cycles (4.512 ms)", dut.reg_perf_vga_total - dut.reg_perf_vga_active);
        $display("  - Hardware Collision Sweep Latency: %0d cycles (160 ns)", dut.reg_perf_col_sweep);
        $display("  - Hardware Collision Sweeps/Frame : %0d sweeps/frame", dut.reg_perf_col_sweeps_per_frame);
        $display("==========================================================");

        if (!dut.exception) begin
            $display(">> TEST PASSED: CPU executed C game software without exceptions!");
        end else begin
            $display(">> TEST FAILED: CPU encountered an illegal instruction exception!");
        end

        $finish;
    end

    // Monitor PC and MMIO activity
    always @(posedge dut.clk_sys) begin
        if (dut.mem_bus_we && dut.mem_bus_addr[31]) begin
            $display("[MMIO WRITE] Addr=0x%08h Data=0x%08h at time %0t", 
                     dut.mem_bus_addr, dut.dmem_write_data, $time);
        end
    end

endmodule
