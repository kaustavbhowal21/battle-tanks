`timescale 1ns/1ps
//==========================================================================
//  Stage 1 : Instruction Fetch / Instruction Decode
//==========================================================================
`ifndef IF_ID_V
`define IF_ID_V

module IF_ID
#(
    parameter [31:0] RESET = 32'h0000_0000
)
(
    input                   clk,
    input                   reset,          // active LOW, asynchronous
    input                   stall,
    output reg              exception,

    // Instruction memory interface
    input                   inst_mem_is_valid,
    input  [31:0]           inst_mem_read_data,

    // ----------------------------- // Signals previously read from pipe  // -----------------------------
    input                   stall_read_i,
    input  [31:0]           inst_fetch_pc,
    input  [31:0]           instruction_i,

    // -----------------------------    // WB-stage signals (passed in)    // -----------------------------
    input                   wb_branch_i,
    input                   wb_stall,
    input                   wb_alu_to_reg,
    input                   wb_mem_to_reg,
    input  [4:0]            wb_dest_reg_sel,
    input  [31:0]           wb_result,
    input  [31:0]           wb_read_data,

    // -----------------------------    // Instruction memory address info    // -----------------------------
    input  [1:0]            inst_mem_offset,
    output [31:0] execute_immediate_w,
    output        immediate_sel_w,
    output        alu_w,
    output        lui_w,
    output        auipc_w,
    output        jal_w,
    output        jalr_w,
    output        branch_w,
    output        mem_write_w,
    output        mem_to_reg_w,
    output        arithsubtype_w,
    output        m_extension_valid_w,
    output [31:0] pc_w,
    output [4:0]  src1_select_w,
    output [4:0]  src2_select_w,
    output [4:0]  dest_reg_sel_w,
    output [2:0]  alu_operation_w,
    output        illegal_inst_w,
    output [31:0] instruction_o
);

//////////////// Including OPCODES ////////////////////////////
`include "opcode.vh"
//////////////////////////////
//////////////////////////////// LOCAL INTERNAL SIGNALS////////////////////////////////////////////////////////////

reg  [31:0] immediate;
reg         illegal_inst;
wire is_rv32m = (instruction_i[`OPCODE] == ARITHR) && 
                (instruction_i[`FUNC7]  == FUNC7_RV32M);

////////////////////////////////////////////////////////////// IF stage////////////////////////////////////////////////////////////

    reg [31:0] skid_buffer;
    reg [31:0] skid_pc;
    reg        has_skid;

    always @(posedge clk or negedge reset) begin
        if (!reset) begin
            skid_buffer <= 32'h0;
            skid_pc     <= 32'h0;
            has_skid    <= 1'b0;
        end else if (wb_branch_i) begin
            skid_buffer <= 32'h0;
            skid_pc     <= 32'h0;
            has_skid    <= 1'b0;
        end else if (stall_read_i) begin
            if (!has_skid && inst_mem_is_valid) begin
                skid_buffer <= inst_mem_read_data;
                skid_pc     <= inst_fetch_pc;
                has_skid    <= 1'b1;
            end
        end else begin
            has_skid    <= 1'b0;
        end
    end

    wire [31:0] current_instr = has_skid ? skid_buffer : inst_mem_read_data;
    wire [31:0] current_pc    = has_skid ? skid_pc     : inst_fetch_pc;

    assign instruction_o = (stall_read_i || !inst_mem_is_valid)
                         ? NOP
                         : current_instr;

////////////////////////////////////////////////////////////// Exception detection////////////////////////////////////////////////////////////

// TODO-2 (DONE):
// Assert exception when:
// - illegal instruction is detected
// - instruction fetch is misaligned (inst_mem_offset != 2'b00)
//
// BUG FIX: the original had no `else` branch, so once `exception` went high it
// could never be cleared (and it was also never assigned a value at all).
// It is now a proper registered flag that follows the condition every cycle.

