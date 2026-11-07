`timescale 1ns / 1ps
//=============================================================================
// Battle Tanks: Top-Level FPGA Module (Fig 1)
//
// 1. Clock Generation: Synthesizes 50.0 MHz clk_sys and 25.0 MHz pix_ce from
//    the 100 MHz board oscillator.
// 2. RV32IM CPU Subsystem: 3-stage core with RV32M MUL/DIV acceleration.
// 3. Instruction & Data Memories (BRAM).
// 4. MMIO Interconnect: Routes addr[31]=0 to Data RAM and addr[31]=1 to MMIO.
// 5. Hardware Peripherals:
//    - Input Controller (2-FF sync + debouncer x12)
//    - Cooldown Timers (1 ms prescaler + 4 down-counters)
//    - Sprite & HUD Register File (12 x 32-bit registers)
//    - Hardware Collision Engine (AABB cells + bullet-wall scanner + W1C status)
//    - Mirrored Maze Tile RAM (Copy V display + Copy C collision)
//=============================================================================
`ifndef TOP_FPGA_V
`define TOP_FPGA_V

module top_fpga #(
    // "" = use the firmware image embedded in modules/cpu/firmware_*.vh (default,
    // robust for Vivado synthesis). Pass a file name to load a .hex instead.
    parameter IMEM_HEX = "",
    parameter DMEM_HEX = "",
    parameter IMEMSIZE = 4096,
    parameter DMEMSIZE = 4096,
    parameter CLK_PER_MS = 50_000,
    parameter DEBOUNCE_MAX = 20'd150_000,
    parameter MIN_HOLD     = 21'd1_000_000,
    parameter SEG_SCAN_BIT = 15
)(
    input  wire        clk,            // 100 MHz board oscillator (pin E3)
    input  wire        reset,          // active-low reset button (pin C12)

    // Optional raw player buttons from board / breadboard
    input  wire [5:0]  p1_btn_raw,     // [0]=FWD, [1]=BWD, [2]=L, [3]=R, [4]=SHOOT, [5]=SPEC
    input  wire [5:0]  p2_btn_raw,

    // Status / debug LEDs (pins H17..V11)
    output wire [15:0] led,

    // 7-Segment Display Outputs (Nexys A7 DISP1 & DISP2 combined)
    output wire [6:0]  seg,            // Active-low cathodes {CG, CF, CE, CD, CC, CB, CA}
    output wire [7:0]  an,             // Active-low anodes AN[7:0] (AN[7:4]=DISP1, AN[3:0]=DISP2)
    output wire        dp,             // Active-low decimal point

    // VGA 12-bit Video DAC Outputs (Nexys A7)
    output wire [3:0]  vga_r,
    output wire [3:0]  vga_g,
    output wire [3:0]  vga_b,
    output wire        vga_hsync,
    output wire        vga_vsync,

    // Audio PWM Outputs (Nexys A7 3.5mm Mono Audio Jack J8)
    output wire        aud_pwm,
    output wire        aud_sd
);

    // =========================================================================
    // 1. Clock & Reset Generation
    // Synthesizes 50 MHz clk_sys and 25 MHz pix_ce from 100 MHz input clock
    // =========================================================================
    reg clk_sys_reg;
    reg pix_ce_reg;

    always @(posedge clk or negedge reset) begin
        if (!reset) begin
            clk_sys_reg <= 1'b0;
            pix_ce_reg  <= 1'b0;
        end else begin
            clk_sys_reg <= ~clk_sys_reg;       // 100 MHz -> 50 MHz
            if (clk_sys_reg)
                pix_ce_reg <= ~pix_ce_reg;     // 50 MHz -> 25 MHz pixel enable
        end
    end

    wire clk_sys = clk_sys_reg;
    wire pix_ce  = pix_ce_reg;

    // Reset synchronizer for 50 MHz clock domain
    reg rst_sync1, rst_sync2;
    always @(posedge clk_sys or negedge reset) begin
        if (!reset) begin
            rst_sync1 <= 1'b0;
            rst_sync2 <= 1'b0;
        end else begin
            rst_sync1 <= 1'b1;
            rst_sync2 <= rst_sync1;
        end
    end
    wire rst_n = rst_sync2;

    // =========================================================================
    // 2. CPU <-> Memory / MMIO Signals
    // =========================================================================
    wire [31:0] pc_out;
    wire        exception;

    wire [31:0] inst_mem_address;
    wire [31:0] inst_mem_read_data;

    wire        dmem_read_ready;
    wire [31:0] dmem_read_address;
    wire        dmem_write_ready;
    wire [31:0] dmem_write_address;
    wire [31:0] dmem_write_data;
    wire [3:0]  dmem_write_byte;
    wire [31:0] dmem_cpu_rdata;

    // Common memory bus address and strobes
    // mem_bus_addr is the WRITE-side address (used for every write decode).
    // Loads (EX stage) and stores (WB stage) can be issued in the same clock, so
    // reads MUST NOT be steered by the write address: they use their own
    // dmem_read_address path (mem_rd_addr / mem_rd_addr_q below).
    wire [31:0] mem_bus_addr = dmem_write_ready ? dmem_write_address : dmem_read_address;
    wire        mem_bus_we   = dmem_write_ready;
    wire        mem_bus_re   = dmem_read_ready;

    // Read address, live (for synchronous RAM-style reads) and registered by one
    // clock (for peripherals whose read data is muxed combinationally in the cycle
    // AFTER the load, aligned with the interconnect's registered chip-selects).
    wire [31:0] mem_rd_addr = dmem_read_address;
    reg  [31:0] mem_rd_addr_q;
    always @(posedge clk_sys or negedge rst_n) begin
        if (!rst_n) mem_rd_addr_q <= 32'd0;
        else        mem_rd_addr_q <= mem_rd_addr;
    end

    // Peripheral read data lines (1-cycle latency)
    wire [31:0] rd_dmem;
    wire [31:0] rd_in;
    wire [31:0] rd_tmr;
    wire [31:0] rd_col;
    wire [31:0] rd_perf;
    wire [31:0] rd_maze;

    // Interconnect chip-selects and write strobes
    wire        cs_dmem;
    wire [3:0]  dmem_we;
    wire        cs_in;
    wire        cs_tmr, wr_en_tmr;
    wire        cs_col, wr_en_col;
    wire        cs_spr, wr_en_spr;
    wire        cs_maze, wr_en_maze;

    // =========================================================================
    // 3. RV32IM Soft-Core Processor
    // =========================================================================
    pipe pipe_u (
        .clk                (clk_sys),
        .reset              (rst_n),
        .stall              (1'b0),
        .exception          (exception),
        .pc_out             (pc_out),

        .inst_mem_is_valid  (1'b1),
        .inst_mem_read_data (inst_mem_read_data),

        .dmem_read_data_temp(dmem_cpu_rdata),
        .dmem_write_valid   (1'b1),
        .dmem_read_valid    (1'b1),

        .inst_mem_address   (inst_mem_address),
        .dmem_read_ready    (dmem_read_ready),
        .dmem_read_address  (dmem_read_address),
        .dmem_write_ready   (dmem_write_ready),
        .dmem_write_address (dmem_write_address),
        .dmem_write_data    (dmem_write_data),
        .dmem_write_byte    (dmem_write_byte)
    );

    // Instruction ROM (4 KB)
    instr_mem #(
        .HEX_FILE(IMEM_HEX)
    ) IMEM (
        .clk   (clk_sys),
        .pc    (inst_mem_address),
        .instr (inst_mem_read_data)
    );

    // Data RAM (4 KB)
    data_mem #(
        .HEX_FILE(DMEM_HEX)
    ) DMEM (
        .clk   (clk_sys),
        .re    (dmem_read_ready && !mem_rd_addr[31]),
        .raddr (dmem_read_address),
        .rdata (rd_dmem),
        .we    (dmem_write_ready && cs_dmem),
        .waddr (dmem_write_address),
        .wdata (dmem_write_data),
        .wstrb (dmem_we)
    );

    // =========================================================================
    // 4. MMIO Interconnect (Fig 2a & Fig 2b)
    // =========================================================================
    mmio_interconnect u_mmio (
        .clk         (clk_sys),
        .reset_n     (rst_n),
        .d_addr      (mem_bus_addr),
        .d_raddr     (mem_rd_addr),
        .d_wdata     (dmem_write_data),
        .d_wstrb     (dmem_write_byte),
        .d_we        (mem_bus_we),
        .d_re        (mem_bus_re),
        .d_rdata     (dmem_cpu_rdata),

        .rd_dmem     (rd_dmem),
        .rd_in       (rd_in),
        .rd_tmr      (rd_tmr),
        .rd_col      (rd_col),
        .rd_perf     (rd_perf),
        .rd_maze     (rd_maze),

        .cs_dmem     (cs_dmem),
        .dmem_we     (dmem_we),
        .cs_in       (cs_in),
        .cs_tmr      (cs_tmr),
        .wr_en_tmr   (wr_en_tmr),
        .cs_col      (cs_col),
        .wr_en_col   (wr_en_col),
        .cs_spr      (cs_spr),
        .wr_en_spr   (wr_en_spr),
        .cs_maze     (cs_maze),
        .wr_en_maze  (wr_en_maze)
    );

    // =========================================================================
    // 5. Input Controller (Fig 3)
    // =========================================================================
    wire [5:0] p1_btn_debounced;
    wire [5:0] p2_btn_debounced;

    input_controller #(
        .DEBOUNCE_MAX(DEBOUNCE_MAX),
        .MIN_HOLD    (MIN_HOLD)
    ) u_input (
        .clk           (clk_sys),
        .reset_n       (rst_n),
        .p1_btn_raw    (p1_btn_raw),
        .p2_btn_raw    (p2_btn_raw),
        .d_addr        (mem_rd_addr_q),
        .rd_in         (rd_in),
        .p1_btn_stable (p1_btn_debounced),
        .p2_btn_stable (p2_btn_debounced)
    );

    // =========================================================================
    // 6. Cooldown Timers (Fig 4)
    // =========================================================================
    cooldown_timers #(
        .CLK_PER_MS(CLK_PER_MS)
    ) u_timers (
        .clk       (clk_sys),
        .reset_n   (rst_n),
        .wr_en_tmr (wr_en_tmr),
        .d_addr    (mem_bus_addr),
        .d_wdata   (dmem_write_data),
        .rd_tmr    (rd_tmr)
    );

    // =========================================================================
    // 7. Sprite & HUD Register File (Fig 5)
    // =========================================================================
    wire [9:0] p1_tank_x, p1_tank_y;
    wire [9:0] p2_tank_x, p2_tank_y;
    wire [9:0] bullet_x   [0:7];
    wire [9:0] bullet_y   [0:7];
    wire [7:0] bullet_act;
    wire [7:0] bullet_big;
    wire [7:0] hp1, hp2;
    wire [3:0] tank_ang1, tank_ang2;

    sprite_hud_regfile u_sprites (
        .clk        (clk_sys),
        .reset_n    (rst_n),
        .wr_en_spr  (wr_en_spr),
        .d_addr     (mem_bus_addr),
        .d_wdata    (dmem_write_data),

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

    // =========================================================================
    // 8. Mirrored Maze Tile RAM (Fig 7)
    // =========================================================================
    wire [8:0] col_tile_addr;
    wire [1:0] col_tile_data;
    wire [8:0] vga_tile_addr;
    wire [1:0] vga_tile_data;

    maze_tile_ram u_maze (
        .clk           (clk_sys),
        .reset_n       (rst_n),
        .wr_en_maze    (wr_en_maze),
        .d_addr        (mem_bus_addr),
        .d_raddr       (mem_rd_addr),
        .d_wdata       (dmem_write_data),
        .rd_maze       (rd_maze),

        .vga_tile_addr (vga_tile_addr),
        .vga_tile_data (vga_tile_data),

        .col_tile_addr (col_tile_addr),
        .col_tile_data (col_tile_data)
    );

    // =========================================================================
    // 9. Hardware Collision Engine (Fig 6a..6d)
    // =========================================================================
    wire [2:0] col_scan_idx;

    collision_engine u_collision (
        .clk         (clk_sys),
        .reset_n     (rst_n),

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
        .d_addr      (mem_bus_addr),
        .d_raddr     (mem_rd_addr_q),
        .d_wdata     (dmem_write_data),
        .rd_col      (rd_col),
        .scan_idx    (col_scan_idx)
    );

    // =========================================================================
    // 9b. Performance & Cycle Profiling Telemetry Unit
    // Latches exact cycle counts for 1 full VGA frame & collision engine sweeps
    // Accessible via MMIO:
    //   0x8000_0030: Total clock cycles per 1 VGA frame (840,000 @ 50 MHz)
    //   0x8000_0034: Active visible display cycles (614,400 @ 50 MHz)
    //   0x8000_0038: Clock cycles for 1 complete collision sweep (8 cycles)
    //   0x8000_003C: Completed collision sweeps per frame (105,000 sweeps)
    // =========================================================================
    reg [31:0] vga_frame_cycle_acc;
    reg [31:0] vga_active_cycle_acc;
    reg [31:0] col_sweep_acc;

    reg [31:0] reg_perf_vga_total;
    reg [31:0] reg_perf_vga_active;
    reg [31:0] reg_perf_col_sweep;
    reg [31:0] reg_perf_col_sweeps_per_frame;

    wire col_sweep_tick = (col_scan_idx == 3'd7);

    always @(posedge clk_sys or negedge rst_n) begin
        if (!rst_n) begin
            vga_frame_cycle_acc           <= 32'd0;
            vga_active_cycle_acc          <= 32'd0;
            col_sweep_acc                 <= 32'd0;
            reg_perf_vga_total            <= 32'd840_000;
            reg_perf_vga_active           <= 32'd614_400;
            reg_perf_col_sweep            <= 32'd8;
            reg_perf_col_sweeps_per_frame <= 32'd105_000;
        end else begin
            // Accumulate active visible cycles
            if (vga_active)
                vga_active_cycle_acc <= vga_active_cycle_acc + 32'd1;

            // Track completed collision sweeps (8 clocks each)
            if (col_sweep_tick)
                col_sweep_acc <= col_sweep_acc + 32'd1;

            // On VGA frame boundary (start of VBLANK), latch metrics
            if (vga_frame_tick) begin
                reg_perf_vga_total            <= vga_frame_cycle_acc + 32'd1;
                reg_perf_vga_active           <= vga_active_cycle_acc;
                reg_perf_col_sweep            <= 32'd8;
                reg_perf_col_sweeps_per_frame <= col_sweep_acc;

                vga_frame_cycle_acc           <= 32'd0;
                vga_active_cycle_acc          <= 32'd0;
                col_sweep_acc                 <= 32'd0;
            end else begin
                vga_frame_cycle_acc <= vga_frame_cycle_acc + 32'd1;
            end
        end
    end

    // MMIO Read Multiplexer for 0x8000_0030..0x8000_003C
    reg [31:0] rd_perf_mux;
    always @(*) begin
        case (mem_rd_addr_q[3:2])
            2'b00:   rd_perf_mux = reg_perf_vga_total;            // 0x8000_0030
            2'b01:   rd_perf_mux = reg_perf_vga_active;           // 0x8000_0034
            2'b10:   rd_perf_mux = reg_perf_col_sweep;            // 0x8000_0038
            2'b11:   rd_perf_mux = reg_perf_col_sweeps_per_frame; // 0x8000_003C
            default: rd_perf_mux = 32'd0;
        endcase
    end
    assign rd_perf = rd_perf_mux;

    // =========================================================================
    // 10. VGA Display Subsystem (Fig 8..12)
    // =========================================================================
    wire [9:0] vga_beam_x;
    wire [9:0] vga_beam_y;
    wire       vga_active;
    wire       vga_hsync_raw;
    wire       vga_vsync_raw;
    wire       vga_frame_tick;

    vga_timing_gen u_vga_timing (
        .clk        (clk_sys),
        .reset_n    (rst_n),
        .pix_ce     (pix_ce),
        .x          (vga_beam_x),
        .y          (vga_beam_y),
        .hcnt       (),
        .vcnt       (),
        .hsync_n    (vga_hsync_raw),
        .vsync_n    (vga_vsync_raw),
        .active     (vga_active),
        .h_end      (),
        .v_end      (),
        .frame_tick (vga_frame_tick)
    );

    // Maze Tile Renderer (Fig 11)
    wire        maze_pixel_wall;
    wire [11:0] maze_pixel_rgb;

    maze_tile_renderer u_maze_render (
        .clk           (clk_sys),
        .reset_n       (rst_n),
        .pix_ce        (pix_ce),
        .x             (vga_beam_x),
        .y             (vga_beam_y),
        .active        (vga_active),
        .maze_vga_addr (vga_tile_addr),
        .maze_vga_data (vga_tile_data),
        .maze_wall     (maze_pixel_wall),
        .maze_rgb      (maze_pixel_rgb)
    );

    // Sprite Engine (Fig 9)
    wire        spr_tank_valid_p1;
    wire [11:0] spr_tank_rgb_p1;
    wire        spr_tank_valid_p2;
    wire [11:0] spr_tank_rgb_p2;
    wire        spr_bullet_valid;
    wire [11:0] spr_bullet_rgb;
    wire        spr_big_valid;
    wire [11:0] spr_big_rgb;

    sprite_engine u_sprites_render (
        .clk           (clk_sys),
        .reset_n       (rst_n),
        .pix_ce        (pix_ce),
        .x             (vga_beam_x),
        .y             (vga_beam_y),
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
        .tank_valid_p1 (spr_tank_valid_p1),
        .tank_rgb_p1   (spr_tank_rgb_p1),
        .tank_valid_p2 (spr_tank_valid_p2),
        .tank_rgb_p2   (spr_tank_rgb_p2),
        .bullet_valid  (spr_bullet_valid),
        .bullet_rgb    (spr_bullet_rgb),
        .big_valid     (spr_big_valid),
        .big_rgb       (spr_big_rgb)
    );

    // Health HUD (Fig 12)
    wire        hud_pixel_valid;
    wire [11:0] hud_pixel_rgb;

    health_hud u_hud_render (
        .clk       (clk_sys),
        .reset_n   (rst_n),
        .pix_ce    (pix_ce),
        .x         (vga_beam_x),
        .y         (vga_beam_y),
        .active    (vga_active),
        .hp1       (hp1),
        .hp2       (hp2),
        .hud_valid (hud_pixel_valid),
        .hud_rgb   (hud_pixel_rgb)
    );

    // Pixel Priority Mixer & VGA DAC Registers (Fig 10)
    pixel_priority_mixer u_mixer (
        .clk           (clk_sys),
        .reset_n       (rst_n),
        .pix_ce        (pix_ce),
        .hsync_n_in    (vga_hsync_raw),
        .vsync_n_in    (vga_vsync_raw),
        .active_in     (vga_active),
        .hud_valid     (hud_pixel_valid),
        .hud_rgb       (hud_pixel_rgb),
        .big_valid     (spr_big_valid),
        .big_rgb       (spr_big_rgb),
        .bullet_valid  (spr_bullet_valid),
        .bullet_rgb    (spr_bullet_rgb),
        .tank_valid_p1 (spr_tank_valid_p1),
        .tank_rgb_p1   (spr_tank_rgb_p1),
        .tank_valid_p2 (spr_tank_valid_p2),
        .tank_rgb_p2   (spr_tank_rgb_p2),
        .maze_wall     (maze_pixel_wall),
        .maze_rgb      (maze_pixel_rgb),
        .vga_r         (vga_r),
        .vga_g         (vga_g),
        .vga_b         (vga_b),
        .vga_hsync     (vga_hsync),
        .vga_vsync     (vga_vsync)
    );

    // =========================================================================
    // 11. Status LEDs (human-readable hardware telemetry)
    //
    // The old mapping drove LD15..LD4 straight from PC[13:2]. The PC changes
    // at 50 MHz, so those LEDs can never be seen "changing": a healthy game
    // shows a fixed dim pattern, and a CPU running garbage (e.g. imem.hex not
    // loaded -> all-zero ROM) toggles every bit and looks like ALL LEDs ON.
    // The LEDs now show slow, meaningful status instead:
    //   LD15     : 1.5 Hz heartbeat            (clock + reset OK)
    //   LD14     : game-loop heartbeat         (toggles every 16 game frames:
    //              ~2 Hz blink = CPU is running the C game loop)
    //   LD13..8  : P1 debounced buttons        [FWD,BWD,L,R,SHOOT,SPEC] = [8..13]
    //   LD7..4   : P2 debounced FWD,BWD,L,R    = [4..7]
    //   LD3      : CPU exception, LATCHED until reset (illegal instr/misaligned)
    //   LD2..0   : tank / bullet-bullet / wall collision flags
    // =========================================================================
    reg [24:0] hb_cnt;
    always @(posedge clk_sys or negedge rst_n) begin
        if (!rst_n) hb_cnt <= 25'd0;
        else        hb_cnt <= hb_cnt + 25'd1;
    end

    // One write to REG_SPRITE_P1_TANK (0x8000_0040) happens per game frame
    reg [4:0] frame_cnt;
    always @(posedge clk_sys or negedge rst_n) begin
        if (!rst_n)
            frame_cnt <= 5'd0;
        else if (wr_en_spr && (mem_bus_addr[7:2] == 6'd16))
            frame_cnt <= frame_cnt + 5'd1;
    end

    reg exception_latched;
    always @(posedge clk_sys or negedge rst_n) begin
        if (!rst_n)         exception_latched <= 1'b0;
        else if (exception) exception_latched <= 1'b1;
    end

    assign led = {
        hb_cnt[24],                    // [15] heartbeat
        frame_cnt[4],                  // [14] game loop alive
        p1_btn_debounced[5:0],         // [13:8] P1 buttons
        p2_btn_debounced[3:0],         // [7:4]  P2 move/turn switches
        exception_latched,             // [3] latched CPU exception
        u_collision.tank_hit_any,      // [2] bullet-tank collision detected
        u_collision.bb_any,            // [1] bullet-bullet collision detected
        u_collision.wall_any           // [0] bullet-wall collision detected
    };


    // =========================================================================
    // 12. Hardware Sound Engine (Autonomous Event Sniffer & Audio Synthesizer)
    // =========================================================================
    sound_engine #(
        .CLK_FREQ_HZ (50_000_000),
        .STARTUP_MS  (20)
    ) u_sound (
        .clk          (clk_sys),
        .reset_n      (rst_n),
        .bullet_act   (bullet_act),
        .hp1          (hp1),
        .hp2          (hp2),
        .wall_hit_any (u_collision.wall_any),
        .tank_hit_any (u_collision.tank_hit_any),
        .trig_fire    (1'b0),
        .trig_bounce  (1'b0),
        .trig_hit     (1'b0),
        .trig_destroy (1'b0),
        .sfx_active   (),
        .current_sfx  (),
        .aud_pwm      (aud_pwm),
        .aud_sd       (aud_sd)
    );


    // =========================================================================
    // 13. 8-Digit 7-Segment Winner Display (Nexys A7 DISP1 & DISP2 Combined)
    //
    // Player 1 tank is BLUE (hp1); Player 2 tank is RED (hp2).
    //   - Both hp1 > 0 and hp2 > 0 : Display OFF (game in progress)
    //   - hp1 == 0 and hp2 > 0     : "RED  WON" (Player 2 Red wins)
    //   - hp2 == 0 and hp1 > 0     : "BLUE WON" (Player 1 Blue wins)
    //   - hp1 == 0 and hp2 == 0    : "  DRAW  " (Simultaneous loss / draw)
    //
    // Active-low segment encoding: seg[6:0] = {CG, CF, CE, CD, CC, CB, CA}
    // =========================================================================
    localparam [6:0] SEG_BLANK = 7'b111_1111; // ' '
    localparam [6:0] SEG_B     = 7'b000_0011; // 'b' (B)
    localparam [6:0] SEG_L     = 7'b100_0111; // 'L'
    localparam [6:0] SEG_U     = 7'b100_0001; // 'U'
    localparam [6:0] SEG_E     = 7'b000_0110; // 'E'
    localparam [6:0] SEG_R     = 7'b010_1111; // 'r' (R)
    localparam [6:0] SEG_D     = 7'b010_0001; // 'd' (D)
    localparam [6:0] SEG_A     = 7'b000_1000; // 'A'
    localparam [6:0] SEG_W     = 7'b000_0001; // 'W'
    localparam [6:0] SEG_O     = 7'b100_0000; // 'O'
    localparam [6:0] SEG_N     = 7'b100_1000; // 'N'

    wire p1_dead = (hp1 == 8'd0);
    wire p2_dead = (hp2 == 8'd0);
    wire [2:0] seg_digit_sel = hb_cnt[SEG_SCAN_BIT + 2 : SEG_SCAN_BIT];

    reg [6:0] seg_char;
    always @(*) begin
        seg_char = SEG_BLANK;
        if (p1_dead && p2_dead) begin
            // Both lost at the same time -> "  DRAW  "
            case (seg_digit_sel)
                3'd5: seg_char = SEG_D;
                3'd4: seg_char = SEG_R;
                3'd3: seg_char = SEG_A;
                3'd2: seg_char = SEG_W;
                default: seg_char = SEG_BLANK;
            endcase
        end else if (p1_dead) begin
            // P1 (Blue) health gone -> P2 (Red) wins -> "RED  WON"
            case (seg_digit_sel)
                3'd7: seg_char = SEG_R;
                3'd6: seg_char = SEG_E;
                3'd5: seg_char = SEG_D;
                3'd2: seg_char = SEG_W;
                3'd1: seg_char = SEG_O;
                3'd0: seg_char = SEG_N;
                default: seg_char = SEG_BLANK;
            endcase
        end else if (p2_dead) begin
            // P2 (Red) health gone -> P1 (Blue) wins -> "BLUE WON"
            case (seg_digit_sel)
                3'd7: seg_char = SEG_B;
                3'd6: seg_char = SEG_L;
                3'd5: seg_char = SEG_U;
                3'd4: seg_char = SEG_E;
                3'd2: seg_char = SEG_W;
                3'd1: seg_char = SEG_O;
                3'd0: seg_char = SEG_N;
                default: seg_char = SEG_BLANK;
            endcase
        end
    end

    assign seg = seg_char;
    assign an  = (seg_char == SEG_BLANK) ? 8'hFF : ~(8'b0000_0001 << seg_digit_sel);
    assign dp  = 1'b1;

endmodule

`endif
