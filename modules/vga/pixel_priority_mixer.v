`timescale 1ns / 1ps
//=============================================================================
// Fig 10: Pixel Priority Mixer, Sync Delay Line and VGA Output Registers
//
// Layer Priority (Timing Sheet E):
//   HUD > Big Bullet > Normal Bullet > Tank P1/P2 > Maze Wall > Floor > Background
//
// Delay Line (Fig 10 Part B):
//   Matches the pipeline latency between VGA coordinate generation,
//   renderer BRAM/shape lookups, and the mixer registers so that HSYNC,
//   VSYNC, and RGB blanking remain strictly aligned to the visible beam.
//=============================================================================
`ifndef PIXEL_PRIORITY_MIXER_V
`define PIXEL_PRIORITY_MIXER_V

module pixel_priority_mixer (
    input  wire        clk,            // 50 MHz clk_sys
    input  wire        reset_n,
    input  wire        pix_ce,

    // Timing inputs from vga_timing_gen
    input  wire        hsync_n_in,
    input  wire        vsync_n_in,
    input  wire        active_in,

    // Layer 1: Health HUD (Highest priority)
    input  wire        hud_valid,
    input  wire [11:0] hud_rgb,

    // Layer 2: Big / Special Bullets
    input  wire        big_valid,
    input  wire [11:0] big_rgb,

    // Layer 3: Normal Bullets
    input  wire        bullet_valid,
    input  wire [11:0] bullet_rgb,

    // Layer 4: Tanks (P1 & P2)
    input  wire        tank_valid_p1,
    input  wire [11:0] tank_rgb_p1,
    input  wire        tank_valid_p2,
    input  wire [11:0] tank_rgb_p2,

    // Layer 5: Maze Tiles (Walls & Arena Floor)
    input  wire        maze_wall,
    input  wire [11:0] maze_rgb,

    // Physical 12-bit DAC VGA output pins (to Nexys A7 resistor ladder)
    output reg  [3:0]  vga_r,
    output reg  [3:0]  vga_g,
    output reg  [3:0]  vga_b,
    output reg         vga_hsync,
    output reg         vga_vsync
);

    // =========================================================================
    // 1. Sync & Active Delay Line (Fig 10 Part B)
    // Matches the 1-clock registered output of the renderers + 1 output stage
    // =========================================================================
    reg [1:0] hsync_pipe;
    reg [1:0] vsync_pipe;
    reg [1:0] active_pipe;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            hsync_pipe  <= 2'b11;
            vsync_pipe  <= 2'b11;
            active_pipe <= 2'b00;
        end else if (pix_ce) begin
            hsync_pipe  <= {hsync_pipe[0],  hsync_n_in};
            vsync_pipe  <= {vsync_pipe[0],  vsync_n_in};
            active_pipe <= {active_pipe[0], active_in};
        end
    end

    // =========================================================================
    // 2. Strict Priority Multiplexer Chain (Fig 10 Part A & Timing Sheet E)
    // =========================================================================
    reg [11:0] selected_rgb;

    always @(*) begin
        if (hud_valid)
            selected_rgb = hud_rgb;
        else if (big_valid)
            selected_rgb = big_rgb;
        else if (bullet_valid)
            selected_rgb = bullet_rgb;
        else if (tank_valid_p1)
            selected_rgb = tank_rgb_p1;
        else if (tank_valid_p2)
            selected_rgb = tank_rgb_p2;
        else if (maze_wall)
            selected_rgb = maze_rgb;
        else
            selected_rgb = maze_rgb; // Arena floor or black
    end

    // =========================================================================
    // 3. Final VGA Output Registers
    // =========================================================================
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            vga_r     <= 4'h0;
            vga_g     <= 4'h0;
            vga_b     <= 4'h0;
            vga_hsync <= 1'b1;
            vga_vsync <= 1'b1;
        end else if (pix_ce) begin
            vga_hsync <= hsync_pipe[1];
            vga_vsync <= vsync_pipe[1];

            if (active_pipe[1]) begin
                vga_r <= selected_rgb[11:8];
                vga_g <= selected_rgb[7:4];
                vga_b <= selected_rgb[3:0];
            end else begin
                // Blanking interval: drive RGB strictly to 0
                vga_r <= 4'h0;
                vga_g <= 4'h0;
                vga_b <= 4'h0;
            end
        end
    end

endmodule

`endif
