`timescale 1ns / 1ps
//=============================================================================
// Input Controller (Fig 3 & Timing Diagram D)
//
// Part A: 2-FF metastability synchronizer + debouncer (x12 channels).
// Part B: Register packing and MMIO read (P1_INPUT_REG 0x8000_0000, P2_INPUT_REG 0x8000_0004).
//=============================================================================
`ifndef INPUT_CONTROLLER_V
`define INPUT_CONTROLLER_V

module input_controller #(
    // Debounce time in clk cycles: 3 ms @ 50 MHz (can override for simulation).
    // Kept short so a button press reaches the CPU almost immediately.
    parameter DEBOUNCE_MAX = 20'd150_000,
    // Minimum time a debounced press is held on the output (20 ms @ 50 MHz, a bit
    // more than one 16.7 ms game frame). The CPU samples the buttons only once per
    // frame, so without this a quick tap could fall between two samples and be lost.
    parameter MIN_HOLD     = 21'd1_000_000
)(
    input  wire        clk,
    input  wire        reset_n,

    // Raw external buttons (FPGA pins / breadboard)
    input  wire [5:0]  p1_btn_raw,       // [0]=FWD, [1]=BWD, [2]=LEFT, [3]=RIGHT, [4]=SHOOT, [5]=SPEC
    input  wire [5:0]  p2_btn_raw,

    // MMIO bus interface
    input  wire [31:0] d_addr,
    output wire [31:0] rd_in,

    // Stable outputs directly usable by hardware
    output wire [5:0]  p1_btn_stable,
    output wire [5:0]  p2_btn_stable
);

    wire [11:0] raw_inputs = {p2_btn_raw, p1_btn_raw};
    wire [11:0] debounced_outputs;

    genvar i;
    generate
        for (i = 0; i < 12; i = i + 1) begin : gen_debouncers
            reg sync1, sync2;
            reg stable_q;
            reg [19:0] cnt_q;
            reg [20:0] hold_q;      // remaining minimum-hold time of a press

            wire diff = sync2 ^ stable_q;

            always @(posedge clk or negedge reset_n) begin
                if (!reset_n) begin
                    sync1    <= 1'b0;
                    sync2    <= 1'b0;
                    stable_q <= 1'b0;
                    cnt_q    <= 20'd0;
                    hold_q   <= 21'd0;
                end else begin
                    sync1 <= raw_inputs[i];
                    sync2 <= sync1;

                    if (hold_q != 21'd0)
                        hold_q <= hold_q - 1'b1;

                    if (diff) begin
                        if (cnt_q == DEBOUNCE_MAX) begin
                            // A release is only accepted once the minimum hold has
                            // expired (the debounce counter just waits at MAX).
                            if (sync2 || (hold_q == 21'd0)) begin
                                stable_q <= sync2;
                                cnt_q    <= 20'd0;
                                if (sync2)
                                    hold_q <= MIN_HOLD;
                            end
                        end else begin
                            cnt_q <= cnt_q + 1'b1;
                        end
                    end else begin
                        cnt_q <= 20'd0;
                    end
                end
            end

            assign debounced_outputs[i] = stable_q;
        end
    endgenerate

    assign p1_btn_stable = debounced_outputs[5:0];
    assign p2_btn_stable = debounced_outputs[11:6];

    // MMIO Read Mux (Fig 3 Part B)
    // d_addr[2] == 0 -> P1_INPUT_REG (0x8000_0000)
    // d_addr[2] == 1 -> P2_INPUT_REG (0x8000_0004)
    assign rd_in = d_addr[2] ? {26'd0, p2_btn_stable} : {26'd0, p1_btn_stable};

endmodule

`endif
