`timescale 1ns / 1ps
//=============================================================================
// Testbench: VGA Timing Generator (640x480 @ 60 Hz)
// Verifies:
// 1. Pixel coordinate generation (x=0..639, y=0..479).
// 2. Horizontal timing: front porch (16), sync (96), back porch (48) = 800 total.
// 3. Vertical timing: front porch (10), sync (2), back porch (33) = 525 total.
// 4. Strobes: h_end, v_end, frame_tick.
// 5. Active signal assertions and active-low sync polarities.
// 6. Reset behavior.
//=============================================================================

module tb_vga_timing_gen;

    reg clk;
    reg reset_n;
    reg pix_ce;

    wire [9:0] x;
    wire [9:0] y;
    wire [9:0] hcnt;
    wire [9:0] vcnt;
    wire       hsync_n;
    wire       vsync_n;
    wire       active;
    wire       h_end;
    wire       v_end;
    wire       frame_tick;

    integer errors = 0;
    integer lines_counted = 0;
    integer frames_counted = 0;
    integer active_pixels_in_line = 0;
    integer hsync_pixels_in_line = 0;
    integer vsync_lines_in_frame = 0;

    vga_timing_gen dut (
        .clk        (clk),
        .reset_n    (reset_n),
        .pix_ce     (pix_ce),
        .x          (x),
        .y          (y),
        .hcnt       (hcnt),
        .vcnt       (vcnt),
        .hsync_n    (hsync_n),
        .vsync_n    (vsync_n),
        .active     (active),
        .h_end      (h_end),
        .v_end      (v_end),
        .frame_tick (frame_tick)
    );

    // 50 MHz clock
    initial begin
        clk = 1'b0;
        forever #10 clk = ~clk; // 20 ns period = 50 MHz
    end

    // 25 MHz pix_ce: toggles every 2nd clock cycle
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

    // Test sequence
    initial begin
        $display("==========================================================");
        $display("   TESTBENCH: VGA TIMING GENERATOR VERIFICATION           ");
        $display("==========================================================");

        // Reset check
        reset_n = 1'b0;
        #100;
        @(posedge clk);
        if (hcnt !== 10'd0 || vcnt !== 10'd0 || hsync_n !== 1'b1 || vsync_n !== 1'b1 || active !== 1'b0) begin
            $display("  [FAIL] Reset values incorrect!");
            errors = errors + 1;
        end else begin
            $display("  [PASS] Async reset correctly cleared all registers.");
        end

        // De-assert reset
        @(posedge clk);
        reset_n = 1'b1;
        $display("  [INFO] Running simulation for 2 complete VGA frames (800x525x2 ticks)...");

        // Track 2 full frames
        while (frames_counted < 2) begin
            @(posedge clk);
            if (pix_ce) begin
                // Check coordinate mapping during active display
                if (active) begin
                    if (x !== hcnt || y !== vcnt) begin
                        $display("  [FAIL] Active pixel coord mismatch at hcnt=%0d vcnt=%0d (x=%0d, y=%0d)",
                                 hcnt, vcnt, x, y);
                        errors = errors + 1;
                    end
                    active_pixels_in_line = active_pixels_in_line + 1;
                end else begin
                    if (hcnt >= 640 && x !== 10'd0) begin
                        $display("  [FAIL] Inactive X coordinate should be zero! (x=%0d)", x);
                        errors = errors + 1;
                    end
                    if (vcnt >= 480 && y !== 10'd0) begin
                        $display("  [FAIL] Inactive Y coordinate should be zero! (y=%0d)", y);
                        errors = errors + 1;
                    end
                end

                if (errors > 20) begin
                    $display("  [FATAL] Error threshold exceeded, terminating early.");
                    $finish;
                end

                // Track HSYNC pulse length
                if (!hsync_n) begin
                    hsync_pixels_in_line = hsync_pixels_in_line + 1;
                end

                // Check h_end strobe
                if (h_end) begin
                    if (hcnt !== 10'd799) begin
                        $display("  [FAIL] h_end asserted when hcnt != 799 (hcnt=%0d)", hcnt);
                        errors = errors + 1;
                    end

                    // Check active pixel count per visible line.
                    // The first line after reset is partial: pixel (0,0) is spent
                    // in reset (outputs blanked, active=0), so skip that one line.
                    if (lines_counted == 0) begin
                        // partial line after reset release - not checked
                    end else if (vcnt < 480) begin
                        if (active_pixels_in_line !== 640) begin
                            $display("  [FAIL] Expected 640 active pixels on visible line %0d, got %0d",
                                     vcnt, active_pixels_in_line);
                            errors = errors + 1;
                        end
                    end else begin
                        if (active_pixels_in_line !== 0) begin
                            $display("  [FAIL] Expected 0 active pixels on blanking line %0d, got %0d",
                                     vcnt, active_pixels_in_line);
                            errors = errors + 1;
                        end
                    end
                    active_pixels_in_line = 0;

                    // Check HSYNC pulse width
                    if (hsync_pixels_in_line !== 96) begin
                        $display("  [FAIL] Expected HSYNC width 96 pixels on line %0d, got %0d",
                                 vcnt, hsync_pixels_in_line);
                        errors = errors + 1;
                    end
                    hsync_pixels_in_line = 0;

                    // Track VSYNC lines
                    if (!vsync_n)
                        vsync_lines_in_frame = vsync_lines_in_frame + 1;

                    // Check frame tick
                    if (frame_tick && vcnt !== 10'd480) begin
                        $display("  [FAIL] frame_tick asserted at wrong vcnt=%0d (expected 480)", vcnt);
                        errors = errors + 1;
                    end

                    lines_counted = lines_counted + 1;
                end

                // Check v_end strobe
                if (v_end) begin
                    if (vcnt !== 10'd524 || hcnt !== 10'd799) begin
                        $display("  [FAIL] v_end asserted at wrong position! hcnt=%0d vcnt=%0d", hcnt, vcnt);
                        errors = errors + 1;
                    end

                    // Check VSYNC duration: exactly 2 lines (vcnt=490, 491)
                    if (vsync_lines_in_frame !== 2) begin
                        $display("  [FAIL] Expected VSYNC width 2 lines, got %0d", vsync_lines_in_frame);
                        errors = errors + 1;
                    end
                    vsync_lines_in_frame = 0;

                    frames_counted = frames_counted + 1;
                    $display("  [INFO] Completed Frame %0d (525 lines, 420,000 pixels simulated)", frames_counted);
                end
            end
        end

        $display("==========================================================");
        if (errors == 0) begin
            $display(">> TEST PASSED: VGA Timing Generator verified with 0 errors!");
        end else begin
            $display(">> TEST FAILED with %0d errors!", errors);
        end
        $display("==========================================================");

        $finish;
    end

endmodule
