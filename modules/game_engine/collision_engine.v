`timescale 1ns / 1ps
//=============================================================================
// Hardware Collision Engine (Fig 6a, 6b, 6c, 6d & Timing Diagram C)
//
// Part A: 28 Bullet-Bullet AABB overlap cells + 16 Bullet-Tank AABB overlap cells.
// Part B: Time-shared Bullet-Wall scan using Maze RAM Copy C (8 bullets in 8 clocks).
// Part C: Sticky hit registers with Write-1-to-Clear (W1C) logic and MMIO read path.
//=============================================================================
`ifndef COLLISION_ENGINE_V
`define COLLISION_ENGINE_V

module collision_engine (
    input  wire        clk,
    input  wire        reset_n,

    // Live object positions from Sprite & HUD Register File (Fig 5)
    input  wire [9:0]  p1_tank_x,
    input  wire [9:0]  p1_tank_y,
    input  wire [9:0]  p2_tank_x,
    input  wire [9:0]  p2_tank_y,

    input  wire [9:0]  bullet_x   [0:7],
    input  wire [9:0]  bullet_y   [0:7],
    input  wire [7:0]  bullet_act,
    input  wire [7:0]  bullet_big,

    // Interface to Maze RAM Copy C Port B (Fig 7)
    output reg  [8:0]  maze_c_addr,
    input  wire [1:0]  maze_c_data,

    // MMIO bus interface
    input  wire        wr_en_col,
    input  wire [31:0] d_addr,         // write address (W1C decode)
    input  wire [31:0] d_raddr,        // read address (independent of in-flight stores)
    input  wire [31:0] d_wdata,
    output reg  [31:0] rd_col
);

    // =========================================================================
    // Bullet Sizes: 6x6 normal, 12x12 big
    // =========================================================================
    wire [4:0] b_size [0:7];
    genvar bi;
    generate
        for (bi = 0; bi < 8; bi = bi + 1) begin : gen_bsize
            assign b_size[bi] = bullet_big[bi] ? 5'd12 : 5'd6;
        end
    endgenerate

    // Tank size: 20x20 constant
    localparam [4:0] TANK_SIZE = 5'd20;

    // =========================================================================
    // Part A: Bullet-Bullet 28-Pair Overlap Matrix (Fig 6c Part A)
    // =========================================================================
    wire [27:0] bb_pair_ovl;

    // Function to compute box overlap
    function aabb_overlap;
        input [9:0] ax, ay;
        input [4:0] aw, ah;
        input       a_act;
        input [9:0] bx, by;
        input [4:0] bw, bh;
        input       b_act;
        begin
            aabb_overlap = a_act && b_act &&
                           (ax < (bx + bw)) && (bx < (ax + aw)) &&
                           (ay < (by + bh)) && (by < (ay + ah));
        end
    endfunction

    // 28 unique pairs among 8 bullets
    assign bb_pair_ovl[0]  = aabb_overlap(bullet_x[0], bullet_y[0], b_size[0], b_size[0], bullet_act[0], bullet_x[1], bullet_y[1], b_size[1], b_size[1], bullet_act[1]);
    assign bb_pair_ovl[1]  = aabb_overlap(bullet_x[0], bullet_y[0], b_size[0], b_size[0], bullet_act[0], bullet_x[2], bullet_y[2], b_size[2], b_size[2], bullet_act[2]);
    assign bb_pair_ovl[2]  = aabb_overlap(bullet_x[0], bullet_y[0], b_size[0], b_size[0], bullet_act[0], bullet_x[3], bullet_y[3], b_size[3], b_size[3], bullet_act[3]);
    assign bb_pair_ovl[3]  = aabb_overlap(bullet_x[0], bullet_y[0], b_size[0], b_size[0], bullet_act[0], bullet_x[4], bullet_y[4], b_size[4], b_size[4], bullet_act[4]);
    assign bb_pair_ovl[4]  = aabb_overlap(bullet_x[0], bullet_y[0], b_size[0], b_size[0], bullet_act[0], bullet_x[5], bullet_y[5], b_size[5], b_size[5], bullet_act[5]);
    assign bb_pair_ovl[5]  = aabb_overlap(bullet_x[0], bullet_y[0], b_size[0], b_size[0], bullet_act[0], bullet_x[6], bullet_y[6], b_size[6], b_size[6], bullet_act[6]);
    assign bb_pair_ovl[6]  = aabb_overlap(bullet_x[0], bullet_y[0], b_size[0], b_size[0], bullet_act[0], bullet_x[7], bullet_y[7], b_size[7], b_size[7], bullet_act[7]);

    assign bb_pair_ovl[7]  = aabb_overlap(bullet_x[1], bullet_y[1], b_size[1], b_size[1], bullet_act[1], bullet_x[2], bullet_y[2], b_size[2], b_size[2], bullet_act[2]);
    assign bb_pair_ovl[8]  = aabb_overlap(bullet_x[1], bullet_y[1], b_size[1], b_size[1], bullet_act[1], bullet_x[3], bullet_y[3], b_size[3], b_size[3], bullet_act[3]);
    assign bb_pair_ovl[9]  = aabb_overlap(bullet_x[1], bullet_y[1], b_size[1], b_size[1], bullet_act[1], bullet_x[4], bullet_y[4], b_size[4], b_size[4], bullet_act[4]);
    assign bb_pair_ovl[10] = aabb_overlap(bullet_x[1], bullet_y[1], b_size[1], b_size[1], bullet_act[1], bullet_x[5], bullet_y[5], b_size[5], b_size[5], bullet_act[5]);
    assign bb_pair_ovl[11] = aabb_overlap(bullet_x[1], bullet_y[1], b_size[1], b_size[1], bullet_act[1], bullet_x[6], bullet_y[6], b_size[6], b_size[6], bullet_act[6]);
    assign bb_pair_ovl[12] = aabb_overlap(bullet_x[1], bullet_y[1], b_size[1], b_size[1], bullet_act[1], bullet_x[7], bullet_y[7], b_size[7], b_size[7], bullet_act[7]);

    assign bb_pair_ovl[13] = aabb_overlap(bullet_x[2], bullet_y[2], b_size[2], b_size[2], bullet_act[2], bullet_x[3], bullet_y[3], b_size[3], b_size[3], bullet_act[3]);
    assign bb_pair_ovl[14] = aabb_overlap(bullet_x[2], bullet_y[2], b_size[2], b_size[2], bullet_act[2], bullet_x[4], bullet_y[4], b_size[4], b_size[4], bullet_act[4]);
    assign bb_pair_ovl[15] = aabb_overlap(bullet_x[2], bullet_y[2], b_size[2], b_size[2], bullet_act[2], bullet_x[5], bullet_y[5], b_size[5], b_size[5], bullet_act[5]);
    assign bb_pair_ovl[16] = aabb_overlap(bullet_x[2], bullet_y[2], b_size[2], b_size[2], bullet_act[2], bullet_x[6], bullet_y[6], b_size[6], b_size[6], bullet_act[6]);
    assign bb_pair_ovl[17] = aabb_overlap(bullet_x[2], bullet_y[2], b_size[2], b_size[2], bullet_act[2], bullet_x[7], bullet_y[7], b_size[7], b_size[7], bullet_act[7]);

    assign bb_pair_ovl[18] = aabb_overlap(bullet_x[3], bullet_y[3], b_size[3], b_size[3], bullet_act[3], bullet_x[4], bullet_y[4], b_size[4], b_size[4], bullet_act[4]);
    assign bb_pair_ovl[19] = aabb_overlap(bullet_x[3], bullet_y[3], b_size[3], b_size[3], bullet_act[3], bullet_x[5], bullet_y[5], b_size[5], b_size[5], bullet_act[5]);
    assign bb_pair_ovl[20] = aabb_overlap(bullet_x[3], bullet_y[3], b_size[3], b_size[3], bullet_act[3], bullet_x[6], bullet_y[6], b_size[6], b_size[6], bullet_act[6]);
    assign bb_pair_ovl[21] = aabb_overlap(bullet_x[3], bullet_y[3], b_size[3], b_size[3], bullet_act[3], bullet_x[7], bullet_y[7], b_size[7], b_size[7], bullet_act[7]);

    assign bb_pair_ovl[22] = aabb_overlap(bullet_x[4], bullet_y[4], b_size[4], b_size[4], bullet_act[4], bullet_x[5], bullet_y[5], b_size[5], b_size[5], bullet_act[5]);
    assign bb_pair_ovl[23] = aabb_overlap(bullet_x[4], bullet_y[4], b_size[4], b_size[4], bullet_act[4], bullet_x[6], bullet_y[6], b_size[6], b_size[6], bullet_act[6]);
    assign bb_pair_ovl[24] = aabb_overlap(bullet_x[4], bullet_y[4], b_size[4], b_size[4], bullet_act[4], bullet_x[7], bullet_y[7], b_size[7], b_size[7], bullet_act[7]);

    assign bb_pair_ovl[25] = aabb_overlap(bullet_x[5], bullet_y[5], b_size[5], b_size[5], bullet_act[5], bullet_x[6], bullet_y[6], b_size[6], b_size[6], bullet_act[6]);
    assign bb_pair_ovl[26] = aabb_overlap(bullet_x[5], bullet_y[5], b_size[5], b_size[5], bullet_act[5], bullet_x[7], bullet_y[7], b_size[7], b_size[7], bullet_act[7]);

    assign bb_pair_ovl[27] = aabb_overlap(bullet_x[6], bullet_y[6], b_size[6], b_size[6], bullet_act[6], bullet_x[7], bullet_y[7], b_size[7], b_size[7], bullet_act[7]);

    // OR reduction per bullet
    wire [7:0] bb_hit;
    assign bb_hit[0] = bb_pair_ovl[0]  | bb_pair_ovl[1]  | bb_pair_ovl[2]  | bb_pair_ovl[3]  | bb_pair_ovl[4]  | bb_pair_ovl[5]  | bb_pair_ovl[6];
    assign bb_hit[1] = bb_pair_ovl[0]  | bb_pair_ovl[7]  | bb_pair_ovl[8]  | bb_pair_ovl[9]  | bb_pair_ovl[10] | bb_pair_ovl[11] | bb_pair_ovl[12];
    assign bb_hit[2] = bb_pair_ovl[1]  | bb_pair_ovl[7]  | bb_pair_ovl[13] | bb_pair_ovl[14] | bb_pair_ovl[15] | bb_pair_ovl[16] | bb_pair_ovl[17];
    assign bb_hit[3] = bb_pair_ovl[2]  | bb_pair_ovl[8]  | bb_pair_ovl[13] | bb_pair_ovl[18] | bb_pair_ovl[19] | bb_pair_ovl[20] | bb_pair_ovl[21];
    assign bb_hit[4] = bb_pair_ovl[3]  | bb_pair_ovl[9]  | bb_pair_ovl[14] | bb_pair_ovl[18] | bb_pair_ovl[22] | bb_pair_ovl[23] | bb_pair_ovl[24];
    assign bb_hit[5] = bb_pair_ovl[4]  | bb_pair_ovl[10] | bb_pair_ovl[15] | bb_pair_ovl[19] | bb_pair_ovl[22] | bb_pair_ovl[25] | bb_pair_ovl[26];
    assign bb_hit[6] = bb_pair_ovl[5]  | bb_pair_ovl[11] | bb_pair_ovl[16] | bb_pair_ovl[20] | bb_pair_ovl[23] | bb_pair_ovl[25] | bb_pair_ovl[27];
    assign bb_hit[7] = bb_pair_ovl[6]  | bb_pair_ovl[12] | bb_pair_ovl[17] | bb_pair_ovl[21] | bb_pair_ovl[24] | bb_pair_ovl[26] | bb_pair_ovl[27];

    // =========================================================================
    // Part B: Bullet-Tank 16-Cell Overlap Matrix (Fig 6c Part B)
    // =========================================================================
    wire [7:0] ovl_tk1;
    wire [7:0] ovl_tk2;
    wire [7:0] btk_hit;

    genvar ti;
    generate
        for (ti = 0; ti < 8; ti = ti + 1) begin : gen_tk_ovl
            assign ovl_tk1[ti] = aabb_overlap(bullet_x[ti], bullet_y[ti], b_size[ti], b_size[ti], bullet_act[ti],
                                              p1_tank_x, p1_tank_y, TANK_SIZE, TANK_SIZE, 1'b1);
            assign ovl_tk2[ti] = aabb_overlap(bullet_x[ti], bullet_y[ti], b_size[ti], b_size[ti], bullet_act[ti],
                                              p2_tank_x, p2_tank_y, TANK_SIZE, TANK_SIZE, 1'b1);
            assign btk_hit[ti] = ovl_tk1[ti] | ovl_tk2[ti];
        end
    endgenerate

    wire [1:0] tank_hit;
    assign tank_hit[0] = |ovl_tk1;  // Tank 1 hit this clock
    assign tank_hit[1] = |ovl_tk2;  // Tank 2 hit this clock

    // =========================================================================
    // Part C: Bullet-Wall Scan (Fig 6b)
    // Time-shared across 8 bullets in 8 clocks (1 shared Maze RAM port)
    // =========================================================================
    reg [2:0] scan_q;
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n)
            scan_q <= 3'd0;
        else
            scan_q <= scan_q + 1'b1;
    end

    wire [9:0] cur_bx = bullet_x[scan_q];
    wire [9:0] cur_by = bullet_y[scan_q];
    wire [3:0] cur_half = bullet_big[scan_q] ? 4'd6 : 4'd3;
    wire       cur_act  = bullet_act[scan_q];

    wire [9:0] cx = cur_bx + cur_half;
    wire [9:0] cy = cur_by + cur_half;

    // Exact tile index for coordinates < 480: (coord * 683) >> 14 == coord / 24
    // NOTE: the product needs 19 bits (480*683). It MUST be computed in a wide
    // intermediate; a direct '(cx * 10'd683) >> 14' into a 5-bit target is evaluated
    // at 10 bits, truncates the product and always yields tile 0 (a wall), which
    // flagged EVERY active bullet as hitting a wall.
    wire [18:0] cx_mul = cx * 19'd683;
    wire [18:0] cy_mul = cy * 19'd683;
    wire [4:0] cur_col = cx_mul[18:14];
    wire [4:0] cur_row = cy_mul[18:14];
    wire [8:0] calc_tile_addr = (cur_row << 4) + (cur_row << 2) + cur_col; // row*20 + col

    // Register address to Maze RAM
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n)
            maze_c_addr <= 9'd0;
        else
            maze_c_addr <= calc_tile_addr;
    end

    // 2-FF delay line for bullet index and active flag to align with BRAM read latency
    reg [2:0] scan_d1, scan_d2;
    reg       act_d1,  act_d2;
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            scan_d1 <= 3'd0; scan_d2 <= 3'd0;
            act_d1  <= 1'b0; act_d2  <= 1'b0;
        end else begin
            scan_d1 <= scan_q;  scan_d2 <= scan_d1;
            act_d1  <= cur_act; act_d2  <= act_d1;
        end
    end

    // Wall detected: tile code 1 (wall) or 2 (breakable wall), i.e. tile != 0
    wire is_wall = (maze_c_data[0] | maze_c_data[1]);
    wire wall_hit_now = is_wall && act_d2;

    wire [7:0] wall_set = wall_hit_now ? (8'b00000001 << scan_d2) : 8'd0;

    // =========================================================================
    // Part D: Sticky Hit Registers (Write-1-to-Clear, Fig 6d)
    // Clear wins over set when both occur on the same clock.
    // =========================================================================
    reg [7:0] sticky_wall_q;
    reg [7:0] sticky_bb_q;
    reg [7:0] sticky_btk_q;
    reg [1:0] sticky_tank_q;

    wire is_col_write = wr_en_col;
    wire [1:0] col_reg_sel = d_addr[3:2];
    wire [1:0] col_rd_sel  = d_raddr[3:2];

    integer k;
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            sticky_wall_q <= 8'd0;
            sticky_bb_q   <= 8'd0;
            sticky_btk_q  <= 8'd0;
            sticky_tank_q <= 2'd0;
        end else begin
            // WALL_MASK (0x24, reg_sel == 2'b01)
            for (k = 0; k < 8; k = k + 1) begin
                if (is_col_write && (col_reg_sel == 2'b01) && d_wdata[k])
                    sticky_wall_q[k] <= 1'b0;
                else if (wall_set[k])
                    sticky_wall_q[k] <= 1'b1;
            end

            // BB_MASK (0x28, reg_sel == 2'b10)
            for (k = 0; k < 8; k = k + 1) begin
                if (is_col_write && (col_reg_sel == 2'b10) && d_wdata[k])
                    sticky_bb_q[k] <= 1'b0;
                else if (bb_hit[k])
                    sticky_bb_q[k] <= 1'b1;
            end

            // HIT_MASK (0x2C, reg_sel == 2'b11): bits [7:0] btk, bits [9:8] tank
            for (k = 0; k < 8; k = k + 1) begin
                if (is_col_write && (col_reg_sel == 2'b11) && d_wdata[k])
                    sticky_btk_q[k] <= 1'b0;
                else if (btk_hit[k])
                    sticky_btk_q[k] <= 1'b1;
            end

            if (is_col_write && (col_reg_sel == 2'b11) && d_wdata[8])
                sticky_tank_q[0] <= 1'b0;
            else if (tank_hit[0])
                sticky_tank_q[0] <= 1'b1;

            if (is_col_write && (col_reg_sel == 2'b11) && d_wdata[9])
                sticky_tank_q[1] <= 1'b0;
            else if (tank_hit[1])
                sticky_tank_q[1] <= 1'b1;
        end
    end

    // Overall summary flags
    wire wall_any     = |sticky_wall_q;
    wire bb_any       = |sticky_bb_q;
    wire tank_hit_any = |sticky_tank_q;

    // MMIO Read Multiplexer (Fig 6d Part B)
    always @(*) begin
        case (col_rd_sel)
            2'b00:   rd_col = {29'd0, tank_hit_any, bb_any, wall_any};                // 0x20: COLLISION_FLAG
            2'b01:   rd_col = {24'd0, sticky_wall_q};                                  // 0x24: WALL_MASK
            2'b10:   rd_col = {24'd0, sticky_bb_q};                                    // 0x28: BB_MASK
            2'b11:   rd_col = {22'd0, sticky_tank_q, sticky_btk_q};                   // 0x2C: HIT_MASK
            default: rd_col = 32'd0;
        endcase
    end

endmodule

`endif