always @(posedge clk or negedge reset) begin
    if (!reset)
        exception <= 1'b0;
    else if (!stall_read_i)
        exception <= illegal_inst || (inst_mem_offset != 2'b00);
end

////////////////////////////////////////////////////////////// ID stage: immediate generation///////////////////////////////////////////////////////////

// TODO-3 (DONE): 32-bit immediates for JAL, JALR, BRANCH, LOAD, STORE, ARITH-I, LUI

always @(*) begin
    immediate    = 32'h0;
    illegal_inst = 1'b0;

    case (instruction_i[`OPCODE])

        // JALR:  imm[11:0] = inst[31:20], sign extended
        JALR  : immediate = {{20{instruction_i[31]}}, instruction_i[31:20]};

        // BRANCH (B-type):
        // imm[12]=inst[31], imm[11]=inst[7], imm[10:5]=inst[30:25],
        // imm[4:1]=inst[11:8], imm[0]=0, imm[31:13]=sign extend
        BRANCH: immediate = {{19{instruction_i[31]}},
                             instruction_i[31],
                             instruction_i[7],
                             instruction_i[30:25],
                             instruction_i[11:8],
                             1'b0};

        // LOAD (I-type): imm[11:0] = inst[31:20], sign extended
        LOAD  : immediate = {{20{instruction_i[31]}}, instruction_i[31:20]};

        // STORE (S-type): imm[11:5]=inst[31:25], imm[4:0]=inst[11:7], sign extended
        STORE : immediate = {{20{instruction_i[31]}},
                             instruction_i[31:25],
                             instruction_i[11:7]};

        // ARITH-I: shifts use the 5-bit shamt, everything else the signed imm12
        ARITHI: immediate =
                (instruction_i[`FUNC3] == SLL ||
                 instruction_i[`FUNC3] == SR)
                ? {27'h0, instruction_i[24:20]}
                : {{20{instruction_i[31]}}, instruction_i[31:20]};

        // ARITH-R: no immediate
        ARITHR: immediate = 32'h0;

        // LUI / AUIPC (U-type): imm[31:12]=inst[31:12], imm[11:0]=0
        LUI,
        AUIPC : immediate = {instruction_i[31:12], 12'h0};

        // JAL (J-type):
        // imm[20]=inst[31], imm[19:12]=inst[19:12], imm[11]=inst[20],
        // imm[10:1]=inst[30:21], imm[0]=0, imm[31:21]=sign extend
        JAL   : immediate = {{11{instruction_i[31]}},
                             instruction_i[31],
                             instruction_i[19:12],
                             instruction_i[20],
                             instruction_i[30:21],
                             1'b0};

        default: illegal_inst = 1'b1;
    endcase
end

////////////////////////////////////////////////////////////// ID -> EX Register////////////////////////////////////////////////////////////

// TODO-4 (DONE): control signal generation

id_ex_reg u_id_ex (
    .clk            (clk),
    .reset_n        (reset),
    .stall_n        (stall_read_i),

    // From ID
    .immediate_i    (immediate),
    .immediate_sel_i(
        (instruction_i[`OPCODE] == JALR)  ||(instruction_i[`OPCODE] == LOAD)  ||
        (instruction_i[`OPCODE] == ARITHI)
    ),
    .alu_i          ((instruction_i[`OPCODE] == ARITHI) || 
                    ((instruction_i[`OPCODE] == ARITHR) && !is_rv32m)),
    .lui_i          (instruction_i[`OPCODE] == LUI),
    .auipc_i        (instruction_i[`OPCODE] == AUIPC),
    .jal_i          (instruction_i[`OPCODE] == JAL),
    .jalr_i         (instruction_i[`OPCODE] == JALR),
    .branch_i       (instruction_i[`OPCODE] == BRANCH),
    .mem_write_i    (instruction_i[`OPCODE] == STORE),
    .mem_to_reg_i   (instruction_i[`OPCODE] == LOAD),
    .arithsubtype_i (
        instruction_i[`SUBTYPE] &&
        !(instruction_i[`OPCODE] == ARITHI &&
          instruction_i[`FUNC3] == ADD)
    ),
    .m_extension_valid_i (is_rv32m),
    .pc_i           (current_pc),
    .src1_sel_i     (instruction_i[`RS1]),
    .src2_sel_i     (instruction_i[`RS2]),
    .dest_reg_sel_i (instruction_i[`RD]),
    .alu_op_i       (instruction_i[`FUNC3]),
    .illegal_inst_i (illegal_inst),

    // To EX (WIRES)
    .execute_immediate_o (execute_immediate_w),
    .immediate_sel_o     (immediate_sel_w),
    .alu_o               (alu_w),
    .lui_o               (lui_w),
    .auipc_o             (auipc_w),
    .jal_o               (jal_w),
    .jalr_o              (jalr_w),
    .branch_o            (branch_w),
    .mem_write_o         (mem_write_w),
    .mem_to_reg_o        (mem_to_reg_w),
    .arithsubtype_o      (arithsubtype_w),
    .m_extension_valid_o (m_extension_valid_w),
    .pc_o                (pc_w),
    .src1_sel_o          (src1_select_w),
    .src2_sel_o          (src2_select_w),
    .dest_reg_sel_o      (dest_reg_sel_w),
    .alu_op_o            (alu_operation_w),
    .illegal_inst_o      (illegal_inst_w)
);
endmodule


