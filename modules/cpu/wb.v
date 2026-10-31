`timescale 1ns/1ps
////////////////////////////////////////////////////////////
// stage 3: Write Back
////////////////////////////////////////////////////////////
`ifndef WB_V
`define WB_V

module wb
#(
    parameter [31:0] RESET = 32'h0000_0000
)
(
    input clk,
    input reset,

    input        stall_read_i,
    input [31:0] fetch_pc_i,

    input        wb_branch_i,
    input        wb_mem_to_reg_i,
    input        mem_write_i,

    input [31:0] write_address_i,
    input [31:0] alu_operand2_i,
    input [2:0]  alu_operation_i,

    input [2:0]  wb_alu_operation_i,
    input [1:0]  wb_read_address_i,

    input [31:0] dmem_read_data_i,
    input        dmem_write_valid_i,

    // Outputs
    output [31:0] inst_mem_address_o,
    output inst_mem_is_ready_o,
    output wb_stall_o,
    output reg [31:0] wb_write_address_o,
    output reg [31:0] wb_write_data_o,
    output reg [3:0]  wb_write_byte_o,
    output reg [31:0] wb_read_data_o,
    output reg [31:0] inst_fetch_pc_o,
    output reg wb_stall_first_o,
    output reg wb_stall_second_o
);

// import "opcode.vh" for OPCODES
`include "opcode.vh"


////////////////////////////////////////////////////////////
// assigning these variables to read from the instruction memory
////////////////////////////////////////////////////////////

assign inst_mem_address_o  = fetch_pc_i;
assign inst_mem_is_ready_o = !stall_read_i;

////////////////////////////////////////////////////////////
// wb_stall flag for defining the first and second stall in branch instruction
////////////////////////////////////////////////////////////

assign wb_stall_o = wb_stall_first_o || wb_stall_second_o;

////////////////////////////////////////////////////////////
// instruction fetch pc update
////////////////////////////////////////////////////////////

always @(posedge clk or negedge reset) begin
    if (!reset)
        inst_fetch_pc_o <= RESET;   // reset the instruction-fetch program counter
    else if (!stall_read_i)
        inst_fetch_pc_o <= fetch_pc_i;
end

////////////////////////////////////////////////////////////
// Branch stall variable declarations
////////////////////////////////////////////////////////////
// Two-cycle stall so the two instructions already in flight behind a taken
// branch/jump do not commit their register writes.

always @(posedge clk or negedge reset) begin
    if (!reset) begin
        wb_stall_first_o  <= 1'b0;
        wb_stall_second_o <= 1'b0;
    end
    else if (!stall_read_i &&
            !((wb_mem_to_reg_i && !dmem_write_valid_i))) begin
        wb_stall_first_o  <= wb_branch_i;
        wb_stall_second_o <= wb_stall_first_o;
    end
end

////////////////////////////////////////////////////////////
// Preparing write data for store type instructions
////////////////////////////////////////////////////////////

// TODO-WB-1 (DONE): byte-enable generation for SB / SH / SW

always @(posedge clk or negedge reset) begin
    if (!reset) begin
        wb_write_address_o <= 32'h0;
        wb_write_byte_o    <= 4'h0;
        wb_write_data_o    <= 32'h0;
    end
    else if (!stall_read_i && mem_write_i) begin
        wb_write_address_o <= write_address_i;
        case (alu_operation_i)

            // Store Byte
            SB: begin
                wb_write_data_o <= {4{alu_operand2_i[7:0]}};
                case (write_address_i[1:0])
                    2'b00:  wb_write_byte_o <= 4'b0001;
                    2'b01:  wb_write_byte_o <= 4'b0010;
                    2'b10:  wb_write_byte_o <= 4'b0100;
                    default:wb_write_byte_o <= 4'b1000;
                endcase
            end
            // Store Halfword
            SH: begin
                wb_write_data_o <= {2{alu_operand2_i[15:0]}};
                wb_write_byte_o <= write_address_i[1] ? 4'b1100 : 4'b0011;
            end
            // Store Word
            SW: begin
                wb_write_data_o <= alu_operand2_i;
                wb_write_byte_o <= 4'b1111;
            end
            default: begin
                // BUG FIX: was 32'hx / 4'hx. An X byte-enable makes the whole
                // data memory go X in simulation. Drive a safe "no write".
                wb_write_data_o <= 32'h0;
                wb_write_byte_o <= 4'b0000;
            end
        endcase
    end
end

////////////////////////////////////////////////////////////
// load instruction based on the OPCODES
////////////////////////////////////////////////////////////

// TODO-WB-2 (DONE): load data formatting / sign-extension

always @* begin
    case (wb_alu_operation_i)
        LB: begin // Load byte
            case (wb_read_address_i)
                2'b00: wb_read_data_o = {{24{dmem_read_data_i[7]}},  dmem_read_data_i[7:0]};
                2'b01: wb_read_data_o = {{24{dmem_read_data_i[15]}}, dmem_read_data_i[15:8]};
                2'b10: wb_read_data_o = {{24{dmem_read_data_i[23]}}, dmem_read_data_i[23:16]};
                2'b11: wb_read_data_o = {{24{dmem_read_data_i[31]}}, dmem_read_data_i[31:24]};
            endcase
        end

        // load halfword
        LH: wb_read_data_o =
            wb_read_address_i[1]
            ? {{16{dmem_read_data_i[31]}}, dmem_read_data_i[31:16]}
            : {{16{dmem_read_data_i[15]}}, dmem_read_data_i[15:0]};

        LW: wb_read_data_o = dmem_read_data_i; // load word

        LBU: begin // load byte unsigned
            case (wb_read_address_i)
                2'b00: wb_read_data_o = {24'h0, dmem_read_data_i[7:0]};
                2'b01: wb_read_data_o = {24'h0, dmem_read_data_i[15:8]};
                2'b10: wb_read_data_o = {24'h0, dmem_read_data_i[23:16]};
                2'b11: wb_read_data_o = {24'h0, dmem_read_data_i[31:24]};
            endcase
        end

        // load halfword unsigned
        LHU: wb_read_data_o =
            wb_read_address_i[1]
            ? {16'h0, dmem_read_data_i[31:16]}
            : {16'h0, dmem_read_data_i[15:0]};

        // BUG FIX: was 'hx, which pushed X into the register file through the
        // load-forwarding mux whenever a non-load happened to sit in WB.
        default:
            wb_read_data_o = dmem_read_data_i;
    endcase
end

endmodule

`endif
