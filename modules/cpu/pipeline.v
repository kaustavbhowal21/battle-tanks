//////////////// Including Stages ////////////////////////////
// NOTE: each of these files now carries an `ifndef include guard, so it is
// safe to both `include them here *and* have them added to the Vivado
// project as separate source files.
`include "IF_ID.v"
`include "execute.v"
`include "wb.v"

`timescale 1ns/1ps
`ifndef PIPELINE_V
`define PIPELINE_V

module pipe
#(
    parameter [31:0]        RESET = 32'h0000_0000
)
(
    input                   clk,
    input                   reset,      // active LOW
    input                   stall,
    output                  exception,
    output [31:0]           pc_out,

    // interface of instruction Memory
    input                   inst_mem_is_valid,
    input        [31: 0]    inst_mem_read_data,
    input        [31: 0]    dmem_read_data_temp,
    input                   dmem_write_valid,
    input                   dmem_read_valid,

    // ------------------------------------------------------------------
    // BUG FIX / TODO: these used to be internal-only wires, so the top level
    // and the testbench had no way to hook the memories up. They are now
    // real ports.
    // ------------------------------------------------------------------
    output       [31: 0]    inst_mem_address,

    output                  dmem_read_ready,
    output       [31: 0]    dmem_read_address,

    output                  dmem_write_ready,
    output       [31: 0]    dmem_write_address,
    output       [31: 0]    dmem_write_data,
    output       [ 3: 0]    dmem_write_byte
);

    //Declaring Wires and Registers

    wire                m_extension_valid;
    wire                m_pipeline_stall;

    //Data Memory Wires

    wire        [31: 0] dmem_read_data;
    wire         [1:0]  dmem_read_offset;
    wire                inst_mem_is_ready;

    //Instruction Fetch/Decode Stage

    wire                immediate_sel;
    wire        [ 4: 0] src1_select;
    wire        [ 4: 0] src2_select;
    wire        [ 4: 0] dest_reg_sel;
    wire        [ 2: 0] alu_operation;
    wire                arithsubtype;
    wire                mem_write;
    wire                mem_to_reg;
    wire                illegal_inst;
    wire        [31: 0] execute_immediate;
    wire                alu;
    wire                lui;
    wire                auipc;
    wire                jal;
    wire                jalr;
    wire                branch;
    reg                 stall_read;
    wire        [31: 0] instruction;
    wire        [31: 0] reg_rdata2;
    wire        [31: 0] reg_rdata1;
    reg         [31: 0] regs [31: 1];

    // PC

    wire        [31: 0] pc;
    wire        [31: 0] inst_fetch_pc;
    reg         [31: 0] fetch_pc;

    //Stalls

    wire    wb_stall_first;
    wire    wb_stall_second;
    wire    wb_stall;

    //Execute Stage

    wire        [31: 0] next_pc;
    wire        [31: 0] write_address;
    wire                branch_taken;
    wire                branch_stall;
    wire        [31: 0] alu_operand1;
    wire        [31: 0] alu_operand2;

    // Write Back

    wire                wb_alu_to_reg;
    wire        [31: 0] wb_result;
    wire        [ 2: 0] wb_alu_operation;
    wire                wb_mem_write;
    wire                wb_mem_to_reg;
    wire        [ 4: 0] wb_dest_reg_sel;
    wire                wb_branch;
    wire                wb_branch_nxt;
    wire        [31: 0] wb_write_address;
    wire        [ 1: 0] wb_read_address;
    wire        [ 3: 0] wb_write_byte;
    wire        [31: 0] wb_write_data;
    wire        [31: 0] wb_read_data;

//------------------------------------------------------//
assign dmem_write_address   = wb_write_address;                     // where to write
assign dmem_read_address    = alu_operand1 + execute_immediate;     // load address (EX stage)
assign dmem_read_offset     = dmem_read_address[1:0];
assign dmem_read_ready      = mem_to_reg && dmem_read_valid;        // load flag
assign dmem_write_ready     = wb_mem_write && dmem_write_valid;     // store flag
assign dmem_write_data      = wb_write_data;
assign dmem_write_byte      = wb_write_byte;
assign dmem_read_data       = dmem_read_data_temp;
// -----------------------------------------------------//

