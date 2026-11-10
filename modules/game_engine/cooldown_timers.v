`timescale 1ns / 1ps
//=============================================================================
// Hardware Cooldown Timers (Fig 4 & Timing Diagram D)
//
// Part A: 1 ms prescaler shared by all four channels.
// Part B: 4 independent down-counters (P1 shoot, P1 special, P2 shoot, P2 special).
// Part C: MMIO write decode (TIMER_TRIGGER 0x8000_0014) and status read (0x8000_0010).
//=============================================================================
`ifndef COOLDOWN_TIMERS_V
`define COOLDOWN_TIMERS_V

module cooldown_timers #(
    parameter CLK_PER_MS = 50_000   // 50,000 clocks @ 50 MHz = 1 ms (set smaller for simulation)
)(
    input  wire        clk,
    input  wire        reset_n,

    // MMIO bus interface
    input  wire        wr_en_tmr,
    input  wire [31:0] d_addr,
    input  wire [31:0] d_wdata,
    output wire [31:0] rd_tmr,

    // Hardware special attack cooldown bar fill levels (0 = empty, 100 = full/ready)
    output wire [6:0]  bar_p1_spec_out,
    output wire [6:0]  bar_p2_spec_out
);

    // =========================================================================
    // Part A: 1 ms Prescaler
    // =========================================================================
    reg [16:0] ms_cnt;
    wire       tick = (ms_cnt == (CLK_PER_MS - 1));

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n)
            ms_cnt <= 17'd0;
        else if (tick)
            ms_cnt <= 17'd0;
        else
            ms_cnt <= ms_cnt + 1'b1;
    end

    // =========================================================================
    // Part C: Trigger Decode
    // Writing to TIMER_TRIGGER (0x8000_0014, d_addr[2] == 1'b1) reloads counters
    // =========================================================================
    wire is_trigger = wr_en_tmr && (d_addr[2] == 1'b1);
    wire trig_p1_shoot = is_trigger && d_wdata[0];
    wire trig_p1_spec  = is_trigger && d_wdata[1];
    wire trig_p2_shoot = is_trigger && d_wdata[2];
    wire trig_p2_spec  = is_trigger && d_wdata[3];

    // =========================================================================
    // Part B: 4 Down-Counter Channels
    // Channel 0: P1 shoot   (500 ms = 0.5 s)
    // Channel 1: P1 special (10,000 ms = 10 s)
    // Channel 2: P2 shoot   (500 ms = 0.5 s)
    // Channel 3: P2 special (10,000 ms = 10 s)
    // =========================================================================
    localparam [14:0] LOAD_SHOOT = 15'd500;
    localparam [14:0] LOAD_SPEC  = 15'd10000;

    reg [14:0] cd_p1_shoot;
    reg [14:0] cd_p1_spec;
    reg [14:0] cd_p2_shoot;
    reg [14:0] cd_p2_spec;

    reg [6:0]  sub_p1_spec;
    reg [6:0]  bar_p1_spec;
    reg [6:0]  sub_p2_spec;
    reg [6:0]  bar_p2_spec;

    // Channel 0: P1 Shoot
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n)
            cd_p1_shoot <= 15'd0;
        else if (trig_p1_shoot)
            cd_p1_shoot <= LOAD_SHOOT;
        else if (tick && (cd_p1_shoot != 15'd0))
            cd_p1_shoot <= cd_p1_shoot - 1'b1;
    end

    // Channel 1: P1 Special
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            cd_p1_spec  <= 15'd0;
            sub_p1_spec <= 7'd0;
            bar_p1_spec <= 7'd100;
        end else if (trig_p1_spec) begin
            cd_p1_spec  <= LOAD_SPEC;
            sub_p1_spec <= 7'd0;
            bar_p1_spec <= 7'd0;
        end else if (tick && (cd_p1_spec != 15'd0)) begin
            cd_p1_spec <= cd_p1_spec - 1'b1;
            if (sub_p1_spec == 7'd99) begin
                sub_p1_spec <= 7'd0;
                bar_p1_spec <= bar_p1_spec + 1'b1;
            end else begin
                sub_p1_spec <= sub_p1_spec + 1'b1;
            end
        end else if (cd_p1_spec == 15'd0) begin
            bar_p1_spec <= 7'd100;
            sub_p1_spec <= 7'd0;
        end
    end

    // Channel 2: P2 Shoot
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n)
            cd_p2_shoot <= 15'd0;
        else if (trig_p2_shoot)
            cd_p2_shoot <= LOAD_SHOOT;
        else if (tick && (cd_p2_shoot != 15'd0))
            cd_p2_shoot <= cd_p2_shoot - 1'b1;
    end

    // Channel 3: P2 Special
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            cd_p2_spec  <= 15'd0;
            sub_p2_spec <= 7'd0;
            bar_p2_spec <= 7'd100;
        end else if (trig_p2_spec) begin
            cd_p2_spec  <= LOAD_SPEC;
            sub_p2_spec <= 7'd0;
            bar_p2_spec <= 7'd0;
        end else if (tick && (cd_p2_spec != 15'd0)) begin
            cd_p2_spec <= cd_p2_spec - 1'b1;
            if (sub_p2_spec == 7'd99) begin
                sub_p2_spec <= 7'd0;
                bar_p2_spec <= bar_p2_spec + 1'b1;
            end else begin
                sub_p2_spec <= sub_p2_spec + 1'b1;
            end
        end else if (cd_p2_spec == 15'd0) begin
            bar_p2_spec <= 7'd100;
            sub_p2_spec <= 7'd0;
        end
    end

    // Status: 1 when ready (counter == 0)
    wire ready_p1_shoot = (cd_p1_shoot == 15'd0);
    wire ready_p1_spec  = (cd_p1_spec  == 15'd0);
    wire ready_p2_shoot = (cd_p2_shoot == 15'd0);
    wire ready_p2_spec  = (cd_p2_spec  == 15'd0);

    // Reading TIMER_STATUS (0x8000_0010, d_addr[2] == 1'b0)
    assign rd_tmr = {28'd0, ready_p2_spec, ready_p2_shoot, ready_p1_spec, ready_p1_shoot};

    assign bar_p1_spec_out = bar_p1_spec;
    assign bar_p2_spec_out = bar_p2_spec;

endmodule

`endif
