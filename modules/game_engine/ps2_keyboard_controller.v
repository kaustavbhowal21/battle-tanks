`timescale 1ns / 1ps
//=============================================================================
// Battle Tanks: PS/2 Keyboard Controller for USB HID Keyboard
//
// Hardware Context:
//   On the Digilent Nexys A7-100T (and Nexys 4 DDR) FPGA board, the onboard
//   Microchip PIC24FJ128 microcontroller functions as a USB HID host connected
//   to the USB Host connector (J5, Type-A). When a standard USB keyboard is
//   plugged into J5, the PIC24 translates USB HID boot keyboard reports into
//   standard PS/2 serial signals and sends them to the FPGA on:
//     - PS2_CLK  : Package pin F4
//     - PS2_DATA : Package pin B2
//
// Controller Architecture:
//   1. 2-FF Metastability Synchronizer + 16-sample Glitch Filter
//   2. 11-bit PS/2 Frame Receiver with Odd Parity and Framing Validation
//   3. Inactivity Watchdog Timer (~3 ms timeout) to recover from dropped clocks
//   4. PS/2 Scancode Set 2 Decoder (Make codes, Break 'F0', Extended 'E0')
//   5. Independent Key State Flip-Flops for True N-Key Rollover
//
// Two-Player Control Mapping (Single Keyboard):
//   Player 1 (Left side of keyboard):
//     - Move Forward  : W     (0x1D)
//     - Move Backward : S     (0x1B)
//     - Turn Left     : A     (0x1C)
//     - Turn Right    : D     (0x23)
//     - Primary Shoot : Space (0x29) or F (0x2B)
//     - Special Weapon: E     (0x24) or Q (0x15)
//
//   Player 2 (Right side of keyboard):
//     - Move Forward  : Up Arrow    (E0 75) or I (0x43)
//     - Move Backward : Down Arrow  (E0 72) or K (0x42)
//     - Turn Left     : Left Arrow  (E0 6B) or J (0x3B)
//     - Turn Right    : Right Arrow (E0 74) or L (0x4B)
//     - Primary Shoot : Enter       (0x5A)  or Slash / (0x4A) or O (0x44)
//     - Special Weapon: Right Shift (0x59)  or P (0x4D)       or Dot . (0x49)
//=============================================================================
`ifndef PS2_KEYBOARD_CONTROLLER_V
`define PS2_KEYBOARD_CONTROLLER_V

module ps2_keyboard_controller #(
    parameter CLK_FREQ_HZ = 50_000_000,
    parameter FILTER_BITS = 4            // 16 clocks @ 50 MHz = 320 ns glitch rejection
)(
    input  wire        clk,              // 50 MHz system clock
    input  wire        reset_n,          // Active-low asynchronous reset
    input  wire        ps2_clk,          // Raw PS2_CLK from FPGA pin F4
    input  wire        ps2_data,         // Raw PS2_DATA from FPGA pin B2

    // Decoded Player Control Vectors (Active-High):
    // [0]=FWD, [1]=BWD, [2]=LEFT, [3]=RIGHT, [4]=SHOOT, [5]=SPECIAL
    output wire [5:0]  p1_controls,
    output wire [5:0]  p2_controls,

    // Diagnostics / Telemetry
    output reg  [7:0]  last_scancode,
    output reg         key_event_strobe,
    output reg         rx_err
);

    // =========================================================================
    // 1. Metastability Synchronizer & Glitch Filter
    // =========================================================================
    reg [1:0] clk_sync;
    reg [1:0] data_sync;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            clk_sync  <= 2'b11;
            data_sync <= 2'b11;
        end else begin
            // Treat unconstrained/floating 'z' or 'x' in simulation as idle high (1'b1)
            clk_sync  <= {clk_sync[0],  (ps2_clk === 1'b0)  ? 1'b0 : 1'b1};
            data_sync <= {data_sync[0], (ps2_data === 1'b0) ? 1'b0 : 1'b1};
        end
    end

    reg [FILTER_BITS-1:0] clk_filter_cnt;
    reg                   ps2_clk_clean;
    reg                   ps2_clk_clean_q;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            clk_filter_cnt  <= {FILTER_BITS{1'b0}};
            ps2_clk_clean   <= 1'b1;
            ps2_clk_clean_q <= 1'b1;
        end else begin
            ps2_clk_clean_q <= ps2_clk_clean;
            if (clk_sync[1] == ps2_clk_clean) begin
                clk_filter_cnt <= {FILTER_BITS{1'b0}};
            end else begin
                clk_filter_cnt <= clk_filter_cnt + 1'b1;
                if (&clk_filter_cnt) begin
                    ps2_clk_clean  <= clk_sync[1];
                    clk_filter_cnt <= {FILTER_BITS{1'b0}};
                end
            end
        end
    end

    wire ps2_clk_fall = (ps2_clk_clean_q && !ps2_clk_clean);

    // =========================================================================
    // 2. PS/2 Frame Receiver with Parity & Framing Validation
    // =========================================================================
    // Standard PS/2 Frame (11 bits total, LSB first):
    //   Bit 0 : Start bit (0)
    //   Bit 1..8 : Data byte (D0..D7)
    //   Bit 9 : Odd Parity bit
    //   Bit 10 : Stop bit (1)
    //
    // shift_reg shifts right: new bit enters at shift_reg[10].
    // At the moment bit_cnt == 10:
    //   shift_reg[1]    = Start bit (must be 0)
    //   shift_reg[9:2]  = Data byte {D7..D0}
    //   shift_reg[10]   = Parity bit
    //   data_sync[1]    = Incoming Stop bit (must be 1)
    // =========================================================================
    reg [10:0] shift_reg;
    reg [3:0]  bit_cnt;
    reg [18:0] timeout_cnt;
    reg        rx_done;
    reg [7:0]  rx_byte;

    // 3 ms watchdog timeout @ 50 MHz (150,000 cycles) to clear incomplete packets
    localparam [18:0] WATCHDOG_MAX = 19'd150_000;
    wire frame_timeout = (timeout_cnt >= WATCHDOG_MAX);

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            shift_reg   <= 11'd0;
            bit_cnt     <= 4'd0;
            timeout_cnt <= 19'd0;
            rx_done     <= 1'b0;
            rx_byte     <= 8'd0;
            rx_err      <= 1'b0;
        end else begin
            rx_done <= 1'b0;

            if (ps2_clk_fall) begin
                timeout_cnt <= 19'd0;
                shift_reg   <= {data_sync[1], shift_reg[10:1]};

                if (bit_cnt == 4'd10) begin
                    bit_cnt <= 4'd0;
                    // Framing check: start=0, stop=1, and odd parity over 8 data bits + parity bit
                    if ((shift_reg[1] == 1'b0) && (data_sync[1] == 1'b1) && (^shift_reg[10:2] == 1'b1)) begin
                        rx_byte <= shift_reg[9:2];
                        rx_done <= 1'b1;
                        rx_err  <= 1'b0;
                    end else begin
                        rx_err  <= 1'b1;
                    end
                end else begin
                    bit_cnt <= bit_cnt + 4'd1;
                end
            end else begin
                // Inactivity timeout counter
                if (bit_cnt != 4'd0) begin
                    if (frame_timeout) begin
                        bit_cnt     <= 4'd0;
                        timeout_cnt <= 19'd0;
                        rx_err      <= 1'b1;
                    end else begin
                        timeout_cnt <= timeout_cnt + 19'd1;
                    end
                end else begin
                    timeout_cnt <= 19'd0;
                end
            end
        end
    end

    // =========================================================================
    // 3. PS/2 Scancode Set 2 Decoder & Key State Registers
    // =========================================================================
    // Scancode Set 2 constants:
    localparam [7:0] SCAN_EXTENDED = 8'hE0;
    localparam [7:0] SCAN_BREAK    = 8'hF0;

    // Player 1 Keys
    localparam [7:0] SCAN_W        = 8'h1D;
    localparam [7:0] SCAN_A        = 8'h1C;
    localparam [7:0] SCAN_S        = 8'h1B;
    localparam [7:0] SCAN_D        = 8'h23;
    localparam [7:0] SCAN_SPACE    = 8'h29;
    localparam [7:0] SCAN_F        = 8'h2B;
    localparam [7:0] SCAN_E        = 8'h24;
    localparam [7:0] SCAN_Q        = 8'h15;

    // Player 2 Navigation (Extended Arrow Keys)
    localparam [7:0] SCAN_UP       = 8'h75;
    localparam [7:0] SCAN_DOWN     = 8'h72;
    localparam [7:0] SCAN_LEFT     = 8'h6B;
    localparam [7:0] SCAN_RIGHT    = 8'h74;

    // Player 2 Alternative (IJKL)
    localparam [7:0] SCAN_I        = 8'h43;
    localparam [7:0] SCAN_K        = 8'h42;
    localparam [7:0] SCAN_J        = 8'h3B;
    localparam [7:0] SCAN_L        = 8'h4B;

    // Player 2 Action Keys
    localparam [7:0] SCAN_ENTER    = 8'h5A; // Main Enter or Numpad Enter
    localparam [7:0] SCAN_SLASH    = 8'h4A; // Main Slash or Numpad /
    localparam [7:0] SCAN_O        = 8'h44; // O key
    localparam [7:0] SCAN_RSHFT    = 8'h59; // Right Shift
    localparam [7:0] SCAN_P        = 8'h4D; // P key
    localparam [7:0] SCAN_DOT      = 8'h49; // Main Period .
    localparam [7:0] SCAN_NUM0     = 8'h70; // Numpad 0 (Insert)
    localparam [7:0] SCAN_NUMDOT   = 8'h71; // Numpad . (Delete)

    reg is_extended;
    reg is_break;

    // Individual Key State Latches (High when key is held down)
    reg key_w, key_s, key_a, key_d, key_space, key_f, key_e, key_q;
    reg key_up, key_down, key_left, key_right;
    reg key_i, key_k, key_j, key_l;
    reg key_enter, key_slash, key_o;
    reg key_rshift, key_p, key_dot;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            is_extended      <= 1'b0;
            is_break         <= 1'b0;
            last_scancode    <= 8'd0;
            key_event_strobe <= 1'b0;

            key_w            <= 1'b0;
            key_s            <= 1'b0;
            key_a            <= 1'b0;
            key_d            <= 1'b0;
            key_space        <= 1'b0;
            key_f            <= 1'b0;
            key_e            <= 1'b0;
            key_q            <= 1'b0;

            key_up           <= 1'b0;
            key_down         <= 1'b0;
            key_left         <= 1'b0;
            key_right        <= 1'b0;
            key_i            <= 1'b0;
            key_k            <= 1'b0;
            key_j            <= 1'b0;
            key_l            <= 1'b0;
            key_enter        <= 1'b0;
            key_slash        <= 1'b0;
            key_o            <= 1'b0;
            key_rshift       <= 1'b0;
            key_p            <= 1'b0;
            key_dot          <= 1'b0;
        end else begin
            key_event_strobe <= 1'b0;

            // Inactivity timeout resets prefix state so receiver never hangs
            if (frame_timeout) begin
                is_extended <= 1'b0;
                is_break    <= 1'b0;
            end

            if (rx_done) begin
                last_scancode    <= rx_byte;
                key_event_strobe <= 1'b1;

                if (rx_byte == SCAN_EXTENDED) begin
                    is_extended <= 1'b1;
                end else if (rx_byte == SCAN_BREAK) begin
                    is_break <= 1'b1;
                end else begin
                    // Determine key action: 1 = pressed (make), 0 = released (break)
                    // (Typematic repeat automatically maintains 1)
                    if (is_extended) begin
                        // Extended Scancodes (Arrow keys, Numpad Enter, etc.)
                        case (rx_byte)
                            SCAN_UP:    key_up    <= ~is_break;
                            SCAN_DOWN:  key_down  <= ~is_break;
                            SCAN_LEFT:  key_left  <= ~is_break;
                            SCAN_RIGHT: key_right <= ~is_break;
                            SCAN_ENTER: key_enter <= ~is_break; // Numpad Enter
                            SCAN_SLASH: key_slash <= ~is_break; // Numpad /
                            default: ;
                        endcase
                    end else begin
                        // Standard Scancodes
                        case (rx_byte)
                            // Player 1 Keys
                            SCAN_W:     key_w     <= ~is_break;
                            SCAN_S:     key_s     <= ~is_break;
                            SCAN_A:     key_a     <= ~is_break;
                            SCAN_D:     key_d     <= ~is_break;
                            SCAN_SPACE: key_space <= ~is_break;
                            SCAN_F:     key_f     <= ~is_break;
                            SCAN_E:     key_e     <= ~is_break;
                            SCAN_Q:     key_q     <= ~is_break;

                            // Player 2 Keys
                            SCAN_I:     key_i     <= ~is_break;
                            SCAN_K:     key_k     <= ~is_break;
                            SCAN_J:     key_j     <= ~is_break;
                            SCAN_L:     key_l     <= ~is_break;
                            SCAN_ENTER: key_enter <= ~is_break; // Main Enter
                            SCAN_SLASH: key_slash <= ~is_break;
                            SCAN_O:     key_o     <= ~is_break;
                            SCAN_RSHFT: key_rshift<= ~is_break;
                            SCAN_P:     key_p     <= ~is_break;
                            SCAN_DOT:   key_dot   <= ~is_break;
                            SCAN_NUM0:  key_enter <= ~is_break;
                            SCAN_NUMDOT:key_dot   <= ~is_break;
                            default: ;
                        endcase
                    end

                    // Clear prefix modifiers after handling the key code
                    is_extended <= 1'b0;
                    is_break    <= 1'b0;
                end
            end
        end
    end

    // =========================================================================
    // 4. Output Vector Assembly
    // =========================================================================
    // Player 1 Vector:
    //   [0] = FWD    (W)
    //   [1] = BWD    (S)
    //   [2] = LEFT   (A)
    //   [3] = RIGHT  (D)
    //   [4] = SHOOT  (Space or F)
    //   [5] = SPEC   (E or Q)
    assign p1_controls = {
        key_e | key_q,                 // [5] SPECIAL
        key_space | key_f,             // [4] SHOOT
        key_d,                         // [3] RIGHT
        key_a,                         // [2] LEFT
        key_s,                         // [1] BWD
        key_w                          // [0] FWD
    };

    // Player 2 Vector:
    //   [0] = FWD    (Up Arrow or I)
    //   [1] = BWD    (Down Arrow or K)
    //   [2] = LEFT   (Left Arrow or J)
    //   [3] = RIGHT  (Right Arrow or L)
    //   [4] = SHOOT  (Enter or Slash / or O)
    //   [5] = SPEC   (Right Shift or P or Dot .)
    assign p2_controls = {
        key_rshift | key_p | key_dot,  // [5] SPECIAL
        key_enter | key_slash | key_o, // [4] SHOOT
        key_right | key_l,             // [3] RIGHT
        key_left  | key_j,             // [2] LEFT
        key_down  | key_k,             // [1] BWD
        key_up    | key_i              // [0] FWD
    };

endmodule

`endif

