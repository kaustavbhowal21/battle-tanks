##=============================================================================
## Battle Tanks on Digilent Nexys A7-100T (Artix-7 XC7A100T-1CSG324C)
## Hardware Constraints (Clock, Reset, Pmod JA/JB breadboard buttons, LEDs, 12-bit VGA DAC)
##=============================================================================

## Clock Signal (100 MHz onboard oscillator)
set_property -dict { PACKAGE_PIN E3    IOSTANDARD LVCMOS33 } [get_ports { clk }];
create_clock -add -name sys_clk_pin -period 10.00 -waveform {0 5} [get_ports { clk }];

## clk_sys (50 MHz) is produced by a toggle flip-flop in top_fpga.v. Without this
## constraint Vivado leaves the whole CPU / game-engine / VGA domain UNCONSTRAINED,
## so timing violations would go unreported. Check WNS in the timing summary.
create_generated_clock -name clk_sys -source [get_ports { clk }] -divide_by 2 [get_pins -hierarchical -filter {NAME =~ *clk_sys_reg_reg/Q}];

## CPU Reset Button (Active Low CPU_RESETN red pushbutton)
set_property -dict { PACKAGE_PIN C12   IOSTANDARD LVCMOS33 } [get_ports { reset }];


## Status / Debug Telemetry LEDs (LD0..LD15)
set_property -dict { PACKAGE_PIN H17   IOSTANDARD LVCMOS33 } [get_ports { led[0] }];  # Wall Hit
set_property -dict { PACKAGE_PIN K15   IOSTANDARD LVCMOS33 } [get_ports { led[1] }];  # Bullet-Bullet Hit
set_property -dict { PACKAGE_PIN J13   IOSTANDARD LVCMOS33 } [get_ports { led[2] }];  # Tank Hit
set_property -dict { PACKAGE_PIN N14   IOSTANDARD LVCMOS33 } [get_ports { led[3] }];  # Exception (latched)
set_property -dict { PACKAGE_PIN R18   IOSTANDARD LVCMOS33 } [get_ports { led[4] }];  # P2 FWD (JB1)
set_property -dict { PACKAGE_PIN V17   IOSTANDARD LVCMOS33 } [get_ports { led[5] }];  # P2 BWD (JB2)
set_property -dict { PACKAGE_PIN U17   IOSTANDARD LVCMOS33 } [get_ports { led[6] }];  # P2 LEFT (JB3)
set_property -dict { PACKAGE_PIN U16   IOSTANDARD LVCMOS33 } [get_ports { led[7] }];  # P2 RIGHT (JB4)
set_property -dict { PACKAGE_PIN V16   IOSTANDARD LVCMOS33 } [get_ports { led[8] }];  # P1 FWD (JA1)
set_property -dict { PACKAGE_PIN T15   IOSTANDARD LVCMOS33 } [get_ports { led[9] }];  # P1 BWD (JA2)
set_property -dict { PACKAGE_PIN U14   IOSTANDARD LVCMOS33 } [get_ports { led[10] }]; # P1 LEFT (JA3)
set_property -dict { PACKAGE_PIN T16   IOSTANDARD LVCMOS33 } [get_ports { led[11] }]; # P1 RIGHT (JA4)
set_property -dict { PACKAGE_PIN V15   IOSTANDARD LVCMOS33 } [get_ports { led[12] }]; # P1 SHOOT (JA7)
set_property -dict { PACKAGE_PIN V14   IOSTANDARD LVCMOS33 } [get_ports { led[13] }]; # P1 SPECIAL (JA8)
set_property -dict { PACKAGE_PIN V12   IOSTANDARD LVCMOS33 } [get_ports { led[14] }]; # Game-loop heartbeat
set_property -dict { PACKAGE_PIN V11   IOSTANDARD LVCMOS33 } [get_ports { led[15] }]; # Clock heartbeat

## USB-HID Keyboard (via onboard PIC24 USB Host to PS/2 interface on Nexys A7)
## Plug standard USB keyboard into USB Host connector J5
set_property -dict { PACKAGE_PIN F4    IOSTANDARD LVCMOS33 PULLUP true } [get_ports { ps2_clk }];  # PS2_CLK
set_property -dict { PACKAGE_PIN B2    IOSTANDARD LVCMOS33 PULLUP true } [get_ports { ps2_data }]; # PS2_DATA

