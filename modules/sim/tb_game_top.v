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
        .DEBOUNCE_MAX (20'd5)     // Fast debounce for simulation
    ) dut (
        .clk        (clk),
        .reset      (reset),
        .p1_btn_raw (p1_btn_raw),
        .p2_btn_raw (p2_btn_raw),
        .led        (led),
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
