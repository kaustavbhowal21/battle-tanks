`timescale 1ns/1ps
`ifndef RV32M_TOP_V
`define RV32M_TOP_V

module rv32m_top (
    input  wire        clk,
    input  wire        reset_n,

    // Control from ID/EX
    input  wire        m_extension_valid,  // Asserted when (OPCODE == ARITHR && FUNC7 == FUNC7_RV32M)
    input  wire [2:0]  alu_op,             // funct3 field
    input  wire [31:0] operand_a,          // rs1 value
    input  wire [31:0] operand_b,          // rs2 value

    // Output to EX multiplexer and pipeline controller
    output reg  [31:0] m_result,
    output wire        pipeline_stall,     // Tells the CPU to hold IF/ID and bubble WB
    output wire        m_ready
);

`include "opcode.vh"

    // Distinguish multiply vs divide operations
    wire is_mul = m_extension_valid && (alu_op[2] == 1'b0); // MUL, MULH, MULHSU, MULHU (3'b000 - 3'b011)
    wire is_div = m_extension_valid && (alu_op[2] == 1'b1); // DIV, DIVU, REM, REMU    (3'b100 - 3'b111)

    // Handshakes and intermediate outputs
    wire [31:0] mul_out;
    wire        mul_ready;

    wire [31:0] div_out;
    wire        div_busy;
    wire        div_ready;

    // Trigger divider start on the first cycle of instruction validity
    reg div_started;
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n)
            div_started <= 1'b0;
        else if (is_div && !div_busy && !div_ready)
            div_started <= 1'b1;
        else
            div_started <= 1'b0;
    end

    // 1. Instantiation of Multiplier
    multiplier_dsp u_mul (
        .clk       (clk),
        .reset_n   (reset_n),
        .start     (is_mul),
        .funct3    (alu_op),
        .operand_a (operand_a),
        .operand_b (operand_b),
        .result    (mul_out),
        .ready     (mul_ready)
    );

    // 2. Instantiation of Iterative Divider
    divider_radix2 u_div (
        .clk       (clk),
        .reset_n   (reset_n),
        .start     (div_started),
        .funct3    (alu_op),
        .operand_a (operand_a),
        .operand_b (operand_b),
        .result    (div_out),
        .busy      (div_busy),
        .ready     (div_ready)
    );

    // Stall pipeline during multi-cycle division until ready asserts
    assign pipeline_stall = is_div && !div_ready;
    assign m_ready        = is_mul ? mul_ready : div_ready;

    // Result Multiplexer
    always @(*) begin
        if (is_mul)
            m_result = mul_out;
        else if (is_div)
            m_result = div_out;
        else
            m_result = 32'h0;
    end

endmodule
`endif