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
    parameter IMEM_HEX = "imem.hex",
    parameter DMEM_HEX = "dmem.hex",
    parameter IMEMSIZE = 4096,
    parameter DMEMSIZE = 4096,
    parameter CLK_PER_MS = 50_000,
    parameter DEBOUNCE_MAX = 20'd500_000
)(
    input  wire        clk,            // 100 MHz board oscillator (pin E3)
    input  wire        reset,          // active-low reset button (pin C12)

    // Optional raw player buttons from board / breadboard
    input  wire [5:0]  p1_btn_raw,     // [0]=FWD, [1]=BWD, [2]=L, [3]=R, [4]=SHOOT, [5]=SPEC
    input  wire [5:0]  p2_btn_raw,

    // Status / debug LEDs (pins H17..V11)
    output wire [15:0] led,

    // VGA 12-bit Video DAC Outputs (Nexys A7)
    output wire [3:0]  vga_r,
    output wire [3:0]  vga_g,
    output wire [3:0]  vga_b,
    output wire        vga_hsync,
    output wire        vga_vsync
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
    // Write cycle uses write_address; read cycle uses read_address
    wire [31:0] mem_bus_addr = dmem_write_ready ? dmem_write_address : dmem_read_address;
    wire        mem_bus_we   = dmem_write_ready;
    wire        mem_bus_re   = dmem_read_ready;

    // Peripheral read data lines (1-cycle latency)
    wire [31:0] rd_dmem;
    wire [31:0] rd_in;
    wire [31:0] rd_tmr;
    wire [31:0] rd_col;
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
        .re    (dmem_read_ready && cs_dmem),
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
        .d_wdata     (dmem_write_data),
        .d_wstrb     (dmem_write_byte),
        .d_we        (mem_bus_we),
        .d_re        (mem_bus_re),
        .d_rdata     (dmem_cpu_rdata),

        .rd_dmem     (rd_dmem),
        .rd_in       (rd_in),
        .rd_tmr      (rd_tmr),
        .rd_col      (rd_col),
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
        .DEBOUNCE_MAX(DEBOUNCE_MAX)
    ) u_input (
        .clk           (clk_sys),
        .reset_n       (rst_n),
        .p1_btn_raw    (p1_btn_raw),
        .p2_btn_raw    (p2_btn_raw),
        .d_addr        (mem_bus_addr),
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
        .d_wdata     (dmem_write_data),
        .rd_col      (rd_col)
    );

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
    // 11. Status LEDs (Live hardware telemetry)
    // =========================================================================
    assign led = {
        pc_out[13:2],                  // [15:4] active instruction PC word
        exception,                     // [3] illegal instruction / alignment exception
        u_collision.tank_hit_any,      // [2] bullet-tank collision detected
        u_collision.bb_any,            // [1] bullet-bullet collision detected
        u_collision.wall_any           // [0] bullet-wall collision detected
    };

endmodule

`endif
