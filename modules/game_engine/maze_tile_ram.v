`timescale 1ns / 1ps
//=============================================================================
// Maze Tile RAM: Two Mirrored True-Dual-Port BRAMs (Fig 7 & Timing Diagram H)
//
// 20 x 20 tiles = 400 entries, 2 bits each.
// Solves 3-user access (CPU, VGA, Collision) without arbiters or pipeline stalls.
// CPU writes both copies simultaneously on Port A.
// Copy V Port B is dedicated to the VGA Maze Tile Renderer.
// Copy C Port B is dedicated to the Hardware Collision Engine.
//=============================================================================
`ifndef MAZE_TILE_RAM_V
`define MAZE_TILE_RAM_V

module maze_tile_ram (
    input  wire        clk,
    input  wire        reset_n,

    // CPU Port A (Read / Write)
    input  wire        wr_en_maze,
    input  wire [31:0] d_addr,         // write address, base 0x8000_0100
    input  wire [31:0] d_raddr,        // read address (independent of in-flight stores)
    input  wire [31:0] d_wdata,
    output reg  [31:0] rd_maze,        // CPU read from Copy V

    // VGA Port B (Read-Only)
    input  wire [8:0]  vga_tile_addr,  // 0..399
    output reg  [1:0]  vga_tile_data,

    // Collision Port B (Read-Only)
    input  wire [8:0]  col_tile_addr,  // 0..399
    output reg  [1:0]  col_tile_data
);

    // 400 entries x 2 bits each
    (* ram_style = "distributed" *)
    reg [1:0] ram_copy_v [0:399];
    (* ram_style = "distributed" *)
    reg [1:0] ram_copy_c [0:399];

    // Decode CPU word address: base 0x100 is word index 64
    wire [8:0] cpu_word_idx = d_addr[10:2];
    wire       cpu_in_range = (cpu_word_idx >= 9'd64) && (cpu_word_idx <= 9'd463);
    wire [8:0] cpu_tile_addr = cpu_word_idx - 9'd64;
    wire       we_cpu = wr_en_maze && cpu_in_range;

    // Separate CPU read index (a load may coincide with a store to another address)
    wire [8:0] cpu_rword_idx  = d_raddr[10:2];
    wire [8:0] cpu_rtile_addr = cpu_rword_idx - 9'd64;

    // Pre-initialize perimeter walls for immediate out-of-the-box playability
    integer r, c, idx;
    initial begin
        for (r = 0; r < 20; r = r + 1) begin
            for (c = 0; c < 20; c = c + 1) begin
                idx = r * 20 + c;
                // Tile encoding (shared with maze_tile_renderer.v and software/mmio.h):
                //   0 = floor, 1 = destructible brick, 2 = indestructible steel, 3 = solid
                // Outer perimeter wall: indestructible steel (code 2), so bullets can
                // no longer blow holes in the arena border.
                if (r == 0 || r == 19 || c == 0 || c == 19) begin
                    ram_copy_v[idx] = 2'b10;
                    ram_copy_c[idx] = 2'b10;
                end
                // Interior pillar walls: indestructible steel (code 2)
                else if ((r % 4 == 0) && (c % 4 == 0)) begin
                    ram_copy_v[idx] = 2'b10;
                    ram_copy_c[idx] = 2'b10;
                end
                // Breakable wall obstacles in the centre: destructible brick (code 1)
                else if ((r == 10 && (c >= 8 && c <= 11))) begin
                    ram_copy_v[idx] = 2'b01;
                    ram_copy_c[idx] = 2'b01;
                end
                // Open floor (tile code 0)
                else begin
                    ram_copy_v[idx] = 2'b00;
                    ram_copy_c[idx] = 2'b00;
                end
            end
        end
    end

    // -------------------------------------------------------------------------
    // COPY V (Display Engine)
    // -------------------------------------------------------------------------
    // Port A: CPU Write and Read
    always @(posedge clk) begin
        if (we_cpu)
            ram_copy_v[cpu_tile_addr] <= d_wdata[1:0];
        rd_maze <= {30'd0, ram_copy_v[cpu_rtile_addr]};
    end

    // Port B: VGA Display Read
    always @(posedge clk) begin
        vga_tile_data <= ram_copy_v[vga_tile_addr];
    end

    // -------------------------------------------------------------------------
    // COPY C (Collision Engine)
    // -------------------------------------------------------------------------
    // Port A: CPU Write (Mirror of Copy V)
    always @(posedge clk) begin
        if (we_cpu)
            ram_copy_c[cpu_tile_addr] <= d_wdata[1:0];
    end

    // Port B: Collision Bullet-Wall Scanner Read
    always @(posedge clk) begin
        col_tile_data <= ram_copy_c[col_tile_addr];
    end

endmodule

`endif
