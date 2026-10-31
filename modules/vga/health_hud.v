`timescale 1ns / 1ps
//=============================================================================
// Fig 12: Health HUD
// 2 x 20 Hearts in the 160 px strip to the right of the maze (x: 480..639)
//
// Hearts are 8x8 pixels so:
//   slot = (x - 480) / 8  (pure bit-slice dx[7:3], no divider required)
//   pixel-in-heart = dx[2:0], dy[2:0]
//
// P1 Row: y = 32..39   (Player 1 Health, green/red HUD strip)
// P2 Row: y = 432..439 (Player 2 Health)
//
// 8x8 Heart Sprite ROM determines shape; slot < hp determines full vs empty.
// Registered outputs align with Pixel Priority Mixer (Fig 10).
//=============================================================================
`ifndef HEALTH_HUD_V
`define HEALTH_HUD_V

module health_hud (
    input  wire        clk,        // 50 MHz clk_sys
    input  wire        reset_n,
    input  wire        pix_ce,

    input  wire [9:0]  x,          // 0..639
    input  wire [9:0]  y,          // 0..479
    input  wire        active,

    input  wire [7:0]  hp1,        // P1 live health (0..20)
    input  wire [7:0]  hp2,        // P2 live health (0..20)

    output reg         hud_valid,  // 1 if active HUD pixel
    output reg  [11:0] hud_rgb     // 12-bit HUD color
);

    // =========================================================================
    // 1. Region & Coordinate Decoding
    // =========================================================================
    wire in_hud_strip = (x >= 10'd480) && (x < 10'd640) && active;
    wire [9:0] dx = x - 10'd480;         // 0..159

    wire [4:0] heart_slot = dx[7:3];     // slot 0..19 (pure bit slice!)
    wire [2:0] px_in_heart = dx[2:0];    // 0..7

    wire in_p1_row = in_hud_strip && (y >= 10'd32)  && (y <= 10'd39);
    wire in_p2_row = in_hud_strip && (y >= 10'd432) && (y <= 10'd439);

    wire [2:0] py_in_heart = in_p1_row ? (y[2:0] - 3'd0) : (y[2:0] - 3'd0);

    // Header label banners
    wire in_p1_banner = in_hud_strip && (y >= 10'd20)  && (y <= 10'd27)  && (dx >= 10'd4) && (dx <= 10'd80);
    wire in_p2_banner = in_hud_strip && (y >= 10'd420) && (y <= 10'd427) && (dx >= 10'd4) && (dx <= 10'd80);

    // Arena vertical divider bar
    wire in_divider = active && (x == 10'd479 || x == 10'd480);

    // =========================================================================
    // 2. 8x8 Heart Sprite ROM
    // =========================================================================
    reg [7:0] rom_row;
    always @(*) begin
        case (py_in_heart)
            3'd0: rom_row = 8'b01100110;
            3'd1: rom_row = 8'b11111111;
            3'd2: rom_row = 8'b11111111;
            3'd3: rom_row = 8'b11111111;
            3'd4: rom_row = 8'b01111110;
            3'd5: rom_row = 8'b00111100;
            3'd6: rom_row = 8'b00011000;
            3'd7: rom_row = 8'b00000000;
        endcase
    end

    wire heart_shape_bit = rom_row[3'd7 - px_in_heart];

    // =========================================================================
    // 3. Pixel Selection & Color Output
    // =========================================================================
    reg        hit_hud;
    reg [11:0] rgb_hud;

    always @(*) begin
        hit_hud = 1'b0;
        rgb_hud = 12'h000;

        // Vertical divider
        if (in_divider) begin
            hit_hud = 1'b1;
            rgb_hud = 12'h557; // Steel divider bar
        end
        // P1 Banner
        else if (in_p1_banner) begin
            hit_hud = 1'b1;
            rgb_hud = 12'h092; // P1 Green Banner
        end
        // P2 Banner
        else if (in_p2_banner) begin
            hit_hud = 1'b1;
            rgb_hud = 12'h902; // P2 Red Banner
        end
        // P1 Hearts Row
        else if (in_p1_row && (heart_slot < 5'd20)) begin
            if (heart_shape_bit) begin
                hit_hud = 1'b1;
                if ({3'd0, heart_slot} < hp1) begin
                    // Full Heart (Red with gloss highlight)
                    if ((px_in_heart == 3'd2 && py_in_heart == 3'd2) || (px_in_heart == 3'd5 && py_in_heart == 3'd2))
                        rgb_hud = 12'hFFA; // Specular gloss
                    else
                        rgb_hud = 12'hF00; // Bright Crimson Red
                end else begin
                    // Depleted Heart (Dark Gray/Red outline)
                    rgb_hud = 12'h300;
                end
            end
        end
        // P2 Hearts Row
        else if (in_p2_row && (heart_slot < 5'd20)) begin
            if (heart_shape_bit) begin
                hit_hud = 1'b1;
                if ({3'd0, heart_slot} < hp2) begin
                    if ((px_in_heart == 3'd2 && py_in_heart == 3'd2) || (px_in_heart == 3'd5 && py_in_heart == 3'd2))
                        rgb_hud = 12'hFFA;
                    else
                        rgb_hud = 12'hF00;
                end else begin
                    rgb_hud = 12'h300;
                end
            end
        end
    end

    // Register outputs to mixer
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            hud_valid <= 1'b0;
            hud_rgb   <= 12'h000;
        end else begin
            hud_valid <= hit_hud;
            hud_rgb   <= rgb_hud;
        end
    end

endmodule

`endif
