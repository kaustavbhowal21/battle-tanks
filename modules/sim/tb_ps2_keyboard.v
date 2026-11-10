`timescale 1ns / 1ps
//=============================================================================
// Testbench for PS/2 Keyboard Controller
// Verifies 11-bit framing, odd parity, scancode decoding, break codes,
// extended codes, and two-player multi-key rollover.
//=============================================================================
module tb_ps2_keyboard;

    reg clk;
    reg reset_n;
    reg ps2_clk;
    reg ps2_data;

    wire [5:0] p1_controls;
    wire [5:0] p2_controls;
    wire       esc_reset;
    wire [7:0] last_scancode;
    wire       key_event_strobe;
    wire       rx_err;

    // Use fast filter in simulation (FILTER_BITS=2 -> 4 clocks @ 50 MHz = 80 ns)
    ps2_keyboard_controller #(
        .CLK_FREQ_HZ(50_000_000),
        .FILTER_BITS (2)
    ) dut (
        .clk              (clk),
        .reset_n          (reset_n),
        .ps2_clk          (ps2_clk),
        .ps2_data         (ps2_data),
        .p1_controls      (p1_controls),
        .p2_controls      (p2_controls),
        .esc_reset        (esc_reset),
        .last_scancode    (last_scancode),
        .key_event_strobe (key_event_strobe),
        .rx_err           (rx_err)
    );

    // 50 MHz system clock (20 ns period)
    always #10 clk = ~clk;

    // Task: Transmit 1 byte via PS/2 protocol (11-bit frame)
    task send_ps2_byte(input [7:0] data);
        integer bit_idx;
        reg parity;
        begin
            parity = ~(^data); // Odd parity

            // 1. Start bit (0)
            ps2_data = 1'b0;
            #200; ps2_clk = 1'b0;
            #200; ps2_clk = 1'b1;

            // 2. 8 Data bits (LSB first)
            for (bit_idx = 0; bit_idx < 8; bit_idx = bit_idx + 1) begin
                ps2_data = data[bit_idx];
                #200; ps2_clk = 1'b0;
                #200; ps2_clk = 1'b1;
            end

            // 3. Parity bit
            ps2_data = parity;
            #200; ps2_clk = 1'b0;
            #200; ps2_clk = 1'b1;

            // 4. Stop bit (1)
            ps2_data = 1'b1;
            #200; ps2_clk = 1'b0;
            #200; ps2_clk = 1'b1;

            // Inter-byte gap
            #500;
        end
    endtask

    integer pass_count = 0;
    integer fail_count = 0;

    task check_condition(input [255:0] test_name, input condition);
        begin
            if (condition) begin
                $display("  [PASS] %0s", test_name);
                pass_count = pass_count + 1;
            end else begin
                $display("  [FAIL] %0s", test_name);
                fail_count = fail_count + 1;
            end
        end
    endtask

    initial begin
        $display("==========================================================");
        $display("  PS/2 KEYBOARD CONTROLLER: TESTBENCH VERIFICATION START  ");
        $display("==========================================================");

        clk      = 1'b0;
        reset_n  = 1'b0;
        ps2_clk  = 1'b1;
        ps2_data = 1'b1;

        #100;
        reset_n = 1'b1;
        #100;

        // ---------------------------------------------------------------------
        // Test 1: Player 1 Forward (W: 0x1D) Make Code
        // ---------------------------------------------------------------------
        $display("\n--- Test 1: P1 Press 'W' (Move Forward) ---");
        send_ps2_byte(8'h1D);
        #50;
        check_condition("P1 controls has FWD bit asserted (p1[0]==1)", p1_controls[0] == 1'b1);
        check_condition("P1 other buttons are low (p1==6'b000001)", p1_controls == 6'b000001);
        check_condition("Last scancode is 0x1D", last_scancode == 8'h1D);

        // ---------------------------------------------------------------------
        // Test 2: Player 1 Shoot (Space: 0x29) while holding 'W'
        // ---------------------------------------------------------------------
        $display("\n--- Test 2: P1 Press 'Space' (Shoot) while holding 'W' ---");
        send_ps2_byte(8'h29);
        #50;
        check_condition("Both FWD (p1[0]) and SHOOT (p1[4]) active (p1==6'b010001)", p1_controls == 6'b010001);

        // ---------------------------------------------------------------------
        // Test 3: Player 1 Turn Left (A: 0x1C) while holding 'W' and 'Space'
        // ---------------------------------------------------------------------
        $display("\n--- Test 3: P1 Press 'A' (Turn Left) simultaneously ---");
        send_ps2_byte(8'h1C);
        #50;
        check_condition("FWD, LEFT, and SHOOT active (p1==6'b010101)", p1_controls == 6'b010101);

        // ---------------------------------------------------------------------
        // Test 4: Player 1 Release 'W' (Break: F0 1D)
        // ---------------------------------------------------------------------
        $display("\n--- Test 4: P1 Release 'W' (F0 1D) ---");
        send_ps2_byte(8'hF0);
        send_ps2_byte(8'h1D);
        #50;
        check_condition("FWD released (p1[0]==0), LEFT and SHOOT still held (p1==6'b010100)", p1_controls == 6'b010100);

        // ---------------------------------------------------------------------
        // Test 5: Player 1 Release 'A' and 'Space'
        // ---------------------------------------------------------------------
        $display("\n--- Test 5: P1 Release 'A' and 'Space' ---");
        send_ps2_byte(8'hF0);
        send_ps2_byte(8'h1C);
        send_ps2_byte(8'hF0);
        send_ps2_byte(8'h29);
        #50;
        check_condition("All P1 controls released (p1==6'b000000)", p1_controls == 6'b000000);

        // ---------------------------------------------------------------------
        // Test 6: Player 2 Extended Key (Up Arrow: E0 75)
        // ---------------------------------------------------------------------
        $display("\n--- Test 6: P2 Press 'Up Arrow' (E0 75) ---");
        send_ps2_byte(8'hE0);
        send_ps2_byte(8'h75);
        #50;
        check_condition("P2 controls has FWD bit asserted (p2[0]==1)", p2_controls[0] == 1'b1);
        check_condition("P1 controls remain completely unaffected (p1==0)", p1_controls == 6'b000000);

        // ---------------------------------------------------------------------
        // Test 7: Player 2 Shoot (Enter: 0x5A)
        // ---------------------------------------------------------------------
        $display("\n--- Test 7: P2 Press 'Enter' (Shoot) ---");
        send_ps2_byte(8'h5A);
        #50;
        check_condition("P2 FWD and SHOOT active (p2==6'b010001)", p2_controls == 6'b010001);

        // ---------------------------------------------------------------------
        // Test 8: Player 2 Release 'Up Arrow' (Extended Break: E0 F0 75)
        // ---------------------------------------------------------------------
        $display("\n--- Test 8: P2 Release 'Up Arrow' (E0 F0 75) ---");
        send_ps2_byte(8'hE0);
        send_ps2_byte(8'hF0);
        send_ps2_byte(8'h75);
        #50;
        check_condition("P2 FWD cleared, SHOOT remains held (p2==6'b010000)", p2_controls == 6'b010000);

        // Release Enter
        send_ps2_byte(8'hF0);
        send_ps2_byte(8'h5A);
        #50;
        check_condition("P2 controls all clear (p2==6'b000000)", p2_controls == 6'b000000);

        // ---------------------------------------------------------------------
        // Test 9: Simultaneous Two-Player Gameplay
        // P1 moves Forward (W) & Special (E); P2 moves Backward (Down Arrow) & Shoots (Slash)
        // ---------------------------------------------------------------------
        $display("\n--- Test 9: Simultaneous Two-Player Action ---");
        send_ps2_byte(8'h1D); // P1 W (FWD)
        send_ps2_byte(8'h24); // P1 E (SPECIAL)
        send_ps2_byte(8'hE0); // P2 Down Arrow (BWD)
        send_ps2_byte(8'h72);
        send_ps2_byte(8'h4A); // P2 Slash (SHOOT)
        #50;
        check_condition("P1 has FWD and SPECIAL active (p1==6'b100001)", p1_controls == 6'b100001);
        check_condition("P2 has BWD and SHOOT active (p2==6'b010010)", p2_controls == 6'b010010);

        // Release all
        send_ps2_byte(8'hF0); send_ps2_byte(8'h1D);
        send_ps2_byte(8'hF0); send_ps2_byte(8'h24);
        send_ps2_byte(8'hE0); send_ps2_byte(8'hF0); send_ps2_byte(8'h72);
        send_ps2_byte(8'hF0); send_ps2_byte(8'h4A);
        #50;
        check_condition("Both players clear after release", (p1_controls == 6'b000000) && (p2_controls == 6'b000000));

        // ---------------------------------------------------------------------
        // Test 10: Player 2 Alternative Keys (IJKL + P)
        // ---------------------------------------------------------------------
        $display("\n--- Test 10: P2 Alternative Keys (I, K, J, L, P) ---");
        send_ps2_byte(8'h43); // I (FWD)
        send_ps2_byte(8'h3B); // J (LEFT)
        send_ps2_byte(8'h4D); // P (SPECIAL)
        #50;
        check_condition("P2 alternative keys active (FWD, LEFT, SPECIAL: p2==6'b100101)", p2_controls == 6'b100101);

        send_ps2_byte(8'hF0); send_ps2_byte(8'h43);
        send_ps2_byte(8'hF0); send_ps2_byte(8'h3B);
        send_ps2_byte(8'hF0); send_ps2_byte(8'h4D);
        #50;
        check_condition("P2 alternative keys released (p2==6'b000000)", p2_controls == 6'b000000);

        // ---------------------------------------------------------------------
        // Test 11: System Reset Key (ESC: 0x76)
        // ---------------------------------------------------------------------
        $display("\n--- Test 11: ESC Key (System Reset: 0x76) ---");
        send_ps2_byte(8'h76); // ESC make
        #50;
        check_condition("ESC pressed asserts esc_reset (esc_reset==1)", esc_reset == 1'b1);

        send_ps2_byte(8'hF0); send_ps2_byte(8'h76); // ESC break
        #50;
        check_condition("ESC released deasserts esc_reset (esc_reset==0)", esc_reset == 1'b0);

        // ---------------------------------------------------------------------
        // Final Summary
        // ---------------------------------------------------------------------
        $display("\n==========================================================");
        $display("  TEST RESULTS: %0d PASSED, %0d FAILED", pass_count, fail_count);
        $display("==========================================================");

        if (fail_count == 0)
            $display(">>> [PS2 KEYBOARD TEST PASSED] All assertions completed successfully! <<<\n");
        else
            $display(">>> [PS2 KEYBOARD TEST FAILED] One or more assertions failed! <<<\n");

        $finish;
    end

endmodule

