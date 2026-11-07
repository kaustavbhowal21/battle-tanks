`timescale 1ns/1ps
`ifndef MULTIPLIER_DSP_V
`define MULTIPLIER_DSP_V

module multiplier_dsp (
    input  wire        clk,
    input  wire        reset_n,
    input  wire        start,
    input  wire        is_custom,
    input  wire [2:0]  funct3,
    input  wire [31:0] operand_a,
    input  wire [31:0] operand_b,
    output reg  [31:0] result,
    output wire        ready
);

`include "opcode.vh"

    // Sign extension depending on operation
    // MUL / MULH / CUSTOM_MULQ* : signed x signed
    // MULHSU                    : signed x unsigned
    // MULHU                     : unsigned x unsigned
    wire signed_a = is_custom || (funct3 == MUL) || (funct3 == MULH) || (funct3 == MULHSU);
    wire signed_b = is_custom || (funct3 == MUL) || (funct3 == MULH);

    wire signed [32:0] op_a_ext = signed_a ? {operand_a[31], operand_a} : {1'b0, operand_a};
    wire signed [32:0] op_b_ext = signed_b ? {operand_b[31], operand_b} : {1'b0, operand_b};

    // Full 66-bit signed product (covers 33x33 bit multiply)
    wire signed [65:0] product_full = op_a_ext * op_b_ext;

    // Combinational completion for single-cycle execution
    assign ready = start;

    always @(*) begin
        if (is_custom) begin
            case (funct3)
                CUSTOM_MULQ16: result = product_full[47:16]; // Q16.16 middle 32 bits
                CUSTOM_MULQ8:  result = product_full[39:8];  // Q24.8 fixed-point product
                default:       result = product_full[47:16];
            endcase
        end else begin
            case (funct3)
                MUL:    result = product_full[31:0];      // Lower 32 bits
                MULH,
                MULHSU,
                MULHU:  result = product_full[63:32];     // Upper 32 bits
                default: result = 32'h0;
            endcase
        end
    end

endmodule
`endif