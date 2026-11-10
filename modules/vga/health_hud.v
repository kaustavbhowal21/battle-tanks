`timescale 1ns / 1ps
//=============================================================================
// Fig 12: Health HUD & Controller Telemetry Display
// 160 px HUD strip (x: 480..639)
//
// 1. Player 1 & 2 Health: 2 rows x 10 Hearts per row
//    P1 Row A: y = 24..31  (hearts  0.. 9)
//    P1 Row B: y = 32..39  (hearts 10..19)
//    P2 Row A: y = 432..439 (hearts  0.. 9)
//    P2 Row B: y = 440..447 (hearts 10..19)
//
// 2. Special Attack Cooldown Bars (100 px wide, 0..10s reload time)
//    P1 Bar: y = 58..71, dx = 28..131 (Electric Cyan)
//    P2 Bar: y = 394..407, dx = 28..131 (Amber Gold)
//
// 3. In-Game Keyboard Controls Display:
//    - Real keycap icons matching inverted-T layout (WASD and Arrows)
//    - Action keycaps: SPACE, E, ENTER, SHIFT, ESC
//    - Clean aligned labels for STEER/MOVE, SHOOT, SPECIAL ATTACK, and RESET
//    - Active key illumination when buttons are pressed on the keyboard
//=============================================================================
`ifndef HEALTH_HUD_V
`define HEALTH_HUD_V

module health_hud (
    input  wire        clk,         // 50 MHz clk_sys
    input  wire        reset_n,
    input  wire        pix_ce,

    input  wire [9:0]  x,           // 0..639
    input  wire [9:0]  y,           // 0..479
    input  wire        active,

    input  wire [7:0]  hp1,         // P1 live health (0..20)
    input  wire [7:0]  hp2,         // P2 live health (0..20)
    input  wire [6:0]  bar_p1_spec, // P1 special cooldown bar fill (0..100)
    input  wire [6:0]  bar_p2_spec, // P2 special cooldown bar fill (0..100)
    input  wire [5:0]  p1_keys,     // [0]=FWD, [1]=BWD, [2]=L, [3]=R, [4]=SHOOT, [5]=SPEC
    input  wire [5:0]  p2_keys,     // [0]=FWD, [1]=BWD, [2]=L, [3]=R, [4]=SHOOT, [5]=SPEC

    output reg         hud_valid,   // 1 if active HUD pixel
    output reg  [11:0] hud_rgb,     // 12-bit HUD color

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
    wire in_p1_row  = in_p1_rowA || in_p1_rowB;
    wire in_p2_row  = in_p2_rowA || in_p2_rowB;

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
    // 2. Hardware Double-Dabble (Shift-and-Add-3) Binary-to-BCD Converter
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

    // =========================================================================
    // 3. Compact 8x8 Font ROM for Alphanumerics & Keyboard Symbols
    // =========================================================================
    function [63:0] char_glyph;
        input [7:0] ch;
        begin
            case (ch)
                // Decimal digits 0..9
                "0": char_glyph = 64'h3C_66_6E_76_66_66_3C_00;
                "1": char_glyph = 64'h18_38_18_18_18_18_7E_00;
                "2": char_glyph = 64'h3C_66_06_1C_30_60_7E_00;
                "3": char_glyph = 64'h3C_66_06_1C_06_66_3C_00;
                "4": char_glyph = 64'h0C_1C_2C_4C_7E_0C_0C_00;
                "5": char_glyph = 64'h7E_60_7C_06_06_66_3C_00;
                "6": char_glyph = 64'h3C_60_7C_66_66_66_3C_00;
                "7": char_glyph = 64'h7E_06_0C_18_18_18_18_00;
                "8": char_glyph = 64'h3C_66_66_3C_66_66_3C_00;
                "9": char_glyph = 64'h3C_66_66_3E_06_66_3C_00;

                // Letters
                "A": char_glyph = 64'h3C_66_66_7E_66_66_66_00;
                "B": char_glyph = 64'h7C_66_66_7C_66_66_7C_00;
                "C": char_glyph = 64'h3C_66_60_60_60_66_3C_00;
                "D": char_glyph = 64'h78_6C_66_66_66_6C_78_00;
                "E": char_glyph = 64'h7E_60_60_7C_60_60_7E_00;
                "F": char_glyph = 64'h7E_60_60_7C_60_60_60_00;
                "G": char_glyph = 64'h3C_66_60_6E_66_66_3C_00;
                "H": char_glyph = 64'h66_66_66_7E_66_66_66_00;
                "I": char_glyph = 64'h7E_18_18_18_18_18_7E_00;
                "K": char_glyph = 64'h66_6C_78_70_78_6C_66_00;
                "L": char_glyph = 64'h60_60_60_60_60_60_7E_00;
                "M": char_glyph = 64'h63_77_7F_6B_63_63_63_00;
                "N": char_glyph = 64'h66_76_7E_7E_6E_66_66_00;
                "O": char_glyph = 64'h3C_66_66_66_66_66_3C_00;
                "P": char_glyph = 64'h7C_66_66_7C_60_60_60_00;
                "R": char_glyph = 64'h7C_66_66_7C_78_6C_66_00;
                "S": char_glyph = 64'h3C_66_60_3C_06_66_3C_00;
                "T": char_glyph = 64'h7E_18_18_18_18_18_18_00;
                "U": char_glyph = 64'h66_66_66_66_66_66_3C_00;
                "V": char_glyph = 64'h66_66_66_66_66_3C_18_00;
                "W": char_glyph = 64'h63_63_63_6B_7F_77_63_00;
                "Y": char_glyph = 64'h66_66_66_3C_18_18_18_00;

                // Symbols & Punctuation
                "/": char_glyph = 64'h06_0C_18_30_60_40_00_00;
                ":": char_glyph = 64'h00_18_18_00_18_18_00_00;
                "-": char_glyph = 64'h00_00_00_7E_00_00_00_00;

                // Arrow Glyphs (matching user design)
                8'h01: char_glyph = 64'h18_3C_7E_18_18_18_18_00; // Up Arrow    ↑
                8'h02: char_glyph = 64'h18_18_18_18_7E_3C_18_00; // Down Arrow  ↓
                8'h03: char_glyph = 64'h10_30_7E_FF_7E_30_10_00; // Left Arrow  ←
                8'h04: char_glyph = 64'h08_0C_7E_FF_7E_0C_08_00; // Right Arrow →

                default: char_glyph = 64'h00_00_00_00_00_00_00_00;
            endcase
        end
    endfunction

    // Health BCD Digits Display (y = 12..19 for P1, y = 420..427 for P2)
    wire in_p1_digits = in_hud_strip && (y >= 10'd12)  && (y <= 10'd19)  && (dx >= 10'd88) && (dx <= 10'd103);
    wire in_p2_digits = in_hud_strip && (y >= 10'd420) && (y <= 10'd427) && (dx >= 10'd88) && (dx <= 10'd103);
    wire [9:0] dig_dx = dx - 10'd88;
    wire [2:0] p1_dig_py = y - 10'd12;
    wire [2:0] p2_dig_py = y - 10'd420;
    wire [63:0] p1_glyph = char_glyph(dig_dx[3] ? ("0" + p1_bcd[3:0]) : ("0" + p1_bcd[7:4]));
    wire [63:0] p2_glyph = char_glyph(dig_dx[3] ? ("0" + p2_bcd[3:0]) : ("0" + p2_bcd[7:4]));
    wire [5:0] p1_bit_idx = {3'd7 - p1_dig_py, 3'd7 - dig_dx[2:0]};
    wire [5:0] p2_bit_idx = {3'd7 - p2_dig_py, 3'd7 - dig_dx[2:0]};
    wire p1_dig_bit = p1_glyph[p1_bit_idx];
    wire p2_dig_bit = p2_glyph[p2_bit_idx];

    // =========================================================================
    // 4. Special Attack Cooldown Bars (0..10 s, 100 px wide fill)
    // =========================================================================
    // P1 Special Cooldown Bar: y = 58..71, dx = 28..131 (inner cavity: y = 60..69, dx = 30..129)
    wire in_p1_bar_box    = in_hud_strip && (y >= 10'd58) && (y <= 10'd71) && (dx >= 10'd28) && (dx <= 10'd131);
    wire in_p1_bar_border = in_p1_bar_box && (dx <= 10'd29 || dx >= 10'd130 || y <= 10'd59 || y >= 10'd70);
    wire [6:0] p1_bar_px  = dx - 10'd30;
    wire in_p1_bar_fill   = in_p1_bar_box && !in_p1_bar_border && (p1_bar_px < bar_p1_spec);
    wire in_p1_bar_empty  = in_p1_bar_box && !in_p1_bar_border && (p1_bar_px >= bar_p1_spec);

    // P1 Special Banner & Digits: y = 48..55
    wire in_p1_spec_banner = in_hud_strip && (y >= 10'd48) && (y <= 10'd55) && (dx >= 10'd4) && (dx <= 10'd80);
    wire in_p1_spec_digits = in_hud_strip && (y >= 10'd48) && (y <= 10'd55) && (dx >= 10'd88) && (dx <= 10'd103);

    // P2 Special Banner & Digits: y = 384..391
    wire in_p2_spec_banner = in_hud_strip && (y >= 10'd384) && (y <= 10'd391) && (dx >= 10'd4) && (dx <= 10'd80);
    wire in_p2_spec_digits = in_hud_strip && (y >= 10'd384) && (y <= 10'd391) && (dx >= 10'd88) && (dx <= 10'd103);

    // P2 Special Cooldown Bar: y = 394..407, dx = 28..131 (inner cavity: y = 396..405, dx = 30..129)
    wire in_p2_bar_box    = in_hud_strip && (y >= 10'd394) && (y <= 10'd407) && (dx >= 10'd28) && (dx <= 10'd131);
    wire in_p2_bar_border = in_p2_bar_box && (dx <= 10'd29 || dx >= 10'd130 || y <= 10'd395 || y >= 10'd406);
    wire [6:0] p2_bar_px  = dx - 10'd30;
    wire in_p2_bar_fill   = in_p2_bar_box && !in_p2_bar_border && (p2_bar_px < bar_p2_spec);
    wire in_p2_bar_empty  = in_p2_bar_box && !in_p2_bar_border && (p2_bar_px >= bar_p2_spec);

    // Special cooldown second counters (0..10) for numeric telemetry
    wire [3:0] sec_p1 = (bar_p1_spec >= 7'd100) ? 4'd10 :
                        (bar_p1_spec >= 7'd90)  ? 4'd9  :
                        (bar_p1_spec >= 7'd80)  ? 4'd8  :
                        (bar_p1_spec >= 7'd70)  ? 4'd7  :
                        (bar_p1_spec >= 7'd60)  ? 4'd6  :
                        (bar_p1_spec >= 7'd50)  ? 4'd5  :
                        (bar_p1_spec >= 7'd40)  ? 4'd4  :
                        (bar_p1_spec >= 7'd30)  ? 4'd3  :
                        (bar_p1_spec >= 7'd20)  ? 4'd2  :
                        (bar_p1_spec >= 7'd10)  ? 4'd1  : 4'd0;
    wire [7:0] sec_p1_tens_char = (sec_p1 == 4'd10) ? "1" : "0";
    wire [7:0] sec_p1_ones_char = (sec_p1 == 4'd10) ? "0" : ("0" + sec_p1);

    wire [3:0] sec_p2 = (bar_p2_spec >= 7'd100) ? 4'd10 :
                        (bar_p2_spec >= 7'd90)  ? 4'd9  :
                        (bar_p2_spec >= 7'd80)  ? 4'd8  :
                        (bar_p2_spec >= 7'd70)  ? 4'd7  :
                        (bar_p2_spec >= 7'd60)  ? 4'd6  :
                        (bar_p2_spec >= 7'd50)  ? 4'd5  :
                        (bar_p2_spec >= 7'd40)  ? 4'd4  :
                        (bar_p2_spec >= 7'd30)  ? 4'd3  :
                        (bar_p2_spec >= 7'd20)  ? 4'd2  :
                        (bar_p2_spec >= 7'd10)  ? 4'd1  : 4'd0;
    wire [7:0] sec_p2_tens_char = (sec_p2 == 4'd10) ? "1" : "0";
    wire [7:0] sec_p2_ones_char = (sec_p2 == 4'd10) ? "0" : ("0" + sec_p2);

    wire [2:0] p1_sdig_py = y - 10'd48;
    wire [2:0] p2_sdig_py = y - 10'd384;
    wire [63:0] p1_s_glyph = char_glyph(dig_dx[3] ? sec_p1_ones_char : sec_p1_tens_char);
    wire [63:0] p2_s_glyph = char_glyph(dig_dx[3] ? sec_p2_ones_char : sec_p2_tens_char);
    wire [5:0] p1_sbit_idx = {3'd7 - p1_sdig_py, 3'd7 - dig_dx[2:0]};
    wire [5:0] p2_sbit_idx = {3'd7 - p2_sdig_py, 3'd7 - dig_dx[2:0]};
    wire p1_sdig_bit = p1_s_glyph[p1_sbit_idx];
    wire p2_sdig_bit = p2_s_glyph[p2_sbit_idx];

    // =========================================================================
    // 5. 8-row x 16-px Heart Sprite ROM
    // =========================================================================
    reg [15:0] rom_row;
    always @(*) begin
        case (py_in_heart)
            3'd0: rom_row = 16'h3C3C;
            3'd1: rom_row = 16'hFFFF;
            3'd2: rom_row = 16'hFFFF;
            3'd3: rom_row = 16'hFFFF;
            3'd4: rom_row = 16'h3FFC;
            3'd5: rom_row = 16'h0FF0;
            3'd6: rom_row = 16'h03C0;
            3'd7: rom_row = 16'h0000;
        endcase
    end
    wire heart_shape_bit = rom_row[4'd15 - px_in_heart];

    // =========================================================================
    // 6. On-Screen Keyboard Controls Display Subsystem
    //    Renders Keycaps [W],[A],[S],[D] & [↑],[←],[↓],[→] matching the image!
    //    Also renders Action Keys [SPACE], [E], [ENTER], [SHIFT], [ESC]
    // =========================================================================

    // Text String Helpers
    function [7:0] p1_ctrl_char;
        input [3:0] idx;
        begin
            case (idx)
                4'd0:  p1_ctrl_char = "P";
                4'd1:  p1_ctrl_char = "1";
                4'd2:  p1_ctrl_char = " ";
                4'd3:  p1_ctrl_char = "C";
                4'd4:  p1_ctrl_char = "O";
                4'd5:  p1_ctrl_char = "N";
                4'd6:  p1_ctrl_char = "T";
                4'd7:  p1_ctrl_char = "R";
                4'd8:  p1_ctrl_char = "O";
                4'd9:  p1_ctrl_char = "L";
                4'd10: p1_ctrl_char = "S";
                default: p1_ctrl_char = " ";
            endcase
        end
    endfunction

    function [7:0] p2_ctrl_char;
        input [3:0] idx;
        begin
            case (idx)
                4'd0:  p2_ctrl_char = "P";
                4'd1:  p2_ctrl_char = "2";
                4'd2:  p2_ctrl_char = " ";
                4'd3:  p2_ctrl_char = "C";
                4'd4:  p2_ctrl_char = "O";
                4'd5:  p2_ctrl_char = "N";
                4'd6:  p2_ctrl_char = "T";
                4'd7:  p2_ctrl_char = "R";
                4'd8:  p2_ctrl_char = "O";
                4'd9:  p2_ctrl_char = "L";
                4'd10: p2_ctrl_char = "S";
                default: p2_ctrl_char = " ";
            endcase
        end
    endfunction

    function [7:0] sys_ctrl_char;
        input [2:0] idx;
        begin
            case (idx)
                3'd0: sys_ctrl_char = "S";
                3'd1: sys_ctrl_char = "Y";
                3'd2: sys_ctrl_char = "S";
                3'd3: sys_ctrl_char = "T";
                3'd4: sys_ctrl_char = "E";
                3'd5: sys_ctrl_char = "M";
                default: sys_ctrl_char = " ";
            endcase
        end
    endfunction

    function [7:0] move_char;
        input [2:0] idx;
        begin
            case (idx)
                3'd0: move_char = "M";
                3'd1: move_char = "O";
                3'd2: move_char = "V";
                3'd3: move_char = "E";
                3'd4: move_char = "/";
                3'd5: move_char = "A";
                3'd6: move_char = "I";
                3'd7: move_char = "M";
            endcase
        end
    endfunction

    function [7:0] shoot_char;
        input [2:0] idx;
        begin
            case (idx)
                3'd0: shoot_char = "S";
                3'd1: shoot_char = "H";
                3'd2: shoot_char = "O";
                3'd3: shoot_char = "O";
                3'd4: shoot_char = "T";
                default: shoot_char = " ";
            endcase
        end
    endfunction

    function [7:0] spec_char;
        input [2:0] idx;
        begin
            case (idx)
                3'd0: spec_char = "S";
                3'd1: spec_char = "P";
                3'd2: spec_char = "E";
                3'd3: spec_char = "C";
                3'd4: spec_char = "I";
                3'd5: spec_char = "A";
                3'd6: spec_char = "L";
                default: spec_char = " ";
            endcase
        end
    endfunction

    function [7:0] reset_char;
        input [2:0] idx;
        begin
            case (idx)
                3'd0: reset_char = "R";
                3'd1: reset_char = "E";
                3'd2: reset_char = "S";
                3'd3: reset_char = "E";
                3'd4: reset_char = "T";
                default: reset_char = " ";
            endcase
        end
    endfunction

    function [7:0] space_key_char;
        input [2:0] idx;
        begin
            case (idx)
                3'd0: space_key_char = "S";
                3'd1: space_key_char = "P";
                3'd2: space_key_char = "A";
                3'd3: space_key_char = "C";
                3'd4: space_key_char = "E";
                default: space_key_char = " ";
            endcase
        end
    endfunction

    function [7:0] enter_key_char;
        input [2:0] idx;
        begin
            case (idx)
                3'd0: enter_key_char = "E";
                3'd1: enter_key_char = "N";
                3'd2: enter_key_char = "T";
                3'd3: enter_key_char = "E";
                3'd4: enter_key_char = "R";
                default: enter_key_char = " ";
            endcase
        end
    endfunction

    function [7:0] shift_key_char;
        input [2:0] idx;
        begin
            case (idx)
                3'd0: shift_key_char = "S";
                3'd1: shift_key_char = "H";
                3'd2: shift_key_char = "I";
                3'd3: shift_key_char = "F";
                3'd4: shift_key_char = "T";
                default: shift_key_char = " ";
            endcase
        end
    endfunction

    function [7:0] esc_key_char;
        input [1:0] idx;
        begin
            case (idx)
                2'd0: esc_key_char = "E";
                2'd1: esc_key_char = "S";
                2'd2: esc_key_char = "C";
                default: esc_key_char = " ";
            endcase
        end
    endfunction

    // 14x14 Keycap Pixel Sampler: returns {is_hit, is_border, is_glyph}
    function [2:0] keycap14_sample;
        input [9:0] cur_x, cur_y;
        input [9:0] box_x, box_y;
        input [7:0] symbol_char;
        reg [3:0] u, v;
        reg is_corner, is_border, in_glyph, gbit;
        reg [63:0] g;
        begin
            if ((cur_x >= box_x) && (cur_x < box_x + 10'd14) &&
                (cur_y >= box_y) && (cur_y < box_y + 10'd14)) begin
                u = cur_x - box_x;
                v = cur_y - box_y;
                is_corner = (u == 4'd0 || u == 4'd13) && (v == 4'd0 || v == 4'd13);
                if (is_corner) begin
                    keycap14_sample = 3'b000;
                end else begin
                    is_border = (u == 4'd0 || u == 4'd13 || v == 4'd0 || v == 4'd13);
                    in_glyph  = (u >= 4'd3 && u <= 4'd10 && v >= 4'd3 && v <= 4'd10);
                    g = char_glyph(symbol_char);
                    gbit = in_glyph && g[{3'd7 - (v[2:0] - 3'd3), 3'd7 - (u[2:0] - 3'd3)}];
                    keycap14_sample = {1'b1, is_border, gbit};
                end
            end else begin
                keycap14_sample = 3'b000;
            end
        end
    endfunction

    // Multi-Character Keycap Pixel Sampler (SPACE, ENTER, SHIFT, ESC)
    function [2:0] keycap_multi_sample;
        input [9:0] cur_x, cur_y;
        input [9:0] box_x, box_y;
        input [5:0] box_w; // 46 or 32
        input [1:0] key_type; // 0=SPACE, 1=ENTER, 2=SHIFT, 3=ESC
        reg [5:0] u;
        reg [3:0] v;
        reg is_corner, is_border, in_text, gbit;
        reg [2:0] ch_idx;
        reg [7:0] ch;
        reg [63:0] g;
        begin
            if ((cur_x >= box_x) && (cur_x < box_x + {4'd0, box_w}) &&
                (cur_y >= box_y) && (cur_y < box_y + 10'd14)) begin
                u = cur_x - box_x;
                v = cur_y - box_y;
                is_corner = (u == 6'd0 || u == box_w - 6'd1) && (v == 4'd0 || v == 4'd13);
                if (is_corner) begin
                    keycap_multi_sample = 3'b000;
                end else begin
                    is_border = (u == 6'd0 || u == box_w - 6'd1 || v == 4'd0 || v == 4'd13);
                    if (box_w == 6'd46) begin
                        // 5 characters centered at u in 3..42, v in 3..10
                        in_text = (u >= 6'd3 && u <= 6'd42 && v >= 4'd3 && v <= 4'd10);
                        ch_idx = (u - 6'd3) >> 3;
                        case (key_type)
                            2'd0: ch = space_key_char(ch_idx);
                            2'd1: ch = enter_key_char(ch_idx);
                            default: ch = shift_key_char(ch_idx);
                        endcase
                        g = char_glyph(ch);
                        gbit = in_text && g[{3'd7 - (v[2:0] - 3'd3), 3'd7 - ((u - 6'd3) & 6'd7)}];
                    end else begin
                        // 3 characters (ESC) centered at u in 4..27, v in 3..10
                        in_text = (u >= 6'd4 && u <= 6'd27 && v >= 4'd3 && v <= 4'd10);
                        ch_idx = (u - 6'd4) >> 3;
                        ch = esc_key_char(ch_idx[1:0]);
                        g = char_glyph(ch);
                        gbit = in_text && g[{3'd7 - (v[2:0] - 3'd3), 3'd7 - ((u - 6'd4) & 6'd7)}];
                    end
                    keycap_multi_sample = {1'b1, is_border, gbit};
                end
            end else begin
                keycap_multi_sample = 3'b000;
            end
        end
    endfunction

    // Text Label Sampler at Column dx = 66
    function text_sample;
        input [9:0] cur_x, cur_y;
        input [9:0] box_x, box_y;
        input [3:0] len;
        input [1:0] text_id; // 0=MOVE/AIM, 1=SHOOT, 2=SPECIAL, 3=RESET
        reg [6:0] u;
        reg [2:0] v;
        reg [3:0] ch_idx;
        reg [7:0] ch;
        reg [63:0] g;
        begin
            if ((cur_x >= box_x) && (cur_x < box_x + {3'd0, len, 3'd0}) &&
                (cur_y >= box_y) && (cur_y < box_y + 10'd8)) begin
                u = cur_x - box_x;
                v = cur_y - box_y;
                ch_idx = u[6:3];
                case (text_id)
                    2'd0: ch = move_char(ch_idx[2:0]);
                    2'd1: ch = shoot_char(ch_idx[2:0]);
                    2'd2: ch = spec_char(ch_idx[2:0]);
                    2'd3: ch = reset_char(ch_idx[2:0]);
                endcase
                g = char_glyph(ch);
                text_sample = g[{3'd7 - v, 3'd7 - u[2:0]}];
            end else begin
                text_sample = 1'b0;
            end
        end
    endfunction

    // Keycap Sample Instances
    wire [2:0] samp_w    = in_hud_strip ? keycap14_sample(dx, y, 10'd28, 10'd94,  "W")   : 3'b000;
    wire [2:0] samp_a    = in_hud_strip ? keycap14_sample(dx, y, 10'd12, 10'd110, "A")   : 3'b000;
    wire [2:0] samp_s    = in_hud_strip ? keycap14_sample(dx, y, 10'd28, 10'd110, "S")   : 3'b000;
    wire [2:0] samp_d    = in_hud_strip ? keycap14_sample(dx, y, 10'd44, 10'd110, "D")   : 3'b000;
    wire [2:0] samp_e    = in_hud_strip ? keycap14_sample(dx, y, 10'd28, 10'd146, "E")   : 3'b000;
    wire [2:0] samp_spc  = in_hud_strip ? keycap_multi_sample(dx, y, 10'd12, 10'd128, 6'd46, 2'd0) : 3'b000;

    wire [2:0] samp_esc  = in_hud_strip ? keycap_multi_sample(dx, y, 10'd16, 10'd192, 6'd32, 2'd3) : 3'b000;

    wire [2:0] samp_up   = in_hud_strip ? keycap14_sample(dx, y, 10'd28, 10'd244, 8'h01) : 3'b000;
    wire [2:0] samp_left = in_hud_strip ? keycap14_sample(dx, y, 10'd12, 10'd260, 8'h03) : 3'b000;
    wire [2:0] samp_down = in_hud_strip ? keycap14_sample(dx, y, 10'd28, 10'd260, 8'h02) : 3'b000;
    wire [2:0] samp_rght = in_hud_strip ? keycap14_sample(dx, y, 10'd44, 10'd260, 8'h04) : 3'b000;
    wire [2:0] samp_ent  = in_hud_strip ? keycap_multi_sample(dx, y, 10'd12, 10'd278, 6'd46, 2'd1) : 3'b000;
    wire [2:0] samp_shf  = in_hud_strip ? keycap_multi_sample(dx, y, 10'd12, 10'd296, 6'd46, 2'd2) : 3'b000;

    // Text Label Instances
    wire bit_p1_move = in_hud_strip && text_sample(dx, y, 10'd66, 10'd105, 4'd8, 2'd0);
    wire bit_p1_shot = in_hud_strip && text_sample(dx, y, 10'd66, 10'd131, 4'd5, 2'd1);
    wire bit_p1_spec = in_hud_strip && text_sample(dx, y, 10'd66, 10'd149, 4'd7, 2'd2);
    wire bit_sys_rst = in_hud_strip && text_sample(dx, y, 10'd66, 10'd195, 4'd5, 2'd3);
    wire bit_p2_move = in_hud_strip && text_sample(dx, y, 10'd66, 10'd255, 4'd8, 2'd0);
    wire bit_p2_shot = in_hud_strip && text_sample(dx, y, 10'd66, 10'd281, 4'd5, 2'd1);
    wire bit_p2_spec = in_hud_strip && text_sample(dx, y, 10'd66, 10'd299, 4'd7, 2'd2);

    // Section Header Banners
    wire in_p1_hdr  = in_hud_strip && (y >= 10'd80)  && (y <= 10'd87)  && (dx >= 10'd8) && (dx <= 10'd151);
    wire in_sys_hdr = in_hud_strip && (y >= 10'd180) && (y <= 10'd187) && (dx >= 10'd8) && (dx <= 10'd151);
    wire in_p2_hdr  = in_hud_strip && (y >= 10'd230) && (y <= 10'd237) && (dx >= 10'd8) && (dx <= 10'd151);

    wire [9:0] p1_h_dx = dx - 10'd36;
    wire [63:0] p1_h_g = char_glyph(p1_ctrl_char(p1_h_dx[6:3]));
    wire p1_hdr_bit = in_p1_hdr && (dx >= 10'd36 && dx <= 10'd123) && p1_h_g[{3'd7 - (y[2:0] - 3'd0), 3'd7 - p1_h_dx[2:0]}];

    wire [9:0] sys_h_dx = dx - 10'd56;
    wire [63:0] sys_h_g = char_glyph(sys_ctrl_char(sys_h_dx[5:3]));
    wire sys_hdr_bit = in_sys_hdr && (dx >= 10'd56 && dx <= 10'd103) && sys_h_g[{3'd7 - (y[2:0] - 3'd0), 3'd7 - sys_h_dx[2:0]}];

    wire [9:0] p2_h_dx = dx - 10'd36;
    wire [63:0] p2_h_g = char_glyph(p2_ctrl_char(p2_h_dx[6:3]));
    wire p2_hdr_bit = in_p2_hdr && (dx >= 10'd36 && dx <= 10'd123) && p2_h_g[{3'd7 - (y[2:0] - 3'd6), 3'd7 - p2_h_dx[2:0]}];

    // =========================================================================
    // 7. Master Priority Pixel Multiplexer
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
        // P1 Banner & Health Digits
        else if (in_p1_banner) begin
            hit_hud = 1'b1;
            rgb_hud = 12'h029; // P1 Blue Banner
        end
        else if (in_p1_digits && p1_dig_bit) begin
            hit_hud = 1'b1;
            rgb_hud = 12'h4CF; // Bright Cyan-White Digits
        end
        // P2 Banner & Health Digits
        else if (in_p2_banner) begin
            hit_hud = 1'b1;
            rgb_hud = 12'h902; // P2 Red Banner
        end
        else if (in_p2_digits && p2_dig_bit) begin
            hit_hud = 1'b1;
            rgb_hud = 12'hFA4; // Bright Orange-Yellow Digits
        end

        // Special Attack Cooldown Displays
        else if (in_p1_spec_banner) begin
            hit_hud = 1'b1;
            rgb_hud = 12'h026;
        end
        else if (in_p1_spec_digits && p1_sdig_bit) begin
            hit_hud = 1'b1;
            rgb_hud = (bar_p1_spec >= 7'd100) ? 12'h4FF : 12'h19E;
        end
        else if (in_p1_bar_border) begin
            hit_hud = 1'b1;
            rgb_hud = 12'h357;
        end
        else if (in_p1_bar_fill) begin
            hit_hud = 1'b1;
            if (bar_p1_spec >= 7'd100)
                rgb_hud = (y == 10'd60 || y == 10'd61) ? 12'hEFF : 12'h0DE;
            else
                rgb_hud = (y == 10'd60) ? 12'h3BF : 12'h07B;
        end
        else if (in_p1_bar_empty) begin
            hit_hud = 1'b1;
            rgb_hud = 12'h012;
        end

        else if (in_p2_spec_banner) begin
            hit_hud = 1'b1;
            rgb_hud = 12'h620;
        end
        else if (in_p2_spec_digits && p2_sdig_bit) begin
            hit_hud = 1'b1;
            rgb_hud = (bar_p2_spec >= 7'd100) ? 12'hFF4 : 12'hE81;
        end
        else if (in_p2_bar_border) begin
            hit_hud = 1'b1;
            rgb_hud = 12'h743;
        end
        else if (in_p2_bar_fill) begin
            hit_hud = 1'b1;
            if (bar_p2_spec >= 7'd100)
                rgb_hud = (y == 10'd396 || y == 10'd397) ? 12'hFFE : 12'hFA0;
            else
                rgb_hud = (y == 10'd396) ? 12'hFB6 : 12'hC50;
        end
        else if (in_p2_bar_empty) begin
            hit_hud = 1'b1;
            rgb_hud = 12'h210;
        end

        // Hearts Rows
        else if (in_p1_row && (heart_slot <= 4'd9)) begin
            if (heart_shape_bit) begin
                hit_hud = 1'b1;
                if ({1'b0, heart_idx_p1} < hp1) begin
                    if ((px_in_heart == 4'd4 && py_in_heart == 3'd2) || (px_in_heart == 4'd10 && py_in_heart == 3'd2))
                        rgb_hud = 12'hFFA;
                    else
                        rgb_hud = 12'hF00;
                end else begin
                    rgb_hud = 12'h300;
                end
            end
        end
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

        // --- P1 Header Banner ---
        else if (in_p1_hdr) begin
            hit_hud = 1'b1;
            rgb_hud = p1_hdr_bit ? 12'h5DF : 12'h014;
        end
        // --- P1 Keycaps ---
        else if (samp_w[2]) begin
            hit_hud = 1'b1;
            rgb_hud = samp_w[0] ? 12'hFFF : (samp_w[1] ? (p1_keys[0] ? 12'h5DF : 12'h88A) : (p1_keys[0] ? 12'h037 : 12'h223));
        end
        else if (samp_a[2]) begin
            hit_hud = 1'b1;
            rgb_hud = samp_a[0] ? 12'hFFF : (samp_a[1] ? (p1_keys[2] ? 12'h5DF : 12'h88A) : (p1_keys[2] ? 12'h037 : 12'h223));
        end
        else if (samp_s[2]) begin
            hit_hud = 1'b1;
            rgb_hud = samp_s[0] ? 12'hFFF : (samp_s[1] ? (p1_keys[1] ? 12'h5DF : 12'h88A) : (p1_keys[1] ? 12'h037 : 12'h223));
        end
        else if (samp_d[2]) begin
            hit_hud = 1'b1;
            rgb_hud = samp_d[0] ? 12'hFFF : (samp_d[1] ? (p1_keys[3] ? 12'h5DF : 12'h88A) : (p1_keys[3] ? 12'h037 : 12'h223));
        end
        else if (samp_spc[2]) begin
            hit_hud = 1'b1;
            rgb_hud = samp_spc[0] ? 12'hFFF : (samp_spc[1] ? (p1_keys[4] ? 12'h5DF : 12'h88A) : (p1_keys[4] ? 12'h037 : 12'h223));
        end
        else if (samp_e[2]) begin
            hit_hud = 1'b1;
            rgb_hud = samp_e[0] ? 12'hFFF : (samp_e[1] ? (p1_keys[5] ? 12'h5DF : 12'h88A) : (p1_keys[5] ? 12'h037 : 12'h223));
        end
        // --- P1 Labels ---
        else if (bit_p1_move) begin
            hit_hud = 1'b1;
            rgb_hud = 12'h8EF;
        end
        else if (bit_p1_shot) begin
            hit_hud = 1'b1;
            rgb_hud = 12'hFFE;
        end
        else if (bit_p1_spec) begin
            hit_hud = 1'b1;
            rgb_hud = 12'h0FF;
        end

        // --- System Reset Section ---
        else if (in_sys_hdr) begin
            hit_hud = 1'b1;
            rgb_hud = sys_hdr_bit ? 12'hFFF : 12'h223;
        end
        else if (samp_esc[2]) begin
            hit_hud = 1'b1;
            rgb_hud = samp_esc[0] ? 12'hFFF : (samp_esc[1] ? 12'h88A : 12'h223);
        end
        else if (bit_sys_rst) begin
            hit_hud = 1'b1;
            rgb_hud = 12'hF88;
        end

        // --- P2 Header Banner ---
        else if (in_p2_hdr) begin
            hit_hud = 1'b1;
            rgb_hud = p2_hdr_bit ? 12'hFB4 : 12'h410;
        end
        // --- P2 Keycaps ---
        else if (samp_up[2]) begin
            hit_hud = 1'b1;
            rgb_hud = samp_up[0] ? 12'hFFF : (samp_up[1] ? (p2_keys[0] ? 12'hFB4 : 12'h88A) : (p2_keys[0] ? 12'h520 : 12'h223));
        end
        else if (samp_left[2]) begin
            hit_hud = 1'b1;
            rgb_hud = samp_left[0] ? 12'hFFF : (samp_left[1] ? (p2_keys[2] ? 12'hFB4 : 12'h88A) : (p2_keys[2] ? 12'h520 : 12'h223));
        end
        else if (samp_down[2]) begin
            hit_hud = 1'b1;
            rgb_hud = samp_down[0] ? 12'hFFF : (samp_down[1] ? (p2_keys[1] ? 12'hFB4 : 12'h88A) : (p2_keys[1] ? 12'h520 : 12'h223));
        end
        else if (samp_rght[2]) begin
            hit_hud = 1'b1;
            rgb_hud = samp_rght[0] ? 12'hFFF : (samp_rght[1] ? (p2_keys[3] ? 12'hFB4 : 12'h88A) : (p2_keys[3] ? 12'h520 : 12'h223));
        end
        else if (samp_ent[2]) begin
            hit_hud = 1'b1;
            rgb_hud = samp_ent[0] ? 12'hFFF : (samp_ent[1] ? (p2_keys[4] ? 12'hFB4 : 12'h88A) : (p2_keys[4] ? 12'h520 : 12'h223));
        end
        else if (samp_shf[2]) begin
            hit_hud = 1'b1;
            rgb_hud = samp_shf[0] ? 12'hFFF : (samp_shf[1] ? (p2_keys[5] ? 12'hFB4 : 12'h88A) : (p2_keys[5] ? 12'h520 : 12'h223));
        end
        // --- P2 Labels ---
        else if (bit_p2_move) begin
            hit_hud = 1'b1;
            rgb_hud = 12'hFCA;
        end
        else if (bit_p2_shot) begin
            hit_hud = 1'b1;
            rgb_hud = 12'hFFE;
        end
        else if (bit_p2_spec) begin
            hit_hud = 1'b1;
            rgb_hud = 12'hFA0;
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