## Player 1 Controls: breadboard 1 (6 push buttons) wired to Pmod header JA
##   Breadboard 3.3V rail -> JA pin 6 (VCC).  Each button connects its JA pin to 3.3V
##   when pressed, so every input has an internal pull-down to read 0 when released.
##   (JA pins 5, 9, 10, 11, 12 are unused: 5 = GND, 11 = GND, 12 = VCC, 9/10 spare)
set_property -dict { PACKAGE_PIN C17   IOSTANDARD LVCMOS33 PULLDOWN true } [get_ports { p1_btn_raw[0] }]; # JA pin 1 - Button 1 (Forward)
set_property -dict { PACKAGE_PIN D18   IOSTANDARD LVCMOS33 PULLDOWN true } [get_ports { p1_btn_raw[1] }]; # JA pin 2 - Button 2 (Backward)
set_property -dict { PACKAGE_PIN E18   IOSTANDARD LVCMOS33 PULLDOWN true } [get_ports { p1_btn_raw[2] }]; # JA pin 3 - Button 3 (Turn Left)
set_property -dict { PACKAGE_PIN G17   IOSTANDARD LVCMOS33 PULLDOWN true } [get_ports { p1_btn_raw[3] }]; # JA pin 4 - Button 4 (Turn Right)
set_property -dict { PACKAGE_PIN D17   IOSTANDARD LVCMOS33 PULLDOWN true } [get_ports { p1_btn_raw[4] }]; # JA pin 7 - Button 5 (Shoot)
set_property -dict { PACKAGE_PIN E17   IOSTANDARD LVCMOS33 PULLDOWN true } [get_ports { p1_btn_raw[5] }]; # JA pin 8 - Button 6 (Special Attack)

## Player 2 Controls: breadboard 2 (6 push buttons) wired to Pmod header JB
##   Same layout as JA: 3.3V rail -> JB pin 6 (VCC), buttons on pins 1, 2, 3, 4, 7, 8.
set_property -dict { PACKAGE_PIN D14   IOSTANDARD LVCMOS33 PULLDOWN true } [get_ports { p2_btn_raw[0] }]; # JB pin 1 - Button 1 (Forward)
set_property -dict { PACKAGE_PIN F16   IOSTANDARD LVCMOS33 PULLDOWN true } [get_ports { p2_btn_raw[1] }]; # JB pin 2 - Button 2 (Backward)
set_property -dict { PACKAGE_PIN G16   IOSTANDARD LVCMOS33 PULLDOWN true } [get_ports { p2_btn_raw[2] }]; # JB pin 3 - Button 3 (Turn Left)
set_property -dict { PACKAGE_PIN H14   IOSTANDARD LVCMOS33 PULLDOWN true } [get_ports { p2_btn_raw[3] }]; # JB pin 4 - Button 4 (Turn Right)
set_property -dict { PACKAGE_PIN E16   IOSTANDARD LVCMOS33 PULLDOWN true } [get_ports { p2_btn_raw[4] }]; # JB pin 7 - Button 5 (Shoot)
set_property -dict { PACKAGE_PIN F13   IOSTANDARD LVCMOS33 PULLDOWN true } [get_ports { p2_btn_raw[5] }]; # JB pin 8 - Button 6 (Special Attack)

## 12-Bit VGA Output (VGA Connector J2)
set_property -dict { PACKAGE_PIN A3    IOSTANDARD LVCMOS33 } [get_ports { vga_r[0] }];
set_property -dict { PACKAGE_PIN B4    IOSTANDARD LVCMOS33 } [get_ports { vga_r[1] }];
set_property -dict { PACKAGE_PIN C5    IOSTANDARD LVCMOS33 } [get_ports { vga_r[2] }];
set_property -dict { PACKAGE_PIN A4    IOSTANDARD LVCMOS33 } [get_ports { vga_r[3] }];

set_property -dict { PACKAGE_PIN C6    IOSTANDARD LVCMOS33 } [get_ports { vga_g[0] }];
set_property -dict { PACKAGE_PIN A5    IOSTANDARD LVCMOS33 } [get_ports { vga_g[1] }];
set_property -dict { PACKAGE_PIN B6    IOSTANDARD LVCMOS33 } [get_ports { vga_g[2] }];
set_property -dict { PACKAGE_PIN A6    IOSTANDARD LVCMOS33 } [get_ports { vga_g[3] }];

