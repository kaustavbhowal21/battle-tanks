`timescale 1ns / 1ps
//=============================================================================
// Sprite & HUD Register File (Fig 5)
//
// 12 x 32-bit write-only MMIO registers.
// Latches positions, health, angles, and bullet active/size flags from C code
// and continuously drives the Collision Engine and VGA Display Engine.
//=============================================================================
`ifndef SPRITE_HUD_REGFILE_V
`define SPRITE_HUD_REGFILE_V

module sprite_hud_regfile (
    input  wire        clk,
    input  wire        reset_n,

    // MMIO bus interface
    input  wire        wr_en_spr,
    input  wire [31:0] d_addr,
    input  wire [31:0] d_wdata,

    // Outputs to Sprite Engine and Collision Engine
    output wire [9:0]  p1_tank_x,
    output wire [9:0]  p1_tank_y,
    output wire [9:0]  p2_tank_x,
    output wire [9:0]  p2_tank_y,

    // 8 Bullets: packed arrays for clean indexing
    output wire [9:0]  bullet_x   [0:7],
    output wire [9:0]  bullet_y   [0:7],
    output wire [7:0]  bullet_act,
    output wire [7:0]  bullet_big,

    // Health and Angles
    output wire [7:0]  hp1,
    output wire [7:0]  hp2,
    output wire [3:0]  tank_ang1,
    output wire [3:0]  tank_ang2
);

    wire [5:0] reg_idx = d_addr[7:2];

    reg [31:0] p1_tank_pos_q;
    reg [31:0] p2_tank_pos_q;
    reg [31:0] bullet_reg_q [0:7];
    reg [31:0] health_bar_reg_q;
    reg [31:0] tank_angle_reg_q;

    integer j;
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            // Default initial positions and health (20 hearts each)
            p1_tank_pos_q    <= {16'd100, 16'd50};    // y=100, x=50
            p2_tank_pos_q    <= {16'd350, 16'd400};   // y=350, x=400
            for (j = 0; j < 8; j = j + 1)
                bullet_reg_q[j] <= 32'd0;
            health_bar_reg_q <= {16'd0, 8'd20, 8'd20}; // hp2=20, hp1=20
            tank_angle_reg_q <= 32'd0;
        end else if (wr_en_spr) begin
            case (reg_idx)
                6'd16: p1_tank_pos_q <= d_wdata;     // 0x40
                6'd17: p2_tank_pos_q <= d_wdata;     // 0x44
                6'd18: bullet_reg_q[0] <= d_wdata;   // 0x48
                6'd19: bullet_reg_q[1] <= d_wdata;   // 0x4C
                6'd20: bullet_reg_q[2] <= d_wdata;   // 0x50
                6'd21: bullet_reg_q[3] <= d_wdata;   // 0x54
                6'd22: bullet_reg_q[4] <= d_wdata;   // 0x58
                6'd23: bullet_reg_q[5] <= d_wdata;   // 0x5C
                6'd24: bullet_reg_q[6] <= d_wdata;   // 0x60
                6'd25: bullet_reg_q[7] <= d_wdata;   // 0x64
                6'd32: health_bar_reg_q <= d_wdata;  // 0x80
                6'd33: tank_angle_reg_q <= d_wdata;  // 0x84
                default: ;
            endcase
        end
    end

    // Unpack positions
    assign p1_tank_x = p1_tank_pos_q[9:0];
    assign p1_tank_y = p1_tank_pos_q[25:16];
    assign p2_tank_x = p2_tank_pos_q[9:0];
    assign p2_tank_y = p2_tank_pos_q[25:16];

    // Unpack bullets
    genvar i;
    generate
        for (i = 0; i < 8; i = i + 1) begin : gen_bullets
            assign bullet_x[i]   = bullet_reg_q[i][9:0];
            assign bullet_y[i]   = bullet_reg_q[i][19:10];
            assign bullet_act[i] = bullet_reg_q[i][20];
            assign bullet_big[i] = bullet_reg_q[i][21];
        end
    endgenerate

    // Unpack health and angle
    assign hp1 = health_bar_reg_q[7:0];
    assign hp2 = health_bar_reg_q[15:8];
    assign tank_ang1 = tank_angle_reg_q[3:0];
    assign tank_ang2 = tank_angle_reg_q[7:4];

endmodule

`endif
