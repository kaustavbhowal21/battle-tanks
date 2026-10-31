`timescale 1ns/1ps
////////////////////////////////////////////////////////////// Stage 2: Execute////////////////////////////////////////////////////////////
`ifndef EXECUTE_V
`define EXECUTE_V

module execute
#(
    parameter [31:0] RESET = 32'h0000_0000
)
(
    input clk,
    input reset,

    // -----------------------------    // FROM ID/EX    // -----------------------------
    input  [31:0] reg_rdata1,
    input  [31:0] reg_rdata2,
    input  [31:0] execute_imm,
    input  [31:0] pc,           // PC of the instruction currently in EX
    input  [31:0] fetch_pc,     // PC currently being fetched
    input         immediate_sel,
    input         mem_write,
    input         jal,
    input         jalr,
    input         lui,
    input         auipc,
    input         alu,
    input         branch,
    input         arithsubtype,
    input         m_extension_valid,
    input         mem_to_reg,
    input         stall_read,

    input  [4:0]  dest_reg_sel,
    input  [2:0]  alu_op,
    input  [1:0]  dmem_raddr,

    // -----------------------------    // FROM WB    // -----------------------------
    input         wb_branch_i,
    input         wb_branch_nxt_i,

    // -----------------------------    // EX -> PIPE    // -----------------------------
    output [31:0] alu_operand1,
    output [31:0] alu_operand2,
    output [31:0] write_address,
    output        branch_stall,
    output        m_pipeline_stall,

    output reg [31:0] next_pc,
    output reg        branch_taken,

    // -----------------------------  // EX -> WB    // -----------------------------
    output [31:0] wb_result,
    output        wb_mem_write,
    output        wb_alu_to_reg,
    output [4:0]  wb_dest_reg_sel,
    output        wb_branch,
    output        wb_branch_nxt,
    output        wb_mem_to_reg,
    output [1:0]  wb_read_address,
    output [2:0]  mem_alu_operation
);

//////////////// Including OPCODES ////////////////////////////
`include "opcode.vh"

wire [31:0] m_result;
wire        m_ready;

rv32m_top u_rv32m (
    .clk               (clk),
    .reset_n           (reset),
    .m_extension_valid (m_extension_valid && !branch_stall),
    .alu_op            (alu_op),             // funct3 [14:12]
    .operand_a         (alu_operand1),       // rs1
    .operand_b         (alu_operand2),       // rs2 (immediate_sel is 0 for R-type)
    .m_result          (m_result),
    .pipeline_stall    (m_pipeline_stall),
    .m_ready           (m_ready)
);

////////////////////////////////////////////////////////////// LOCAL INTERNAL SIGNALS/////////////////////////////////

reg  [31:0] ex_result;
wire [32:0] ex_result_subs;
wire [32:0] ex_result_subu;

// 5-bit shift amount (RISC-V only uses the low 5 bits of the second operand)
wire [4:0]  shamt = alu_operand2[4:0];

// Signed view of operand 1, needed so that SRA really is an arithmetic shift.
wire signed [31:0] alu_operand1_s = alu_operand1;

////////////////////////////////////////////////////////////// Operand selection///////////////////////////////////////////////////////

// TODO-EX-1 (DONE)
assign alu_operand1 = reg_rdata1;
assign alu_operand2 = immediate_sel ? execute_imm
                                    : reg_rdata2;

////////////////////////////////////////////////////////////// Subtractions////////////////////////////////////////////////////////////

// TODO-EX-2 (DONE)
// Signed compare: sign-extend both operands to 33 bits, bit[32] of the
// difference is then "operand1 <  operand2" (signed).
assign ex_result_subs =
    {alu_operand1[31], alu_operand1} -
    {alu_operand2[31], alu_operand2};

