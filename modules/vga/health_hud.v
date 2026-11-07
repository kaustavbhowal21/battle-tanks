`timescale 1ns / 1ps
//=============================================================================
// Fig 12: Health HUD
// 2 rows x 10 Hearts per row in the 160 px HUD strip (x: 480..639)
//
// Hearts are 16px wide x 8px tall, 2 rows stacked:
//   slot = dx[7:4]  (0..9),  px_in_heart = dx[3:0] -> select bit [15-px] of 16px wide rom
//
// P1 Row A: y = 24..31  (hearts  0.. 9)
// P1 Row B: y = 32..39  (hearts 10..19)
// P2 Row A: y = 432..439 (hearts  0.. 9)
// P2 Row B: y = 440..447 (hearts 10..19)
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
    output reg  [11:0] hud_rgb,    // 12-bit HUD color

    // Double-Dabble BCD telemetry outputs
    output wire [7:0]  p1_bcd,
    output wire [7:0]  p2_bcd
);

    // =========================================================================
    // 1. Region & Coordinate Decoding
    // =========================================================================
    wire in_hud_strip = (x >= 10'd480) && (x < 10'd640) && active;
    wire [9:0] dx = x - 10'd480;         // 0..159

    wire [3:0] heart_slot = dx[7:4];     // slot 0..9  (10 hearts per row)
    wire [3:0] px_in_heart = dx[3:0];    // 0..15 (16-px wide heart)

    // P1: two rows stacked; row A = hearts 0..9, row B = hearts 10..19
    wire in_p1_rowA = in_hud_strip && (y >= 10'd24)  && (y <= 10'd31);
    wire in_p1_rowB = in_hud_strip && (y >= 10'd32)  && (y <= 10'd39);
    wire in_p2_rowA = in_hud_strip && (y >= 10'd432) && (y <= 10'd439);
    wire in_p2_rowB = in_hud_strip && (y >= 10'd440) && (y <= 10'd447);
    wire in_p1_row = in_p1_rowA || in_p1_rowB;
    wire in_p2_row = in_p2_rowA || in_p2_rowB;

    // Heart index: slot + 10 for row B
    wire [4:0] heart_idx_p1 = (in_p1_rowB ? 5'd10 : 5'd0) + {1'b0, heart_slot};
    wire [4:0] heart_idx_p2 = (in_p2_rowB ? 5'd10 : 5'd0) + {1'b0, heart_slot};

    wire [2:0] py_in_heart = y[2:0];

    // Header label banners
    wire in_p1_banner = in_hud_strip && (y >= 10'd12)  && (y <= 10'd19)  && (dx >= 10'd4) && (dx <= 10'd80);
    wire in_p2_banner = in_hud_strip && (y >= 10'd420) && (y <= 10'd427) && (dx >= 10'd4) && (dx <= 10'd80);

    // Arena vertical divider bar
    wire in_divider = active && (x == 10'd479 || x == 10'd480);

    // =========================================================================
    // 1b. Hardware Double-Dabble (Shift-and-Add-3) Binary-to-BCD Converter
    //     & 8x8 Digit Character ROM (Zero Dividers, Zero CPU Cycles)
    // =========================================================================
    function [7:0] bin_to_bcd2;
        input [7:0] bin;
        reg [19:0] shift_reg;
        integer s;
        begin
            shift_reg = {12'd0, bin};
            for (s = 0; s < 8; s = s + 1) begin
                if (shift_reg[11:8] >= 4'd5)
                    shift_reg[11:8] = shift_reg[11:8] + 4'd3;
                if (shift_reg[15:12] >= 4'd5)
                    shift_reg[15:12] = shift_reg[15:12] + 4'd3;
                if (shift_reg[19:16] >= 4'd5)
                    shift_reg[19:16] = shift_reg[19:16] + 4'd3;
                shift_reg = shift_reg << 1;
            end
            bin_to_bcd2 = shift_reg[15:8]; // {tens[3:0], ones[3:0]}
        end
    endfunction

    assign p1_bcd = bin_to_bcd2(hp1);
    assign p2_bcd = bin_to_bcd2(hp2);

    // Compact 8x8 Font ROM for decimal digits 0..9 (packed 64-bit glyph per digit)
    function [63:0] digit_glyph;
        input [3:0] d;
        begin
            case (d)
                4'd0: digit_glyph = 64'h3C_66_6E_76_66_66_3C_00;
                4'd1: digit_glyph = 64'h18_38_18_18_18_18_7E_00;
                4'd2: digit_glyph = 64'h3C_66_06_1C_30_60_7E_00;
                4'd3: digit_glyph = 64'h3C_66_06_1C_06_66_3C_00;
                4'd4: digit_glyph = 64'h0C_1C_2C_4C_7E_0C_0C_00;
                4'd5: digit_glyph = 64'h7E_60_7C_06_06_66_3C_00;
                4'd6: digit_glyph = 64'h3C_60_7C_66_66_66_3C_00;
                4'd7: digit_glyph = 64'h7E_06_0C_18_18_18_18_00;
                4'd8: digit_glyph = 64'h3C_66_66_3C_66_66_3C_00;
                4'd9: digit_glyph = 64'h3C_66_66_3E_06_66_3C_00;
                default: digit_glyph = 64'h0000_0000_0000_0000;
            endcase
        end
    endfunction

    wire in_p1_digits = in_hud_strip && (y >= 10'd12)  && (y <= 10'd19)  && (dx >= 10'd88) && (dx <= 10'd103);
    wire in_p2_digits = in_hud_strip && (y >= 10'd420) && (y <= 10'd427) && (dx >= 10'd88) && (dx <= 10'd103);
    wire [9:0] dig_dx = dx - 10'd88;
    wire [2:0] p1_dig_py = y - 10'd12;
    wire [2:0] p2_dig_py = y - 10'd420;
    wire [63:0] p1_glyph = digit_glyph(dig_dx[3] ? p1_bcd[3:0] : p1_bcd[7:4]);
    wire [63:0] p2_glyph = digit_glyph(dig_dx[3] ? p2_bcd[3:0] : p2_bcd[7:4]);
    wire [5:0] p1_bit_idx = {3'd7 - p1_dig_py, 3'd7 - dig_dx[2:0]};
    wire [5:0] p2_bit_idx = {3'd7 - p2_dig_py, 3'd7 - dig_dx[2:0]};
    wire p1_dig_bit = p1_glyph[p1_bit_idx];
    wire p2_dig_bit = p2_glyph[p2_bit_idx];

    // =========================================================================
    // 2. 8-row x 16-px Heart Sprite ROM (each original bit doubled horizontally)
    // =========================================================================
    reg [15:0] rom_row;
    always @(*) begin
        case (py_in_heart)
            3'd0: rom_row = 16'h3C3C; // 8'b01100110 doubled horizontally
            3'd1: rom_row = 16'hFFFF; // 8'b11111111 doubled
            3'd2: rom_row = 16'hFFFF;
            3'd3: rom_row = 16'hFFFF;
            3'd4: rom_row = 16'h3FFC; // 8'b01111110 doubled
            3'd5: rom_row = 16'h0FF0; // 8'b00111100 doubled
            3'd6: rom_row = 16'h03C0; // 8'b00011000 doubled
            3'd7: rom_row = 16'h0000;
        endcase
    end

    wire heart_shape_bit = rom_row[4'd15 - px_in_heart];

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
            rgb_hud = 12'h029; // P1 Blue Banner
        end
        // P1 BCD Numeric Health Readout (Double-Dabble + Character ROM)
        else if (in_p1_digits && p1_dig_bit) begin
            hit_hud = 1'b1;
            rgb_hud = 12'h4CF; // Bright Cyan-White Digits
        end
        // P2 Banner
        else if (in_p2_banner) begin
            hit_hud = 1'b1;
            rgb_hud = 12'h902; // P2 Red Banner
        end
        // P2 BCD Numeric Health Readout (Double-Dabble + Character ROM)
        else if (in_p2_digits && p2_dig_bit) begin
            hit_hud = 1'b1;
            rgb_hud = 12'hFA4; // Bright Orange-Yellow Digits
        end
        // P1 Hearts Row (10 per row, 2 rows)
        else if (in_p1_row && (heart_slot <= 4'd9)) begin
            if (heart_shape_bit) begin
                hit_hud = 1'b1;
                if ({1'b0, heart_idx_p1} < hp1) begin
                    // Full Heart
                    if ((px_in_heart == 4'd4 && py_in_heart == 3'd2) || (px_in_heart == 4'd10 && py_in_heart == 3'd2))
                        rgb_hud = 12'hFFA; // Specular gloss
                    else
                        rgb_hud = 12'hF00; // Crimson Red
                end else begin
                    rgb_hud = 12'h300; // Depleted
                end
            end
        end
        // P2 Hearts Row (10 per row, 2 rows)
        else if (in_p2_row && (heart_slot <= 4'd9)) begin
            if (heart_shape_bit) begin
                hit_hud = 1'b1;
                if ({1'b0, heart_idx_p2} < hp2) begin
                    if ((px_in_heart == 4'd4 && py_in_heart == 3'd2) || (px_in_heart == 4'd10 && py_in_heart == 3'd2))
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