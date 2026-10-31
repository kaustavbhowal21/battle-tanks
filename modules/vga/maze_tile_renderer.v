`timescale 1ns / 1ps
//=============================================================================
// Fig 11: Maze Tile Renderer
// Pixel (x, y) -> Tile address -> Wall / Floor Color
//
// 24 px tiles, 20 x 20 grid = 480 x 480 playfield at the left of the screen.
// No hardware divider: tile column (tile_x) and sub-pixel (sub_x) advance
// with pix_ce. Tile row (tile_y) and sub_y advance on each line tick.
//
// BRAM read takes 1 clock cycle latency on Maze RAM Copy V port B;
// internal coordinates and in_maze flags are delayed by 1 clock to align.
//=============================================================================
`ifndef MAZE_TILE_RENDERER_V
`define MAZE_TILE_RENDERER_V

module maze_tile_renderer (
    input  wire        clk,            // 50 MHz clk_sys
    input  wire        reset_n,
    input  wire        pix_ce,         // 25 MHz pixel clock enable

    input  wire [9:0]  x,              // 0..639 from vga_timing_gen
    input  wire [9:0]  y,              // 0..479 from vga_timing_gen
    input  wire        active,

    // Interface to Mirrored Maze RAM Copy V Port B
    output wire [8:0]  maze_vga_addr,  // 0..399 tile address
    input  wire [1:0]  maze_vga_data,  // 2-bit tile type from BRAM

    // Pixel outputs to Pixel Priority Mixer (Fig 10)
    output reg         maze_wall,      // 1 if current pixel is a solid wall
    output reg  [11:0] maze_rgb        // 12-bit RGB wall/floor color
);

    // =========================================================================
    // 1. Direct Tile Coordinate & Sub-Pixel Derivation (24x24 px tiles)
    // =========================================================================
    wire in_maze = (x < 10'd480) && (y < 10'd480) && active;

    // Direct derivation from beam coordinates (immune to blanking interval jitter)
    wire [4:0] tile_x = (x < 10'd480) ? (x / 5'd24) : 5'd0;
    wire [4:0] sub_x  = (x < 10'd480) ? (x % 5'd24) : 5'd0;
    wire [4:0] tile_y = (y < 10'd480) ? (y / 5'd24) : 5'd0;
    wire [4:0] sub_y  = (y < 10'd480) ? (y % 5'd24) : 5'd0;

    // Tile RAM address: tile_y * 20 + tile_x = (tile_y << 4) + (tile_y << 2) + tile_x
    wire [8:0] next_tile_addr = ({4'd0, tile_y} << 4) + ({4'd0, tile_y} << 2) + {4'd0, tile_x};

    assign maze_vga_addr = next_tile_addr;

    // =========================================================================
    // 2. 1-Clock Alignment Pipeline (matching BRAM synchronous read latency)
    // =========================================================================
    reg       in_maze_d;
    reg [4:0] sub_x_d, sub_y_d;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            in_maze_d <= 1'b0;
            sub_x_d   <= 5'd0;
            sub_y_d   <= 5'd0;
        end else begin
            in_maze_d <= in_maze;
            sub_x_d   <= sub_x;
            sub_y_d   <= sub_y;
        end
    end

    // =========================================================================
    // 3. Wall / Floor Color Generation (Timing Sheet E & H)
    // =========================================================================
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            maze_wall <= 1'b0;
            maze_rgb  <= 12'h000;
        end else begin
            if (!in_maze_d) begin
                maze_wall <= 1'b0;
                maze_rgb  <= 12'h000; // Black outside maze arena
            end else begin
                case (maze_vga_data)
                    2'b00: begin // Empty Floor
                        maze_wall <= 1'b0;
                        // Subtle arena floor grid
                        if ((sub_x_d == 5'd0) || (sub_y_d == 5'd0))
                            maze_rgb <= 12'h112; // Dark tile grid line
                        else
                            maze_rgb <= 12'h081; // Dark arena green/gray floor
                    end

                    2'b01: begin // Destructible Wall (Brick)
                        maze_wall <= 1'b1;
                        // Brick mortar groove pattern
                        if ((sub_y_d == 5'd0) || (sub_y_d == 5'd12) || 
                            ((sub_y_d < 5'd12) && (sub_x_d == 5'd0)) ||
                            ((sub_y_d >= 5'd12) && (sub_x_d == 5'd12)))
                            maze_rgb <= 12'h444; // Mortar
                        else
                            maze_rgb <= 12'hB52; // Orange-red brick body
                    end

                    2'b10: begin // Indestructible Perimeter / Steel Wall
                        maze_wall <= 1'b1;
                        // Steel plate bevel & rivet border
                        if ((sub_x_d == 5'd0) || (sub_y_d == 5'd0))
                            maze_rgb <= 12'hCCD; // Highlight top-left bevel
                        else if ((sub_x_d == 5'd23) || (sub_y_d == 5'd23))
                            maze_rgb <= 12'h445; // Shadow bottom-right bevel
                        else
                            maze_rgb <= 12'h889; // Solid steel plate body
                    end

                    2'b11: begin // Reinforced / Corner Wall
                        maze_wall <= 1'b1;
                        maze_rgb  <= 12'h668;
                    end
                endcase
            end
        end
    end

endmodule

`endif