set_property -dict { PACKAGE_PIN B7    IOSTANDARD LVCMOS33 } [get_ports { vga_b[0] }];
set_property -dict { PACKAGE_PIN C7    IOSTANDARD LVCMOS33 } [get_ports { vga_b[1] }];
set_property -dict { PACKAGE_PIN D7    IOSTANDARD LVCMOS33 } [get_ports { vga_b[2] }];
set_property -dict { PACKAGE_PIN D8    IOSTANDARD LVCMOS33 } [get_ports { vga_b[3] }];

set_property -dict { PACKAGE_PIN B11   IOSTANDARD LVCMOS33 } [get_ports { vga_hsync }];
set_property -dict { PACKAGE_PIN B12   IOSTANDARD LVCMOS33 } [get_ports { vga_vsync }];

## PWM Audio Output (Nexys A7 Mono Audio Jack J8)
set_property -dict { PACKAGE_PIN A11   IOSTANDARD LVCMOS33 } [get_ports { aud_pwm }];
set_property -dict { PACKAGE_PIN D12   IOSTANDARD LVCMOS33 } [get_ports { aud_sd }];

## 8-Digit 7-Segment Display (DISP1 & DISP2 Combined: RED WON / BLUE WON / DRAW)
set_property -dict { PACKAGE_PIN T10   IOSTANDARD LVCMOS33 } [get_ports { seg[0] }]; # CA
set_property -dict { PACKAGE_PIN R10   IOSTANDARD LVCMOS33 } [get_ports { seg[1] }]; # CB
set_property -dict { PACKAGE_PIN K16   IOSTANDARD LVCMOS33 } [get_ports { seg[2] }]; # CC
set_property -dict { PACKAGE_PIN K13   IOSTANDARD LVCMOS33 } [get_ports { seg[3] }]; # CD
set_property -dict { PACKAGE_PIN P15   IOSTANDARD LVCMOS33 } [get_ports { seg[4] }]; # CE
set_property -dict { PACKAGE_PIN T11   IOSTANDARD LVCMOS33 } [get_ports { seg[5] }]; # CF
set_property -dict { PACKAGE_PIN L18   IOSTANDARD LVCMOS33 } [get_ports { seg[6] }]; # CG
set_property -dict { PACKAGE_PIN H15   IOSTANDARD LVCMOS33 } [get_ports { dp }];     # DP

set_property -dict { PACKAGE_PIN J17   IOSTANDARD LVCMOS33 } [get_ports { an[0] }];  # AN0 (DISP2 digit 0)
set_property -dict { PACKAGE_PIN J18   IOSTANDARD LVCMOS33 } [get_ports { an[1] }];  # AN1 (DISP2 digit 1)
set_property -dict { PACKAGE_PIN T9    IOSTANDARD LVCMOS33 } [get_ports { an[2] }];  # AN2 (DISP2 digit 2)
set_property -dict { PACKAGE_PIN J14   IOSTANDARD LVCMOS33 } [get_ports { an[3] }];  # AN3 (DISP2 digit 3)
set_property -dict { PACKAGE_PIN P14   IOSTANDARD LVCMOS33 } [get_ports { an[4] }];  # AN4 (DISP1 digit 4)
set_property -dict { PACKAGE_PIN T14   IOSTANDARD LVCMOS33 } [get_ports { an[5] }];  # AN5 (DISP1 digit 5)
set_property -dict { PACKAGE_PIN K2    IOSTANDARD LVCMOS33 } [get_ports { an[6] }];  # AN6 (DISP1 digit 6)
set_property -dict { PACKAGE_PIN U13   IOSTANDARD LVCMOS33 } [get_ports { an[7] }];  # AN7 (DISP1 digit 7)

## USB-UART Interface (FPGA transmits to PC via FT2232HQ USB-UART bridge)
set_property -dict { PACKAGE_PIN D4    IOSTANDARD LVCMOS33 } [get_ports { uart_tx }]; # UART_RXD_OUT (PC reads this)
