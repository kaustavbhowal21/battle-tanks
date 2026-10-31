`timescale 1ns / 1ps
//=============================================================================
// Sound Engine (Hardware Audio Synthesizer & Event Sniffer)
//
// Synthesizes retro sound effects for Battle Tanks:
//   1. Bullet Fire: Downward frequency sweep square wave (pew-pew).
//   2. Bullet Bounce: High-frequency metallic chirp (pip/tink).
//   3. Tank Damage / Heart Loss: Two-tone dissonant alert tone.
//   4. Destroy Tank: Heavy decaying LFSR rumble explosion (KABOOM).
//
// Operating Modes:
//   - Autonomous Event Sniffer: Passively observes bullet_act, hp1, hp2,
//     and collision signals from existing hardware modules (Zero CPU overhead).
//   - Direct Trigger Inputs: trig_fire, trig_bounce, trig_hit, trig_destroy
//     for simulation, testbenches, or manual hardware triggers.
//
// Audio Output:
//   - 8-bit digital sample mixed from Tone Generator and Noise Generator.
//   - Converted to 1-bit high-frequency PWM (Pin A11) for Nexys A7 audio jack.
//   - Drives aud_sd (Pin D12) HIGH to enable the onboard mono audio amplifier.
//=============================================================================
`ifndef SOUND_ENGINE_V
`define SOUND_ENGINE_V

module sound_engine #(
    parameter CLK_FREQ_HZ = 50_000_000, // 50 MHz clk_sys
    parameter STARTUP_MS  = 20          // Grace period in ms after reset
)(
    input  wire        clk,
    input  wire        reset_n,

    // -------------------------------------------------------------------------
    // Hardware Event Sniffer Inputs (Existing Wires in top_fpga.v)
    // -------------------------------------------------------------------------
    input  wire [7:0]  bullet_act,     // from sprite_hud_regfile
    input  wire [7:0]  hp1,            // from sprite_hud_regfile (0..20)
    input  wire [7:0]  hp2,            // from sprite_hud_regfile (0..20)
    input  wire        wall_hit_any,   // from collision_engine (u_collision.wall_any)
    input  wire        tank_hit_any,   // from collision_engine (u_collision.tank_hit_any)

    // -------------------------------------------------------------------------
    // Direct / Test Trigger Inputs (Optional / Testbench)
    // -------------------------------------------------------------------------
    input  wire        trig_fire,
    input  wire        trig_bounce,
    input  wire        trig_hit,
    input  wire        trig_destroy,

    // -------------------------------------------------------------------------
    // Status Telemetry (Optional for LEDs / Debug)
    // -------------------------------------------------------------------------
    output wire        sfx_active,
    output reg  [2:0]  current_sfx,    // 0=IDLE, 1=FIRE, 2=BOUNCE, 3=HIT, 4=DESTROY

    // -------------------------------------------------------------------------
    // Physical Audio Pins (Nexys A7 Mono Audio Jack J8)
    // -------------------------------------------------------------------------
    output wire        aud_pwm,        // Pin A11 (PWM audio stream)
    output wire        aud_sd          // Pin D12 (Audio amplifier shutdown, active-low)
);

    // =========================================================================
    // SFX Identifier Constants & Priorities
    // =========================================================================
    localparam [2:0] SFX_IDLE    = 3'd0;
    localparam [2:0] SFX_FIRE    = 3'd1;
    localparam [2:0] SFX_BOUNCE  = 3'd2;
    localparam [2:0] SFX_HIT     = 3'd3;
    localparam [2:0] SFX_DESTROY = 3'd4;

    // =========================================================================
    // 1. Millisecond Timebase Generator (1 ms Tick)
    // 50 MHz / 50,000 = 1,000 Hz (1 ms)
    // =========================================================================
    localparam CLKS_PER_MS = CLK_FREQ_HZ / 1000;
    reg [15:0] ms_clk_cnt;
    reg        tick_1ms;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            ms_clk_cnt <= 16'd0;
            tick_1ms   <= 1'b0;
        end else begin
            if (ms_clk_cnt >= (CLKS_PER_MS - 1)) begin
                ms_clk_cnt <= 16'd0;
                tick_1ms   <= 1'b1;
            end else begin
                ms_clk_cnt <= ms_clk_cnt + 16'd1;
                tick_1ms   <= 1'b0;
            end
        end
    end

    // Startup muting: avoid spurious triggers while system boots
    reg [7:0] startup_cnt;
    wire startup_done = (STARTUP_MS == 0) || (startup_cnt >= STARTUP_MS);

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n)
            startup_cnt <= 8'd0;
        else if (tick_1ms && !startup_done)
            startup_cnt <= startup_cnt + 8'd1;
    end

    // =========================================================================
    // 2. Hardware Sniffer Transition Detectors
    // =========================================================================
    reg [7:0] prev_bullet_act;
    reg [7:0] prev_hp1, prev_hp2;
    reg       prev_wall_hit;
    reg       prev_tank_hit;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            prev_bullet_act <= 8'd0;
            prev_hp1        <= 8'd20;
            prev_hp2        <= 8'd20;
            prev_wall_hit   <= 1'b0;
            prev_tank_hit   <= 1'b0;
        end else begin
            prev_bullet_act <= bullet_act;
            prev_hp1        <= hp1;
            prev_hp2        <= hp2;
            prev_wall_hit   <= wall_hit_any;
            prev_tank_hit   <= tank_hit_any;
        end
    end

    // Sniffer Events:
    // Bullet Fire: any bit 0 -> 1 in bullet_act
    wire sniffer_fire = startup_done && (|(bullet_act & ~prev_bullet_act));

    // Bullet Bounce: wall collision strobe
    wire sniffer_bounce = startup_done && (wall_hit_any && !prev_wall_hit);

    // Tank Death: either tank HP drops to 0
    wire p1_died = (hp1 == 8'd0) && (prev_hp1 > 8'd0);
    wire p2_died = (hp2 == 8'd0) && (prev_hp2 > 8'd0);
    wire sniffer_destroy = startup_done && (p1_died || p2_died);

    // Tank Damage: HP decreased while still alive
    wire p1_damaged = (hp1 < prev_hp1) && (hp1 > 8'd0);
    wire p2_damaged = (hp2 < prev_hp2) && (hp2 > 8'd0);
    wire sniffer_hit = startup_done && (p1_damaged || p2_damaged ||
                                       (tank_hit_any && !prev_tank_hit && !sniffer_destroy));

    // Consolidated Triggers (Sniffer OR Direct Test Inputs):
    wire evt_destroy = trig_destroy || sniffer_destroy;
    wire evt_hit     = trig_hit     || sniffer_hit;
    wire evt_bounce  = trig_bounce  || sniffer_bounce;
    wire evt_fire    = trig_fire    || sniffer_fire;

    // =========================================================================
    // 3. Sound Effect State & Parameter Machine
    // Duration in ms, starting pitch divisor, sweep rates, volume decay
    // =========================================================================
    reg [9:0]  sfx_timer_ms;      // Countdown in ms (up to 1023 ms)
    reg [18:0] tone_div;          // 50MHz / (2 * freq)
    reg [18:0] tone_sweep_step;   // amount added/subtracted to tone_div
    reg        sweep_dir;         // 1 = pitch drops (div increases), 0 = pitch rises
    reg [7:0]  tone_volume;       // 0..127 amplitude
    reg [7:0]  noise_volume;      // 0..127 amplitude
    reg [7:0]  noise_prescale;    // noise clock rate selector

    assign sfx_active = (current_sfx != SFX_IDLE);

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            current_sfx     <= SFX_IDLE;
            sfx_timer_ms    <= 10'd0;
            tone_div        <= 19'd0;
            tone_sweep_step <= 19'd0;
            sweep_dir       <= 1'b0;
            tone_volume     <= 8'd0;
            noise_volume    <= 8'd0;
            noise_prescale  <= 8'd0;
        end else begin
            // -----------------------------------------------------------------
            // Priority Arbiter: DESTROY > HIT > BOUNCE > FIRE
            // -----------------------------------------------------------------
            if (evt_destroy) begin
                // Explosion: 500 ms long, loud low-frequency noise rumble + bass thud
                current_sfx     <= SFX_DESTROY;
                sfx_timer_ms    <= 10'd500;
                tone_div        <= 19'd350_000; // ~70 Hz sub-bass rumble
                tone_sweep_step <= 19'd300;
                sweep_dir       <= 1'b1;
                tone_volume     <= 8'd45;
                noise_volume    <= 8'd80;       // dominant heavy noise
                noise_prescale  <= 8'd120;      // low rumble clock
            end
            else if (evt_hit && (current_sfx != SFX_DESTROY)) begin
                // Tank Hit: 150 ms two-tone dissonant alert + crunch
                current_sfx     <= SFX_HIT;
                sfx_timer_ms    <= 10'd150;
                tone_div        <= 19'd50_000;  // 500 Hz
                tone_sweep_step <= 19'd250;
                sweep_dir       <= 1'b1;
                tone_volume     <= 8'd60;
                noise_volume    <= 8'd40;       // impact crunch
                noise_prescale  <= 8'd40;
            end
            else if (evt_bounce && (current_sfx != SFX_DESTROY && current_sfx != SFX_HIT)) begin
                // Bounce: 35 ms high-pitched metallic chirp
                current_sfx     <= SFX_BOUNCE;
                sfx_timer_ms    <= 10'd35;
                tone_div        <= 19'd11_364;  // 2200 Hz
                tone_sweep_step <= 19'd150;
                sweep_dir       <= 1'b0;        // rises to 2600 Hz
                tone_volume     <= 8'd65;
                noise_volume    <= 8'd0;        // pure tone
                noise_prescale  <= 8'd0;
            end
            else if (evt_fire && (current_sfx == SFX_IDLE || current_sfx == SFX_FIRE)) begin
                // Bullet Fire: 65 ms downward laser sweep (1500 Hz -> 300 Hz)
                current_sfx     <= SFX_FIRE;
                sfx_timer_ms    <= 10'd65;
                tone_div        <= 19'd16_667;  // 1500 Hz
                tone_sweep_step <= 19'd1100;    // fast downward sweep
                sweep_dir       <= 1'b1;
                tone_volume     <= 8'd60;
                noise_volume    <= 8'd0;
                noise_prescale  <= 8'd0;
            end
            // -----------------------------------------------------------------
            // Active SFX Envelope and Pitch Modulation (1 ms Tick)
            // -----------------------------------------------------------------
            else if (tick_1ms && (current_sfx != SFX_IDLE)) begin
                if (sfx_timer_ms > 10'd1) begin
                    sfx_timer_ms <= sfx_timer_ms - 10'd1;

                    // Pitch sweep
                    if (sweep_dir)
                        tone_div <= tone_div + tone_sweep_step;
                    else if (tone_div > tone_sweep_step)
                        tone_div <= tone_div - tone_sweep_step;

                    // Volume decay (linear envelope)
                    case (current_sfx)
                        SFX_FIRE: begin
                            if (tone_volume > 8'd1) tone_volume <= tone_volume - 8'd1;
                        end
                        SFX_BOUNCE: begin
                            if (tone_volume > 8'd2) tone_volume <= tone_volume - 8'd2;
                        end
                        SFX_HIT: begin
                            if (tone_volume > 8'd1)  tone_volume  <= tone_volume - 8'd1;
                            if (noise_volume > 8'd1) noise_volume <= noise_volume - 8'd1;
                        end
                        SFX_DESTROY: begin
                            // Decay noise and tone smoothly over 500 ms
                            if (noise_volume > 8'd0 && (sfx_timer_ms[2:0] == 3'd0))
                                noise_volume <= noise_volume - 8'd1;
                            if (tone_volume > 8'd0 && (sfx_timer_ms[3:0] == 4'd0))
                                tone_volume <= tone_volume - 8'd1;
                        end
                        default: ;
                    endcase
                end else begin
                    // SFX Complete -> Return to IDLE
                    current_sfx     <= SFX_IDLE;
                    sfx_timer_ms    <= 10'd0;
                    tone_volume     <= 8'd0;
                    noise_volume    <= 8'd0;
                    tone_div        <= 19'd0;
                end
            end
        end
    end

    // =========================================================================
    // 4. Square Wave Tone Generator
    // =========================================================================
    reg [18:0] tone_cnt;
    reg        tone_out;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            tone_cnt <= 19'd0;
            tone_out <= 1'b0;
        end else if (tone_volume > 8'd0 && tone_div > 19'd0) begin
            if (tone_cnt >= tone_div) begin
                tone_cnt <= 19'd0;
                tone_out <= ~tone_out;
            end else begin
                tone_cnt <= tone_cnt + 19'd1;
            end
        end else begin
            tone_cnt <= 19'd0;
            tone_out <= 1'b0;
        end
    end

    // =========================================================================
    // 5. Noise Generator (16-bit Galois LFSR)
    // =========================================================================
    reg [15:0] lfsr;
    reg [7:0]  noise_clk_div;
    reg        noise_sample;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            lfsr          <= 16'hACE1; // Non-zero seed
            noise_clk_div <= 8'd0;
            noise_sample  <= 1'b0;
        end else if (noise_volume > 8'd0) begin
            if (noise_clk_div >= noise_prescale) begin
                noise_clk_div <= 8'd0;
                // Galois LFSR polynomial: x^16 + x^14 + x^13 + x^11 + 1
                lfsr <= {lfsr[14:0], 1'b0} ^ ({16{lfsr[15]}} & 16'h002D);
                noise_sample <= lfsr[0];
            end else begin
                noise_clk_div <= noise_clk_div + 8'd1;
            end
        end else begin
            noise_clk_div <= 8'd0;
            noise_sample  <= 1'b0;
        end
    end

    // =========================================================================
    // 6. Audio Mixer
    // Centered around mid-rail (128) with signed bipolar deflection:
    // sample = 128 + tone_signed + noise_signed
    // =========================================================================
    wire signed [8:0] tone_term  = (tone_volume == 0)  ? 9'sd0 : (tone_out     ? $signed({1'b0, tone_volume})  : -$signed({1'b0, tone_volume}));
    wire signed [8:0] noise_term = (noise_volume == 0) ? 9'sd0 : (noise_sample ? $signed({1'b0, noise_volume}) : -$signed({1'b0, noise_volume}));

    wire signed [10:0] mixed_sum = 11'sd128 + {{2{tone_term[8]}}, tone_term} + {{2{noise_term[8]}}, noise_term};

    // Clamp to 8-bit unsigned range [0..255]
    reg [7:0] mixed_sample;
    always @(*) begin
        if (mixed_sum < 11'sd0)
            mixed_sample = 8'd0;
        else if (mixed_sum > 11'sd255)
            mixed_sample = 8'd255;
        else
            mixed_sample = mixed_sum[7:0];
    end

    // =========================================================================
    // 7. PWM Digital-to-Analog Converter (50 MHz / 256 = 195.3 kHz carrier)
    // =========================================================================
    reg [7:0] pwm_acc;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n)
            pwm_acc <= 8'd0;
        else
            pwm_acc <= pwm_acc + 8'd1;
    end

    // Pin A11: PWM audio stream
    assign aud_pwm = (mixed_sample > pwm_acc);

    // Pin D12: Audio amplifier shutdown (active-low). Drive HIGH to enable.
    assign aud_sd  = reset_n;

endmodule

`endif
