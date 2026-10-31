//=============================================================================
// OPCODE and Parameter Definitions (RV32I + RV32M Extensions)
//=============================================================================

// ----------------------------------------------------------------------------
// Instruction Field Slices
// ----------------------------------------------------------------------------
`define OPCODE      6:0
`define RD          11:7
`define FUNC3       14:12
`define RS1         19:15
`define RS2         24:20
`define FUNC7       31:25
`define SUBTYPE     30

// ----------------------------------------------------------------------------
// Standard Pseudo-Instructions
// ----------------------------------------------------------------------------
localparam [31:0] NOP        = 32'h0000_0013;    // addi x0, x0, 0

// ----------------------------------------------------------------------------
// Base RV32I Opcodes (INST[6:0])
// ----------------------------------------------------------------------------
localparam [6:0]  LUI        = 7'b0110111,       // U-type
                  AUIPC      = 7'b0010111,       // U-type
                  JAL        = 7'b1101111,       // J-type
                  JALR       = 7'b1100111,       // I-type
                  BRANCH     = 7'b1100011,       // B-type
                  LOAD       = 7'b0000011,       // I-type
                  STORE      = 7'b0100011,       // S-type
                  ARITHI     = 7'b0010011,       // I-type
                  ARITHR     = 7'b0110011;       // R-type (Shared with RV32M)

// ----------------------------------------------------------------------------
// Branch Conditions: FUNC3, INST[14:12] when OPCODE == BRANCH (7'b1100011)
// ----------------------------------------------------------------------------
localparam [2:0]  BEQ        = 3'b000,
                  BNE        = 3'b001,
                  BLT        = 3'b100,
                  BGE        = 3'b101,
                  BLTU       = 3'b110,
                  BGEU       = 3'b111;

// ----------------------------------------------------------------------------
// Load Types: FUNC3, INST[14:12] when OPCODE == LOAD (7'b0000011)
// ----------------------------------------------------------------------------
localparam [2:0]  LB         = 3'b000,
                  LH         = 3'b001,
                  LW         = 3'b010,
                  LBU        = 3'b100,
                  LHU        = 3'b101;

// ----------------------------------------------------------------------------
// Store Types: FUNC3, INST[14:12] when OPCODE == STORE (7'b0100011)
// ----------------------------------------------------------------------------
localparam [2:0]  SB         = 3'b000,
                  SH         = 3'b001,
                  SW         = 3'b010;

// ----------------------------------------------------------------------------
// RV32I ALU Operations: FUNC3, INST[14:12] when OPCODE == ARITHR or ARITHI
// ----------------------------------------------------------------------------
localparam [2:0]  ADD        = 3'b000,   // inst[30] == 0: ADD,  inst[30] == 1: SUB
                  SLL        = 3'b001,
                  SLT        = 3'b010,
                  SLTU       = 3'b011,
                  XOR        = 3'b100,
                  SR         = 3'b101,   // inst[30] == 0: SRL,  inst[30] == 1: SRA
                  OR         = 3'b110,
                  AND        = 3'b111;

// ----------------------------------------------------------------------------
// RV32M Extension Definitions
// Both RV32I ARITHR and RV32M use OPCODE == 7'b0110011.
// They are distinguished using the FUNC7 field (INST[31:25]):
//   - RV32I Standard : FUNC7 == 7'b0000000 (or 7'b0100000 for SUB/SRA)
//   - RV32M Extension: FUNC7 == 7'b0000001
// ----------------------------------------------------------------------------
localparam [6:0]  FUNC7_RV32I   = 7'b0000000,
                  FUNC7_RV32I_ALT = 7'b0100000,
                  FUNC7_RV32M   = 7'b0000001;

// RV32M Operations: FUNC3, INST[14:12] when OPCODE == ARITHR && FUNC7 == FUNC7_RV32M
localparam [2:0]  MUL        = 3'b000,   // Lower 32 bits of (signed x signed)
                  MULH       = 3'b001,   // Upper 32 bits of (signed x signed)
                  MULHSU     = 3'b010,   // Upper 32 bits of (signed x unsigned)
                  MULHU      = 3'b011,   // Upper 32 bits of (unsigned x unsigned)
                  DIV        = 3'b100,   // Signed division
                  DIVU       = 3'b101,   // Unsigned division
                  REM        = 3'b110,   // Signed remainder
                  REMU       = 3'b111;   // Unsigned remainder