// Unsigned compare: zero-extend both operands to 33 bits, bit[32] is the
// borrow, i.e. "operand1 < operand2" (unsigned).
assign ex_result_subu =
    {1'b0, alu_operand1} -
    {1'b0, alu_operand2};

////////////////////////////////////////////////////////////// Address & branch stall////////////////////////////////////////

assign write_address = alu_operand1 + execute_imm;
assign branch_stall  = wb_branch_nxt_i || wb_branch_i;

////////////////////////////////////////////////////////////// Next PC logic////////////////////////////////////////////////////////////

// TODO-EX-3 (DONE)
always @(*) begin
    next_pc      = fetch_pc + 32'd4;
    branch_taken = !branch_stall;

    case (1'b1)
        // JAL  : PC-relative
        jal  : next_pc = pc + execute_imm;
        // JALR : register relative, LSB of the target is forced to 0 (RISC-V spec)
        jalr : next_pc = (alu_operand1 + execute_imm) & ~32'd1;

        branch: begin
            case (alu_op)
                BEQ:  begin
                    next_pc = (ex_result_subs == 0)
                              ? pc + execute_imm
                              : fetch_pc + 32'd4;
                    if (ex_result_subs != 0)
                        branch_taken = 1'b0;
                end
                BNE:  begin
                    next_pc = (ex_result_subs != 0)
                              ? pc + execute_imm
                              : fetch_pc + 32'd4;
                    if (ex_result_subs == 0)
                        branch_taken = 1'b0;
                end
                BLT:  begin
                    next_pc = ex_result_subs[32]
                              ? pc + execute_imm
                              : fetch_pc + 32'd4;
                    if (!ex_result_subs[32])
                        branch_taken = 1'b0;
                end
                BGE:  begin
                    next_pc = !ex_result_subs[32]
                              ? pc + execute_imm
                              : fetch_pc + 32'd4;
                    if (ex_result_subs[32])
                        branch_taken = 1'b0;
                end
                BLTU: begin
                    next_pc = ex_result_subu[32]
                              ? pc + execute_imm
                              : fetch_pc + 32'd4;
                    if (!ex_result_subu[32])
                        branch_taken = 1'b0;
                end
                BGEU: begin
                    next_pc = !ex_result_subu[32]
                              ? pc + execute_imm
                              : fetch_pc + 32'd4;
                    if (ex_result_subu[32])
                        branch_taken = 1'b0;
                end
                // BUG FIX: the original default assigned `next_pc = fetch_pc`,
                // which re-fetches the same address forever (livelock) on the
                // two reserved BRANCH func3 encodings (3'b010 / 3'b011).
                default: begin
                    next_pc      = fetch_pc + 32'd4;
                    branch_taken = 1'b0;
                end
            endcase
        end

        default: begin
            next_pc      = fetch_pc + 32'd4;
            branch_taken = 1'b0;
        end
    endcase
end

////////////////////////////////////////////////////////////// ALU result logic////////////////////////////////////////////////////////////

// TODO-EX-4 (DONE)
always @(*) begin
    case (1'b1)
        mem_write: ex_result = alu_operand2;          // store data (rs2)
        jal,
        jalr:      ex_result = pc + 32'd4;            // link address
        lui:       ex_result = execute_imm;
        auipc:     ex_result = pc + execute_imm;
        m_extension_valid: ex_result = m_result;
        alu: begin
            case (alu_op)
                ADD : ex_result =
                      arithsubtype
                      ? alu_operand1 - alu_operand2
                      : alu_operand1 + alu_operand2;
                SLL : ex_result = alu_operand1 << shamt;
                SLT : ex_result = {31'h0, ex_result_subs[32]};
                SLTU: ex_result = {31'h0, ex_result_subu[32]};
                XOR : ex_result = alu_operand1 ^ alu_operand2;
                // BUG FIX (3 separate bugs in the original one-liner):
                //  1. SRL used `>>>`. On an unsigned operand that happens to
                //     behave like `>>`, but `>>` states the intent.
                //  2. The shift amount was the full 32-bit operand. RISC-V
                //     only uses the low 5 bits, so `srl x1,x2,x3` with
                //     x3 > 31 gave 0 instead of the correct result.
                //  3. *The real killer*: SRA was written as a ternary
                //     `arithsubtype ? $signed(a) >>> s : a >> s`. In Verilog
                //     an expression is unsigned if ANY operand is unsigned,
                //     so the unsigned `a >> s` branch silently made the whole
                //     conditional unsigned and `>>>` degraded to a logical
                //     shift. SRAI/SRA of a negative number returned garbage
                //     (e.g. srai x17,x3,1 with x3=-1 gave 0x7FFFFFFF).
                //     Splitting it into if/else keeps the signedness intact.
                SR  : begin
                          if (arithsubtype)
                              ex_result = alu_operand1_s >>> shamt;  // SRA
                          else
                              ex_result = alu_operand1   >>  shamt;  // SRL
                      end
                OR  : ex_result = alu_operand1 | alu_operand2;
                AND : ex_result = alu_operand1 & alu_operand2;
                default: ex_result = 32'h0;
            endcase
        end

        // BUG FIX: was 'hx. Branch instructions fall through to here, so the
        // X used to be latched into wb_result and propagate through the
        // forwarding muxes in simulation. 0 is harmless (alu_to_reg is low).
        default: ex_result = 32'h0;
    endcase
end


////////////////////////////////////////////////////////////// EX -> WB pipeline register/////////////////////////////////////////

ex_mem_wb_reg u_ex_mem_wb (
    .clk            (clk),
    .reset_n        (reset),
    .stall_n        (stall_read),

    .ex_result      (ex_result),

    .mem_write      (mem_write && !branch_stall && !m_pipeline_stall),
    // BUG FIX: never mark x0 as a destination and never write back for an
    // instruction that is sitting in the branch shadow or during a multi-cycle DIV stall.
    .alu_to_reg     ((alu | lui | auipc | jal | jalr | mem_to_reg | m_extension_valid) &&
                    (dest_reg_sel != 5'd0) && !branch_stall && !m_pipeline_stall),
    .dest_reg_sel   (dest_reg_sel),
    .branch_taken   (branch_taken),
    .mem_to_reg     (mem_to_reg),
    .read_address   (dmem_raddr),
    .alu_operation  (alu_op),

    .ex_mem_result        (wb_result),
    .ex_mem_mem_write     (wb_mem_write),
    .ex_mem_alu_to_reg    (wb_alu_to_reg),
    .ex_mem_dest_reg_sel  (wb_dest_reg_sel),
    .ex_mem_branch        (wb_branch),
    .ex_mem_branch_nxt    (wb_branch_nxt),
    .ex_mem_mem_to_reg    (wb_mem_to_reg),
    .ex_mem_read_address  (wb_read_address),
    .ex_mem_alu_operation (mem_alu_operation)
);

endmodule


module ex_mem_wb_reg (
    input         clk,
    input         reset_n,
    input         stall_n,        // again: active-HIGH stall despite the name

    // Data
    input  [31:0] ex_result,

    // Control inputs from EX/MEM
    input         mem_write,
    input         alu_to_reg,
    input  [4:0]  dest_reg_sel,
    input         branch_taken,
    input         mem_to_reg,
    input  [1:0]  read_address,
    input  [2:0]  alu_operation,

    // Outputs to WB
    output reg [31:0] ex_mem_result,
    output reg        ex_mem_mem_write,
    output reg        ex_mem_alu_to_reg,
    output reg [4:0]  ex_mem_dest_reg_sel,
    output reg        ex_mem_branch,
    output reg        ex_mem_branch_nxt,
    output reg        ex_mem_mem_to_reg,
    output reg [1:0]  ex_mem_read_address,
    output reg [2:0]  ex_mem_alu_operation
);

// TODO-EX-5 (DONE)
always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
        ex_mem_result         <= 32'h0;
        ex_mem_mem_write      <= 1'b0;
        ex_mem_alu_to_reg     <= 1'b0;
        ex_mem_dest_reg_sel   <= 5'h0;
        ex_mem_branch         <= 1'b0;
        ex_mem_branch_nxt     <= 1'b0;
        ex_mem_mem_to_reg     <= 1'b0;
        ex_mem_read_address   <= 2'h0;
        ex_mem_alu_operation  <= 3'h0;
    end
    else if (!stall_n) begin
        ex_mem_result         <= ex_result;
        ex_mem_mem_write      <= mem_write;
        ex_mem_alu_to_reg     <= alu_to_reg;
        ex_mem_dest_reg_sel   <= dest_reg_sel;
        ex_mem_branch         <= branch_taken;
        ex_mem_branch_nxt     <= ex_mem_branch;
        ex_mem_mem_to_reg     <= mem_to_reg;
        ex_mem_read_address   <= read_address;
        ex_mem_alu_operation  <= alu_operation;
    end
end

endmodule

`endif