////////////////////////////////////////////////////////////// ID -> EX register module////////////////////////////////////////////////////////////

module id_ex_reg (
    input         clk,
    input         reset_n,
    input         stall_n,   // NOTE: this is really "stall" (active HIGH), see below

    // Inputs from ID
    input  [31:0] immediate_i,
    input         immediate_sel_i,
    input         alu_i,
    input         lui_i,
    input         auipc_i,
    input         jal_i,
    input         jalr_i,
    input         branch_i,
    input         mem_write_i,
    input         mem_to_reg_i,
    input         arithsubtype_i,
    input         m_extension_valid_i,
    input  [31:0] pc_i,
    input  [4:0]  src1_sel_i,
    input  [4:0]  src2_sel_i,
    input  [4:0]  dest_reg_sel_i,
    input  [2:0]  alu_op_i,
    input         illegal_inst_i,

    // Outputs to EX
    output reg [31:0] execute_immediate_o,
    output reg        immediate_sel_o,
    output reg        alu_o,
    output reg        lui_o,
    output reg        auipc_o,
    output reg        jal_o,
    output reg        jalr_o,
    output reg        branch_o,
    output reg        mem_write_o,
    output reg        mem_to_reg_o,
    output reg        arithsubtype_o,
    output reg        m_extension_valid_o,
    output reg [31:0] pc_o,
    output reg [4:0]  src1_sel_o,
    output reg [4:0]  src2_sel_o,
    output reg [4:0]  dest_reg_sel_o,
    output reg [2:0]  alu_op_o,
    output reg        illegal_inst_o
);

// TODO-5 (DONE): clear / capture every field.
always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
        execute_immediate_o <= 32'h0;
        immediate_sel_o     <= 1'b0;
        alu_o               <= 1'b0;
        lui_o               <= 1'b0;
        auipc_o             <= 1'b0;
        jal_o               <= 1'b0;
        jalr_o              <= 1'b0;
        branch_o            <= 1'b0;
        mem_write_o         <= 1'b0;
        mem_to_reg_o        <= 1'b0;
        arithsubtype_o      <= 1'b0;
        m_extension_valid_o <= 1'b0;
        pc_o                <= 32'h0;
        src1_sel_o          <= 5'h0;
        src2_sel_o          <= 5'h0;
        dest_reg_sel_o      <= 5'h0;
        alu_op_o            <= 3'h0;
        illegal_inst_o      <= 1'b0;
    end
    else if (!stall_n) begin        // stall_n == 0  =>  no stall  =>  advance
        execute_immediate_o <= immediate_i;
        immediate_sel_o     <= immediate_sel_i;
        alu_o               <= alu_i;
        lui_o               <= lui_i;
        auipc_o             <= auipc_i;
        jal_o               <= jal_i;
        jalr_o              <= jalr_i;
        branch_o            <= branch_i;
        mem_write_o         <= mem_write_i;
        mem_to_reg_o        <= mem_to_reg_i;
        arithsubtype_o      <= arithsubtype_i;
        m_extension_valid_o <= m_extension_valid_i;
        pc_o                <= pc_i;
        src1_sel_o          <= src1_sel_i;
        src2_sel_o          <= src2_sel_i;
        dest_reg_sel_o      <= dest_reg_sel_i;
        alu_op_o            <= alu_op_i;
        illegal_inst_o      <= illegal_inst_i;
    end
end

endmodule

`endif
