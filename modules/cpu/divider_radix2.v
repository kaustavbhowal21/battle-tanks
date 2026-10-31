`timescale 1ns/1ps
`ifndef DIVIDER_RADIX2_V
`define DIVIDER_RADIX2_V

module divider_radix2 (
    input  wire        clk,
    input  wire        reset_n,
    input  wire        start,
    input  wire [2:0]  funct3,
    input  wire [31:0] operand_a,
    input  wire [31:0] operand_b,
    output reg  [31:0] result,
    output wire        busy,
    output wire        ready
);

`include "opcode.vh"

    localparam IDLE    = 2'b00;
    localparam COMPUTE = 2'b01;
    localparam DONE    = 2'b10;

    reg [1:0]  state;
    reg [5:0]  count;

    reg [31:0] reg_q;
    reg [31:0] reg_r;
    reg [31:0] reg_b;

    reg        sign_q;
    reg        sign_r;
    reg [2:0]  saved_funct3;

    // Detect operation type
    wire is_signed = (funct3 == DIV) || (funct3 == REM);

    // Detect edge cases
    wire div_by_zero = (operand_b == 32'h0);
    wire overflow    = is_signed && (operand_a == 32'h8000_0000) && (operand_b == 32'hFFFF_FFFF);

    // Absolute values for signed division
    wire [31:0] abs_a = (is_signed && operand_a[31]) ? (-operand_a) : operand_a;
    wire [31:0] abs_b = (is_signed && operand_b[31]) ? (-operand_b) : operand_b;

    // Shift-and-subtract internal registers
    reg [63:0] working_dividend;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state        <= IDLE;
            count        <= 6'd0;
            reg_q        <= 32'd0;
            reg_r        <= 32'd0;
            reg_b        <= 32'd0;
            sign_q       <= 1'b0;
            sign_r       <= 1'b0;
            saved_funct3 <= 3'd0;
            working_dividend <= 64'd0;
        end else begin
            case (state)
                IDLE: begin
                    if (start) begin
                        saved_funct3 <= funct3;
                        if (div_by_zero) begin
                            // Division by zero shortcuts
                            state  <= DONE;
                            reg_q  <= 32'hFFFF_FFFF;
                            reg_r  <= operand_a;
                            sign_q <= 1'b0;
                            sign_r <= 1'b0;
                        end else if (overflow) begin
                            // Overflow shortcut
                            state  <= DONE;
                            reg_q  <= 32'h8000_0000;
                            reg_r  <= 32'h0;
                            sign_q <= 1'b0;
                            sign_r <= 1'b0;
                        end else begin
                            state            <= COMPUTE;
                            count            <= 6'd0;
                            reg_b            <= abs_b;
                            sign_q           <= is_signed ? (operand_a[31] ^ operand_b[31]) : 1'b0;
                            sign_r           <= is_signed ? operand_a[31] : 1'b0;
                            working_dividend <= {32'd0, abs_a};
                        end
                    end
                end

                COMPUTE: begin
                    // Radix-2 trial subtraction step
                    if (count < 6'd32) begin
                        if ({working_dividend[62:31]} >= reg_b) begin
                            working_dividend <= {working_dividend[62:31] - reg_b, working_dividend[30:0], 1'b1};
                        end else begin
                            working_dividend <= {working_dividend[62:0], 1'b0};
                        end
                        count <= count + 1'b1;
                    end else begin
                        state <= DONE;
                        reg_q <= working_dividend[31:0];
                        reg_r <= working_dividend[63:32];
                    end
                end

                DONE: begin
                    state <= IDLE;
                end

                default: state <= IDLE;
            endcase
        end
    end

    assign busy  = (state == COMPUTE) || (state == IDLE && start);
    assign ready = (state == DONE);

    // Format output with proper signs
    always @(*) begin
        case (saved_funct3)
            DIV:  result = sign_q ? (-reg_q) : reg_q;
            DIVU: result = reg_q;
            REM:  result = sign_r ? (-reg_r) : reg_r;
            REMU: result = reg_r;
            default: result = 32'h0;
        endcase
    end

endmodule
`endif