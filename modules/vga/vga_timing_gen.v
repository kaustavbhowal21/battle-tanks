`timescale 1ns / 1ps
//=============================================================================
// Fig 8: VGA Timing Generator (640x480 @ 60 Hz, 25 MHz pixel enable)
//
// Timing specification:
// Horizontal: 640 visible + 16 front porch + 96 sync + 48 back porch = 800 pix
// Vertical:   480 visible + 10 front porch +  2 sync + 33 back porch = 525 lines
// Advancing:  Horizontal advances when pix_ce = 1; Vertical advances on h_end.
// Sync polarities: Both HSYNC and VSYNC are active-low for standard 640x480@60Hz.
//=============================================================================
`ifndef VGA_TIMING_GEN_V
`define VGA_TIMING_GEN_V

module vga_timing_gen (
    input  wire        clk,        // 50 MHz clk_sys
    input  wire        reset_n,    // Active-low synchronous/asynchronous reset
    input  wire        pix_ce,     // 25 MHz pixel clock enable pulse

    output reg  [9:0]  x,          // Visible beam X coordinate (0..639)
    output reg  [9:0]  y,          // Visible beam Y coordinate (0..479)
    output reg  [9:0]  hcnt,       // Raw horizontal counter (0..799)
    output reg  [9:0]  vcnt,       // Raw vertical counter (0..524)
    output reg         hsync_n,    // Active-low horizontal sync
    output reg         vsync_n,    // Active-low vertical sync
    output reg         active,     // 1 when beam is inside active display (640x480)
    output wire        h_end,      // 1-cycle strobe at end of line (hcnt == 799 & pix_ce)
    output wire        v_end,      // 1-cycle strobe at end of frame (vcnt == 524 & h_end)
    output wire        frame_tick  // 1-cycle strobe at start of VBLANK (y == 480)
);

    localparam H_VISIBLE = 10'd640;
    localparam H_FRONT   = 10'd16;
    localparam H_SYNC    = 10'd96;
    localparam H_BACK    = 10'd48;
    localparam H_TOTAL   = 10'd800;

    localparam V_VISIBLE = 10'd480;
    localparam V_FRONT   = 10'd10;
    localparam V_SYNC    = 10'd2;
    localparam V_BACK    = 10'd33;
    localparam V_TOTAL   = 10'd525;

    localparam H_SYNC_START = H_VISIBLE + H_FRONT;             // 656
    localparam H_SYNC_END   = H_VISIBLE + H_FRONT + H_SYNC;     // 752
    localparam V_SYNC_START = V_VISIBLE + V_FRONT;             // 490
    localparam V_SYNC_END   = V_VISIBLE + V_FRONT + V_SYNC;     // 492

    assign h_end = (hcnt == (H_TOTAL - 10'd1)) && pix_ce;
    assign v_end = (vcnt == (V_TOTAL - 10'd1)) && h_end;
    assign frame_tick = (vcnt == V_VISIBLE) && h_end;

    // Next-state counters
    wire        h_wrap   = (hcnt == (H_TOTAL - 10'd1));
    wire [9:0]  hcnt_nxt = h_wrap ? 10'd0 : (hcnt + 10'd1);
    wire [9:0]  vcnt_nxt = !h_wrap ? vcnt :
                           ((vcnt == (V_TOTAL - 10'd1)) ? 10'd0 : (vcnt + 10'd1));

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            hcnt    <= 10'd0;
            vcnt    <= 10'd0;
            x       <= 10'd0;
            y       <= 10'd0;
            hsync_n <= 1'b1;
            vsync_n <= 1'b1;
            active  <= 1'b0;
        end else if (pix_ce) begin
            hcnt <= hcnt_nxt;
            vcnt <= vcnt_nxt;

            // All registered outputs are computed from the NEXT counter values so
            // that x/y/active/hsync_n/vsync_n describe the same pixel as hcnt/vcnt
            // (previously they lagged hcnt/vcnt by one pixel, so x != hcnt).
            x <= (hcnt_nxt < H_VISIBLE) ? hcnt_nxt : 10'd0;
            y <= (vcnt_nxt < V_VISIBLE) ? vcnt_nxt : 10'd0;

            active <= (hcnt_nxt < H_VISIBLE) && (vcnt_nxt < V_VISIBLE);

            hsync_n <= !((hcnt_nxt >= H_SYNC_START) && (hcnt_nxt < H_SYNC_END));
            vsync_n <= !((vcnt_nxt >= V_SYNC_START) && (vcnt_nxt < V_SYNC_END));
        end
    end

endmodule

`endif