// instantiating Instruction fetch module -----------------------
IF_ID #(.RESET(RESET)) IF_ID_stage (
    .clk                (clk),
    .reset              (reset),
    .stall              (stall),
    .exception          (exception),

    // Instruction memory interface
    .inst_mem_is_valid  (inst_mem_is_valid),
    .inst_mem_read_data (inst_mem_read_data),

    // Previously pipe.* signals (now explicit ports)
    .stall_read_i       (stall_read || m_pipeline_stall),
    .inst_fetch_pc      (inst_fetch_pc),
    .instruction_i      (instruction),

    // WB-stage signals
    .wb_branch_i        (wb_branch),
    .wb_stall           (wb_stall),
    .wb_alu_to_reg      (wb_alu_to_reg),
    .wb_mem_to_reg      (wb_mem_to_reg),
    .wb_dest_reg_sel    (wb_dest_reg_sel),
    .wb_result          (wb_result),
    .wb_read_data       (wb_read_data),

    // Instruction memory address offset
    .inst_mem_offset    (inst_mem_address[1:0]),

    // Output wires (write-only)
    .execute_immediate_w (execute_immediate),
    .immediate_sel_w    (immediate_sel),
    .alu_w              (alu),
    .lui_w              (lui),
    .auipc_w            (auipc),
    .jal_w              (jal),
    .jalr_w             (jalr),
    .branch_w           (branch),
    .mem_write_w        (mem_write),
    .mem_to_reg_w       (mem_to_reg),
    .arithsubtype_w     (arithsubtype),
    .m_extension_valid_w(m_extension_valid),
    .pc_w               (pc),
    .src1_select_w      (src1_select),
    .src2_select_w      (src2_select),
    .dest_reg_sel_w     (dest_reg_sel),
    .alu_operation_w    (alu_operation),
    .illegal_inst_w     (illegal_inst),
    .instruction_o      (instruction)
);


////////////////////////////////////////////////////////////
// TODO (DONE): Register File Forwarding
//
// - src register x0 -> always 0
// - WB stage writing the same register (and not stalled) -> forward
//      wb_read_data (LOAD)  /  wb_result (ALU)
// - otherwise read the register array
////////////////////////////////////////////////////////////

