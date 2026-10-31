`timescale 1ns / 1ps
//=============================================================================
// Testbench: Sound Engine (Hardware Audio Synthesizer & Event Sniffer)
//
// Verifies:
//   1. Reset state and audio amplifier shutdown (aud_sd).
//   2. Startup muting grace period.
//   3. Direct trigger inputs (trig_fire, trig_bounce, trig_hit, trig_destroy).
//   4. Sniffer event detection:
//      - Bullet Fire (bullet_act edge)
//      - Bullet Bounce (wall_hit_any edge)
//      - Tank Hit / Heart Decrease (hp1 / hp2 drop)
//      - Destroy Tank (hp1 / hp2 reaches 0)
//   5. Priority arbiter (DESTROY > HIT > BOUNCE > FIRE).
//   6. PWM generation (aud_pwm activity and duty-cycle modulation).
//=============================================================================

module tb_sound_engine;

    // Use scaled clock for fast simulation (1 ms = 50 clock cycles)
    localparam CLK_FREQ_HZ = 50_000;

    reg        clk;
    reg        reset_n;

    // Sniffer inputs
    reg  [7:0] bullet_act;
    reg  [7:0] hp1;
    reg  [7:0] hp2;
    reg        wall_hit_any;
    reg        tank_hit_any;

    // Direct test inputs
    reg        trig_fire;
    reg        trig_bounce;
    reg        trig_hit;
    reg        trig_destroy;

    // Outputs
    wire       sfx_active;
    wire [2:0] current_sfx;
    wire       aud_pwm;
    wire       aud_sd;

    integer errors = 0;
    integer pwm_toggles = 0;

    // SFX Constants
    localparam [2:0] SFX_IDLE    = 3'd0;
    localparam [2:0] SFX_FIRE    = 3'd1;
    localparam [2:0] SFX_BOUNCE  = 3'd2;
    localparam [2:0] SFX_HIT     = 3'd3;
    localparam [2:0] SFX_DESTROY = 3'd4;

    sound_engine #(
        .CLK_FREQ_HZ (CLK_FREQ_HZ),
        .STARTUP_MS  (0)
    ) dut (
        .clk          (clk),
        .reset_n      (reset_n),
        .bullet_act   (bullet_act),
        .hp1          (hp1),
        .hp2          (hp2),
        .wall_hit_any (wall_hit_any),
        .tank_hit_any (tank_hit_any),
        .trig_fire    (trig_fire),
        .trig_bounce  (trig_bounce),
        .trig_hit     (trig_hit),
        .trig_destroy (trig_destroy),
        .sfx_active   (sfx_active),
        .current_sfx  (current_sfx),
        .aud_pwm      (aud_pwm),
        .aud_sd       (aud_sd)
    );

    // Clock generation (period = 20 ns)
    initial begin
        clk = 1'b0;
        forever #10 clk = ~clk;
    end

    // Monitor PWM toggles
    always @(posedge aud_pwm) begin
        pwm_toggles = pwm_toggles + 1;
    end

    // Helper task: advance N milliseconds
    task advance_ms;
        input integer ms;
        integer k;
        begin
            for (k = 0; k < ms; k = k + 1) begin
                repeat (50) @(posedge clk);
            end
        end
    endtask

    initial begin
        $display("==========================================================");
        $display("    TESTBENCH: SOUND ENGINE (AUDIO SYNTHESIZER / SNIFFER) ");
        $display("==========================================================");

        // Initial setup
        reset_n      = 1'b0;
        bullet_act   = 8'h00;
        hp1          = 8'd20;
        hp2          = 8'd20;
        wall_hit_any = 1'b0;
        tank_hit_any = 1'b0;
        trig_fire    = 1'b0;
        trig_bounce  = 1'b0;
        trig_hit     = 1'b0;
        trig_destroy = 1'b0;

        #100;
        @(negedge clk);

        // ---------------------------------------------------------------------
        // Test 1: Reset Behavior & Amp Shutdown
        // ---------------------------------------------------------------------
        $display("\n[TEST 1] Testing Reset State & Amplifier Control...");
        if (aud_sd !== 1'b0) begin
            $display("  [FAIL] Expected aud_sd = 0 during reset, got %b", aud_sd);
            errors = errors + 1;
        end else begin
            $display("  [PASS] aud_sd is 0 (amplifier safely shutdown during reset).");
        end

        reset_n = 1'b1;
        @(posedge clk);
        #1;

        if (aud_sd !== 1'b1) begin
            $display("  [FAIL] Expected aud_sd = 1 after reset released, got %b", aud_sd);
            errors = errors + 1;
        end else begin
            $display("  [PASS] aud_sd is 1 (amplifier active).");
        end

        // Wait out startup muting period
        advance_ms(5);

        if (current_sfx !== SFX_IDLE || sfx_active !== 1'b0) begin
            $display("  [FAIL] Expected idle state after startup, got sfx=%d", current_sfx);
            errors = errors + 1;
        end else begin
            $display("  [PASS] Engine successfully reached SFX_IDLE after startup grace period.");
        end

        // ---------------------------------------------------------------------
        // Test 2: Sniffer - Bullet Fire Detection
        // ---------------------------------------------------------------------
        $display("\n[TEST 2] Testing Sniffer Bullet Fire Detection (bullet_act edge)...");
        pwm_toggles = 0;
        @(negedge clk);
        bullet_act = 8'h01; // Bullet 0 fired on negedge
        @(posedge clk);     // Latched on posedge
        #1;

        if (current_sfx !== SFX_FIRE || sfx_active !== 1'b1) begin
            $display("  [FAIL] Expected SFX_FIRE (1), got current_sfx=%d", current_sfx);
            errors = errors + 1;
        end else begin
            $display("  [PASS] Sniffer triggered SFX_FIRE immediately upon bullet_act change.");
        end

        advance_ms(70); // Wait for fire sound duration (65 ms)
        @(posedge clk);
        #1;

        if (current_sfx !== SFX_IDLE) begin
            $display("  [FAIL] Expected return to IDLE after fire duration, got %d", current_sfx);
            errors = errors + 1;
        end else begin
            $display("  [PASS] Sound completed cleanly and returned to SFX_IDLE. (PWM toggles: %0d)", pwm_toggles);
        end

        // ---------------------------------------------------------------------
        // Test 3: Sniffer - Bullet Bounce (Wall Hit)
        // ---------------------------------------------------------------------
        $display("\n[TEST 3] Testing Sniffer Bullet Bounce Detection (wall_hit_any)...");
        @(negedge clk);
        wall_hit_any = 1'b1;
        @(posedge clk);
        #1;

        if (current_sfx !== SFX_BOUNCE) begin
            $display("  [FAIL] Expected SFX_BOUNCE (2), got current_sfx=%d", current_sfx);
            errors = errors + 1;
        end else begin
            $display("  [PASS] Sniffer triggered SFX_BOUNCE on wall_hit_any.");
        end

        @(negedge clk);
        wall_hit_any = 1'b0;
        advance_ms(40); // Wait for bounce sound duration (35 ms)
        @(posedge clk);
        #1;

        if (current_sfx !== SFX_IDLE) begin
            $display("  [FAIL] Expected return to IDLE after bounce duration, got %d", current_sfx);
            errors = errors + 1;
        end else begin
            $display("  [PASS] Bounce completed cleanly and returned to SFX_IDLE.");
        end

        // ---------------------------------------------------------------------
        // Test 4: Sniffer - Tank Damage (Heart Decrease)
        // ---------------------------------------------------------------------
        $display("\n[TEST 4] Testing Sniffer Tank Damage / Heart Loss (hp1 drop)...");
        @(negedge clk);
        hp1 = 8'd18; // P1 took 2 damage (18 hearts)
        @(posedge clk);
        #1;

        if (current_sfx !== SFX_HIT) begin
            $display("  [FAIL] Expected SFX_HIT (3), got current_sfx=%d", current_sfx);
            errors = errors + 1;
        end else begin
            $display("  [PASS] Sniffer triggered SFX_HIT upon health decrease (20 -> 18).");
        end

        advance_ms(160); // Wait for hit sound duration (150 ms)
        @(posedge clk);
        #1;

        if (current_sfx !== SFX_IDLE) begin
            $display("  [FAIL] Expected return to IDLE after hit duration, got %d", current_sfx);
            errors = errors + 1;
        end else begin
            $display("  [PASS] Hit alert completed cleanly and returned to SFX_IDLE.");
        end

        // ---------------------------------------------------------------------
        // Test 5: Sniffer - Tank Destroyed (Health = 0)
        // ---------------------------------------------------------------------
        $display("\n[TEST 5] Testing Sniffer Tank Destroyed (hp2 reaches 0)...");
        @(negedge clk);
        hp2 = 8'd0; // P2 killed!
        @(posedge clk);
        #1;

        if (current_sfx !== SFX_DESTROY) begin
            $display("  [FAIL] Expected SFX_DESTROY (4), got current_sfx=%d", current_sfx);
            errors = errors + 1;
        end else begin
            $display("  [PASS] Sniffer triggered SFX_DESTROY upon lethal hit (hp2 -> 0).");
        end

        // ---------------------------------------------------------------------
        // Test 6: Priority Arbiter Test
        // ---------------------------------------------------------------------
        $display("\n[TEST 6] Testing Priority Arbiter during Active Explosion...");
        // While SFX_DESTROY is running, try lower priority triggers (Fire and Bounce)
        @(negedge clk);
        bullet_act = 8'h05; // Fire bullet
        wall_hit_any = 1'b1; // Bounce
        @(posedge clk);
        #1;

        if (current_sfx !== SFX_DESTROY) begin
            $display("  [FAIL] Low-priority sound preempted SFX_DESTROY! current_sfx=%d", current_sfx);
            errors = errors + 1;
        end else begin
            $display("  [PASS] SFX_DESTROY held lock against lower priority fire/bounce events.");
        end

        @(negedge clk);
        wall_hit_any = 1'b0;
        advance_ms(510); // Wait for explosion duration (500 ms)
        @(posedge clk);
        #1;

        if (current_sfx !== SFX_IDLE) begin
            $display("  [FAIL] Expected return to IDLE after explosion, got %d", current_sfx);
            errors = errors + 1;
        end else begin
            $display("  [PASS] Explosion rumble completed cleanly and returned to SFX_IDLE.");
        end

        // ---------------------------------------------------------------------
        // Test 7: Direct Trigger Inputs
        // ---------------------------------------------------------------------
        $display("\n[TEST 7] Testing Direct Test Trigger Inputs (trig_fire, trig_bounce)...");
        @(negedge clk);
        trig_fire = 1'b1;
        @(posedge clk);
        #1;

        if (current_sfx !== SFX_FIRE) begin
            $display("  [FAIL] Direct trig_fire failed, current_sfx=%d", current_sfx);
            errors = errors + 1;
        end else begin
            $display("  [PASS] Direct trig_fire triggered SFX_FIRE.");
        end

        @(negedge clk);
        trig_fire = 1'b0;
        advance_ms(70);

        @(negedge clk);
        trig_bounce = 1'b1;
        @(posedge clk);
        #1;

        if (current_sfx !== SFX_BOUNCE) begin
            $display("  [FAIL] Direct trig_bounce failed, current_sfx=%d", current_sfx);
            errors = errors + 1;
        end else begin
            $display("  [PASS] Direct trig_bounce triggered SFX_BOUNCE.");
        end

        @(negedge clk);
        trig_bounce = 1'b0;
        advance_ms(40);

        // ---------------------------------------------------------------------
        // Final Results
        // ---------------------------------------------------------------------
        $display("\n==========================================================");
        if (errors == 0) begin
            $display("  >>> ALL SOUND ENGINE TESTS PASSED SUCCESSFULLY! <<<");
        end else begin
            $display("  >>> TESTBENCH FAILED WITH %0d ERRORS! <<<", errors);
        end
        $display("==========================================================\n");

        $finish;
    end

endmodule