assign reg_rdata1 =
    (src1_select == 5'd0) ? 32'h0 :
    (!wb_stall && wb_alu_to_reg && (wb_dest_reg_sel == src1_select))
    ? (wb_mem_to_reg ? wb_read_data : wb_result)
    : regs[src1_select];

assign reg_rdata2 =
    (src2_select == 5'd0) ? 32'h0 :
    (!wb_stall && wb_alu_to_reg && (wb_dest_reg_sel == src2_select))
    ? (wb_mem_to_reg ? wb_read_data : wb_result)
    : regs[src2_select];

////////////////////////////////////////////////////////////
// TODO (DONE): Register File Writeback
////////////////////////////////////////////////////////////

integer i;
always @(posedge clk or negedge reset) begin
    if (!reset) begin
        for (i = 1; i < 32; i = i + 1)
            regs[i] <= 32'h0;
    end
    // BUG FIX: explicitly guard against writing x0. regs is declared [31:1],
    // so regs[0] is an out-of-range write - harmless in simulation but it
    // hides the intent and some tools warn about it.
    else if (wb_alu_to_reg && !stall_read && !wb_stall &&
             (wb_dest_reg_sel != 5'd0)) begin
        regs[wb_dest_reg_sel] <=
            wb_mem_to_reg ? wb_read_data : wb_result;
    end
end


////////////////////////////////////////////////////////////
// Stall register
////////////////////////////////////////////////////////////

always @(posedge clk or negedge reset) begin
    if (!reset)
        stall_read <= 1'b1;
    else
        stall_read <= stall;
end


// instantiating execute module -----------------------------------
execute #(.RESET(RESET)) execute (
    // -----------------
    // Clock / Reset
    // -----------------
    .clk            (clk),
    .reset          (reset),

    // -----------------
    // FROM ID/EX   (TODO - DONE)
    // -----------------
    .reg_rdata1     (reg_rdata1),
    .reg_rdata2     (reg_rdata2),
    .execute_imm    (execute_immediate),
    .pc             (pc),
    .fetch_pc       (fetch_pc),
    .immediate_sel  (immediate_sel),
    .mem_write      (mem_write),
    .jal            (jal),
    .jalr           (jalr),
    .lui            (lui),
    .auipc          (auipc),
    .alu            (alu),
    .branch         (branch),
    .arithsubtype   (arithsubtype),
    .m_extension_valid(m_extension_valid),
    .mem_to_reg     (mem_to_reg),
    .stall_read     (stall_read),

    .dest_reg_sel   (dest_reg_sel),
    .alu_op         (alu_operation),
    .dmem_raddr     (dmem_read_offset),

    // -----------------
    // FROM WB
    // -----------------
    .wb_branch_i    (wb_branch),
    .wb_branch_nxt_i(wb_branch_nxt),

    // -----------------
    // EX -> PIPE
    // -----------------
    .alu_operand1   (alu_operand1),
    .alu_operand2   (alu_operand2),
    .write_address  (write_address),
    .branch_stall   (branch_stall),
    .m_pipeline_stall(m_pipeline_stall),
    .next_pc        (next_pc),
    .branch_taken   (branch_taken),

    // -----------------
    // EX -> WB   (TODO - DONE)
    // -----------------
    .wb_result        (wb_result),
    .wb_mem_write     (wb_mem_write),
    .wb_alu_to_reg    (wb_alu_to_reg),
    .wb_dest_reg_sel  (wb_dest_reg_sel),
    .wb_branch        (wb_branch),
    .wb_branch_nxt    (wb_branch_nxt),
    .wb_mem_to_reg    (wb_mem_to_reg),
    .wb_read_address  (wb_read_address),
    .mem_alu_operation(wb_alu_operation)
);



////////////////////////////////////////////////////////////
// PC Update Logic
//
// reset            -> PC = RESET
// branch_stall = 1 -> the two shadow instructions still have to be fetched,
//                     so keep going sequentially
// otherwise        -> PC = next_pc (sequential, jump or branch target)
// stall_read       -> freeze the PC
////////////////////////////////////////////////////////////

always @(posedge clk or negedge reset) begin
    if (!reset)
        fetch_pc <= RESET;
    else if (!stall_read && !m_pipeline_stall)
        fetch_pc <= branch_stall
                    ? fetch_pc + 32'd4
                    : next_pc;
end


// instantiating Writeback module ----------------------------------
wb #(.RESET(RESET)) wb_stage (
    .clk                (clk),
    .reset              (reset),

    // ----------------- inputs (TODO - DONE)
    .stall_read_i       (stall_read || m_pipeline_stall),
    .fetch_pc_i         (fetch_pc),
    .wb_branch_i        (wb_branch),
    .wb_mem_to_reg_i    (wb_mem_to_reg),
    .mem_write_i        (mem_write),
    .write_address_i    (write_address),
    .alu_operand2_i     (alu_operand2),
    .alu_operation_i    (alu_operation),
    .wb_alu_operation_i (wb_alu_operation),
    .wb_read_address_i  (wb_read_address),
    .dmem_read_data_i   (dmem_read_data),
    .dmem_write_valid_i (dmem_write_valid),

    // ----------------- outputs (TODO - DONE)
    .inst_mem_address_o (inst_mem_address),
    .inst_mem_is_ready_o(inst_mem_is_ready),
    .wb_stall_o         (wb_stall),
    .wb_write_address_o (wb_write_address),
    .wb_write_data_o    (wb_write_data),
    .wb_write_byte_o    (wb_write_byte),
    .wb_read_data_o     (wb_read_data),
    .inst_fetch_pc_o    (inst_fetch_pc),
    .wb_stall_first_o   (wb_stall_first),
    .wb_stall_second_o  (wb_stall_second)
);

assign pc_out = fetch_pc;

endmodule

`endif
