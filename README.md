# Hardware-Accelerated 2D Battle Tanks with Real-Time Reflection Physics on an RV32IM FPGA Soft-Core

**Course:** CSE Semester 3 — Hardware Laboratory Project  
**Group Number:** 3  
**Team Members:** Kaustav Bhowal, Kabir Gupta, Jayesh Vijaivargia, Mahendra, Jayesh Banzal  
**Target Platform:** Digilent Nexys A7-100T (Xilinx Artix-7 `XC7A100T-1CSG324C` FPGA)  
**Display Output:** 640×480 @ 60 Hz VGA (12-bit RGB DAC, 4,096 colors)  
**Processor Core:** Custom 3-Stage Pipelined `RV32IM` RISC-V Soft-Core (`IF/ID` $\rightarrow$ `EX` $\rightarrow$ `WB`) @ 50 MHz  

---

## Table of Contents

1. [Project Overview](#1-project-overview)
2. [The Game: Display Layout, Rules, Actions & How to Win](#2-the-game-display-layout-rules-actions--how-to-win)
3. [Running the Project on Any Laptop (Requirements, Setup & File Changes)](#3-running-the-project-on-any-laptop-requirements-setup--file-changes)
4. [Detailed Hardware Accelerations Implemented](#4-detailed-hardware-accelerations-implemented)

---

## 1. Project Overview

**Battle Tanks** is a real-time, two-player 2D tank combat game built from the ground up as a hardware-software co-design on an FPGA. At the heart of the system is a custom **32-bit RISC-V (`RV32IM`) soft-core processor** running at **50 MHz**, which executes an embedded C game program (`software/`) responsible for high-level game rules, Q24.8 fixed-point trigonometry, 2D projectile reflection physics, and arena state management.

On a baseline soft-core processor without hardware support, software-based frame-buffer rendering, multi-object bounding-box collision checks, and software division/multiplication would severely bottleneck the CPU and drop frame rates below playable levels. To achieve a rock-solid **60 FPS game loop** and **zero-tearing 640×480 @ 60 Hz VGA video**, our architecture extends the processor ISA with **hardware multiplication and division (`RV32M`)** and offloads all pixel-rate, timer-rate, and parallel intersection tasks to **memory-mapped hardware accelerators (`0x8000_0000`–`0x8000_073F`)**:

* **Custom 3-Stage RV32IM Soft-Core (`modules/cpu/`):** Implements the base `RV32I` instruction set (including `AUIPC` for GCC PC-relative addressing) plus the `RV32M` extension featuring a single-cycle DSP48E1 multiplier and a 32-cycle non-restoring radix-2 divider with automatic pipeline stall and writeback bubble injection.
* **Real-Time Racing-the-Beam VGA Subsystem (`modules/vga/`):** Generates 640×480 @ 60 Hz video on the fly at 25 MHz without a frame buffer. Hardware engines independently rasterize the 20×20 maze grid, two 16-angle rotating tank sprites, 8 circular bullet discs, and a 2×20-heart health HUD, compositing them through a pipelined pixel priority mixer.
* **Parallel Hardware Collision Engine (`modules/game_engine/collision_engine.v`):** Evaluates 28 bullet-bullet Axis-Aligned Bounding Box (AABB) pairs and 16 bullet-tank AABB pairs every single clock cycle in parallel, alongside an 8-clock time-shared bullet-wall scanner, latching hits into Write-1-to-Clear (W1C) sticky registers.
* **Contention-Free Mirrored Maze BRAM (`modules/game_engine/maze_tile_ram.v`):** Uses two identical dual-port memories (**Copy V** for VGA rendering and **Copy C** for hardware collision scanning) written simultaneously by the CPU on Port A so that CPU updates, video rasterization, and collision scanning never stall one another.
* **Hardware Cooldown Timers, Low-Latency Input Debouncers & Autonomous PWM Audio (`modules/game_engine/`, `modules/audio/`):** Provides hardware countdown timers for weapon reload rates, 2-FF synchronized button debouncers with a 20 ms minimum-hold latch, and a zero-CPU-overhead PWM sound synthesizer that sniffs hardware game events in real time.

### Repository Directory Structure

```text
battle-tanks/
├── README.md                          # Complete project documentation & setup guide
├── run_sim.bat                        # 1-Click full-system build and XSim simulation script
├── run_game_engine_tests.bat          # Batch runner for all 7 Game Engine testbenches
├── run_vga_tests.bat                  # Batch runner for all 5 VGA subsystem testbenches
│
├── diagrams/                          # Architecture block diagrams, timing diagrams & slides
│   ├── block_diagram.pdf / .docx
│   ├── timing_diagram.pdf
│   └── presentation.pdf
│
├── modules/
│   ├── top_fpga.v                     # Top-level FPGA integration (clocks, CPU, MMIO, VGA, LEDs)
│   ├── constraints.xdc                # Digilent Nexys A7-100T pin constraints
│   ├── cpu/                           # 3-Stage RV32IM Soft-Core Processor
│   │   ├── pipeline.v                 # Pipeline top-level (IF/ID -> EX -> WB)
│   │   ├── IF_ID.v                    # Fetch, decode, skid buffer, regfile & immediate gen
│   │   ├── execute.v                  # ALU, branch unit & RV32M integration
│   │   ├── wb.v                       # Writeback, load sign-extension & store byte-lane align
│   │   ├── memory.v                   # 4 KB Instruction ROM & 4 KB Data RAM (Block RAM)
│   │   ├── multiplier_dsp.v           # Single-cycle 33x33 signed/unsigned DSP multiplier
│   │   ├── divider_radix2.v           # 32-cycle non-restoring radix-2 divider/remainder unit
│   │   ├── top_rv32m.v                # RV32M wrapper & pipeline stall controller
│   │   ├── opcode.vh                  # RISC-V opcodes, funct3 & funct7 constants
│   │   └── firmware_imem.vh / dmem.vh # Auto-generated synthesizable firmware headers
│   ├── game_engine/                   # Memory-Mapped Hardware Peripherals
│   │   ├── mmio_interconnect.v        # Split read/write address decoder & registered read mux
│   │   ├── collision_engine.v         # 28 BB AABB, 16 BTK AABB, 8-clk wall scan & W1C regs
│   │   ├── cooldown_timers.v          # Shared 1 ms prescaler & 4 weapon cooldown counters
│   │   ├── sprite_hud_regfile.v       # 12x 32-bit live sprite coordinate & HUD registers
│   │   ├── input_controller.v         # 12-channel 2-FF sync, 3 ms debouncer & 20 ms hold latch
│   │   └── maze_tile_ram.v            # Mirrored dual-port 20x20x2b Maze RAM (Copy V & Copy C)
│   ├── vga/                           # 640x480 @ 60 Hz Display Pipeline
│   │   ├── vga_timing_gen.v           # 800x525 raster counters, HSync, VSync & active flags
│   │   ├── maze_tile_renderer.v       # 20x20 grid (24x24 px tiles) bevel/brick/floor shader
│   │   ├── sprite_engine.v            # 16-angle tank barrel projection & circular bullet discs
│   │   ├── health_hud.v               # Right-hand 160x480 HUD strip & 8x8 heart sprite ROM
│   │   └── pixel_priority_mixer.v     # 6-layer priority compositor & 2-FF sync delay line
│   ├── audio/
│   │   └── sound_engine.v             # Autonomous hardware event sniffer & PWM audio synth
│   └── sim/                           # 16 Module, Subsystem & Full-System Testbenches
│
├── software/                          # Embedded C Game Firmware (RV32IM)
│   ├── build_and_export.py            # Automated GCC compiler, hex exporter & .vh generator
│   ├── build.bat                      # Windows batch wrapper for firmware build
│   ├── crt0.s                         # Bare-metal RISC-V startup assembly (stack & BSS init)
│   ├── linker.ld                      # Linker script (4 KB IMEM @ 0x0, 4 KB DMEM @ 0x0)
│   ├── include/                       # Headers: game.h, physics.h, mmio.h
│   ├── src/                           # Sources: main.c, game.c, physics.c
│   └── tests/test_game.c              # 129-assertion host C unit test suite
│
└── testing/                           # Automated Python Verification Suites
    ├── run_all_game_engine_tests.py   # Runs all 7 Game Engine testbenches in Vivado XSim
    ├── run_all_vga_tests.py           # Runs all 5 VGA testbenches in Vivado XSim
    └── RV32IM/                        # Standalone CPU ISA test suite (MUL, DIV, AUIPC, ALL)
```

---

## 2. The Game: Display Layout, Rules, Actions & How to Win

### A. What is Displayed on the VGA Screen (640×480 @ 60 Hz)

The 640×480 screen is divided into two distinct regions separated by a vertical steel divider bar at $x = 479..480$:

1. **The Combat Arena (Left `480×480` Pixels — `20×20` Grid of `24×24` Pixel Tiles):**
   * **Indestructible Steel Walls (Gray with 3D Beveled Borders):** Form the outer perimeter border (rows `0` and `19`, columns `0` and `19`) and interior pillar obstacles placed at every 4th row and column (`r % 4 == 0 && c % 4 == 0`). Bullets bounce off steel walls without damaging them.
   * **Destructible Brick Walls (Orange-Red Bricks with Mortar Grooves):** Placed in the center of the arena (`row = 10, cols = 8..11`) as breakable cover. When struck by any bullet, the brick shatters into open floor while reflecting the bullet.
   * **Arena Floor (Dark Tactical Green with Subtle Grid Lines):** Open navigable terrain where tanks drive and projectiles fly.
   * **Player 1 Tank (Top-Left Spawn at `(48, 48)`, Facing East):** A `20×20` pixel armored tank rendered with dark/medium green treads, an olive/green hull, a bright green turret dome, and a dynamic gun barrel that rotates smoothly across **16 discrete angles** ($0^\circ$ to $337.5^\circ$ in $22.5^\circ$ increments).
   * **Player 2 Tank (Bottom-Right Spawn at `(410, 410)`, Facing West):** A `20×20` pixel crimson/red armored tank with dark red treads, a bright red turret dome, and its own 16-angle rotating barrel.
   * **Normal Bullets (`6×6` Bright Yellow Circular Discs):** High-speed primary projectiles (6 pixels/frame).
   * **Special "Big" Bullets (`10×10` Fiery Orange-Red Circular Discs):** Heavy cannon projectiles (4 pixels/frame) with a larger hitbox and triple damage.

2. **The Heads-Up Display / Health HUD (Right `160×480` Pixels, $x = 480..639$):**
   * **Player 1 Status Strip (Top Right):** Displays a green Player 1 header banner (`y = 20..27`) above a row of **20 heart icons** (`y = 32..39`, each `8×8` pixels). Active health points are drawn as bright crimson hearts with white specular highlights; lost health points turn into dark depleted heart outlines.
   * **Player 2 Status Strip (Bottom Right):** Displays a red Player 2 header banner (`y = 420..427`) above Player 2's row of **20 heart icons** (`y = 432..439`).

---

### B. What Actions Players Can Perform

Each player has **6 independent controls** and can perform the following maneuvers simultaneously in real time:

1. **Rotate Turret & Hull in 16 Directions (`LEFT` / `RIGHT`):**
   * Rotate counter-clockwise or clockwise in $22.5^\circ$ steps ($360^\circ / 16$).
   * Rotation wraps cleanly around $360^\circ$ (`angle = (angle ± 1) & 0xF`).
2. **Drive Forward & Reverse (`FWD` / `BWD`):**
   * Move forward or backward along the exact 16-angle heading vector using Q24.8 fixed-point trigonometry ($\Delta x, \Delta y$ computed via hardware `MUL`).
   * **Wall Sliding:** X and Y movement axes are checked independently against solid maze tiles and the opponent's tank. If a tank drives diagonally into a wall or another tank, it smoothly slides along the free axis rather than getting stuck.
   * **Tank-vs-Tank Blocking:** Tanks cannot drive through or overlap one another.
3. **Fire Primary Weapon (`SHOOT` — 0.5-Second Hardware Cooldown):**
   * Spawns a fast `6×6` yellow circular bullet from the tip of the tank's gun barrel (`center + 14 px` along barrel angle).
   * Each player can have up to **4 active bullets** in flight simultaneously (Bullets `0..3` for Player 1, Bullets `4..7` for Player 2).
   * Triggers a hardware 500 ms countdown timer; additional shoot presses are ignored until the hardware timer expires.
4. **Fire Special Heavy Attack (`SPECIAL` — 20.0-Second Hardware Cooldown):**
   * Launches a massive `10×10` fiery red-orange projectile that deals **6 hearts of damage** (3× normal damage).
   * Governed by a dedicated 20,000 ms (20 s) hardware cooldown timer per player.
5. **Ricochet / Bank Shots off Walls:**
   * Bullets reflect off horizontal and vertical wall faces ($v_x' = -v_x$ on vertical faces, $v_y' = -v_y$ on horizontal faces) up to **5 bounces** (`MAX_BOUNCES = 5`) before despawning, enabling tactical trick shots around pillars.
6. **Demolish Destructible Cover:**
   * Shooting the central brick barricade shatters individual brick tiles in real time, opening new lines of fire across the arena.
7. **Intercept Incoming Fire (Bullet-on-Bullet Annihilation):**
   * Players can shoot down an opponent's incoming normal or special projectile mid-air; when two active bullets overlap, the hardware collision matrix flags both and they mutually annihilate.

---

### C. Game Rules & How to Win

* **Starting Health:** Both Player 1 and Player 2 start with **20 Hearts (20 HP)**.
* **Damage System:**
  * **Normal Bullet Hit:** Reduces the struck tank's health by **2 Hearts**.
  * **Special (Big) Bullet Hit:** Reduces the struck tank's health by **6 Hearts**.
* **Self-Damage & Muzzle Immunity Rule:**
  * When a bullet is first fired (`bounces == 0`), it **cannot damage the shooter** so that spawning at the gun barrel tip never causes self-inflicted damage.
  * Once a bullet has bounced off at least one wall (`bounces > 0`), **friendly fire becomes active**—a careless bank shot can ricochet back and damage the player who fired it!
* **How to Win:**
  * The objective is to deplete the opponent's health bar from **20 Hearts down to 0 Hearts**.
  * When a tank's HP reaches `0`, that tank is **destroyed and immobilized** (its movement, rotation, and weapon controls are locked out), and the hardware sound engine plays a heavy decaying LFSR explosion sound (`SFX_DESTROY`).
  * The surviving player with remaining hearts wins the match!
  * Pressing the **Red Reset Button (`CPU_RESETN`)** on the Nexys A7 board (or restarting the simulation) resets tank positions, restores both health bars to 20 hearts, and reconstructs all shattered brick walls in the maze.

### D. Board Controls & Status LEDs (Digilent Nexys A7)

| Control / Indicator | Player 1 Pin | Player 2 Pin | Function |
| :--- | :--- | :--- | :--- |
| **Move Forward (`FWD`)** | `BTNU` (`M18`) | `SW1` (`L16`) | Drive forward along current tank angle |
| **Move Backward (`BWD`)** | `BTND` (`P18`) | `SW2` (`M13`) | Reverse along current tank angle |
| **Rotate Left (`LEFT`)** | `BTNL` (`P17`) | `SW3` (`R15`) | Rotate turret/tank $22.5^\circ$ counter-clockwise |
| **Rotate Right (`RIGHT`)** | `BTNR` (`M17`) | `SW4` (`R17`) | Rotate turret/tank $22.5^\circ$ clockwise |
| **Primary Fire (`SHOOT`)** | `BTNC` (`N17`) | `SW5` (`T18`) | Fire normal bullet (2 DMG, 0.5 s cooldown) |
| **Special Attack (`SPEC`)** | `SW0` (`J15`) | `SW6` (`U18`) | Fire heavy bullet (6 DMG, 20.0 s cooldown) |
| **System Reset** | `CPU_RESETN` (`C12`) | `CPU_RESETN` (`C12`) | Active-low hardware & game reset |

* **Diagnostic LEDs (`LD0..LD15`):**
  * `LD[0]`: Live Bullet-Wall collision sticky indicator
  * `LD[1]`: Live Bullet-Bullet collision sticky indicator
  * `LD[2]`: Live Bullet-Tank collision sticky indicator
  * `LD[3]`: CPU Illegal Instruction / Alignment Exception flag (`0` during normal operation)
  * `LD[15:4]`: Live CPU Program Counter word telemetry (`pc_out[13:2]`)

---

## 3. Running the Project on Any Laptop (Requirements, Setup & File Changes)

Follow this section step-by-step to clone, configure, compile, test, and simulate the entire project on any Windows, Linux, or macOS laptop.

---

### A. Software & Hardware Requirements

Depending on what you want to run, you need the following tools:

| Tool | Required For | Minimum / Recommended Version |
| :--- | :--- | :--- |
| **Python 3** | Running build scripts & automated test runners | Python 3.8+ |
| **xPack RISC-V Bare-Metal GCC** (`riscv-none-elf-gcc`) | Recompiling the embedded C game firmware (`software/`) or RV32IM C tests | GCC 12.x / 13.x / 14.x (`riscv-none-elf-*`) |
| **AMD / Xilinx Vivado Design Suite** (`xvlog`, `xelab`, `xsim`) | Simulating Verilog/SystemVerilog testbenches & generating the FPGA bitstream | Vivado ML Standard (WebPACK) 2020.2 – 2025.2 |
| **Host C Compiler (`gcc` or `clang`)** | Running the 129-assertion host C physics/game unit test suite (`test_game.c`) | Any standard C99/C11 compiler |

> **Note:** Pre-compiled firmware images (`imem.hex`, `dmem.hex`, `modules/cpu/firmware_imem.vh`, and `modules/cpu/firmware_dmem.vh`) are already committed in the repository. Therefore, **even if you do not install `riscv-none-elf-gcc`**, you can immediately run the Vivado hardware simulations and FPGA synthesis out of the box!

---

### B. How to Install the Requirements

#### 1. Installing Python 3
* **Windows:** Download from [python.org](https://www.python.org/downloads/) (check **"Add python.exe to PATH"** during installation) or run:
  ```powershell
  winget install Python.Python.3.12
  ```
* **Ubuntu / Debian Linux:**
  ```bash
  sudo apt update && sudo apt install -y python3 build-essential
  ```
* **macOS:**
  ```bash
  brew install python
  ```

#### 2. Installing the RISC-V Bare-Metal GCC Toolchain (`riscv-none-elf-gcc`)
* **Windows:**
  1. Download the latest `xpack-riscv-none-elf-gcc-<version>-win32-x64.zip` archive from the [xPack RISC-V GCC Releases page](https://github.com/xpack-dev-tools/riscv-none-elf-gcc-xpack/releases).
  2. Extract it to a folder such as `C:\xpack-riscv-none-elf-gcc`.
  3. Add `C:\xpack-riscv-none-elf-gcc\bin` to your user or system `PATH` environment variable.
  4. Verify in a new terminal:
     ```powershell
     riscv-none-elf-gcc --version
     ```
* **Ubuntu / Debian Linux:**
  Download the xPack Linux tarball or install the bare-metal toolchain and create `riscv-none-elf-*` symlinks if your distro provides `riscv64-unknown-elf-gcc`:
  ```bash
  sudo apt update && sudo apt install -y gcc-riscv64-unknown-elf binutils-riscv64-unknown-elf
  # Optional symlink if your package is named riscv64-unknown-elf-*:
  sudo ln -s /usr/bin/riscv64-unknown-elf-gcc /usr/local/bin/riscv-none-elf-gcc
  sudo ln -s /usr/bin/riscv64-unknown-elf-objdump /usr/local/bin/riscv-none-elf-objdump
  sudo ln -s /usr/bin/riscv64-unknown-elf-objcopy /usr/local/bin/riscv-none-elf-objcopy
  ```
* **macOS:**
  ```bash
  brew install --cask xpack-dev-tools/xpack/xpack-riscv-none-elf-gcc
  ```

#### 3. Installing AMD / Xilinx Vivado (Simulator & FPGA Synthesis)
1. Go to the [AMD Unified Installer Download Page](https://www.xilinx.com/support/download.html).
2. Download the **AMD Unified Installer for FPGAs & Adaptive SoCs** (Windows or Linux).
3. Choose **Vivado** $\rightarrow$ **Vivado ML Standard (Free / WebPACK)**.
4. Under **Devices**, ensure **7 Series $\rightarrow$ Artix-7** is checked (this is the family for the Nexys A7 `xc7a100tcsg324-1`).

---

### C. What Changes Must Be Made in Project Files for Your Laptop

By default, the repository's simulation scripts point to a Windows Vivado installation at **`D:\2025.2\Vivado\bin`**. Before running the automated test or simulation scripts on your own laptop, update the Vivado path in the following **4 files** to match where Vivado is installed on your machine (for example, `C:\Xilinx\Vivado\2024.1\bin` on Windows, or `/tools/Xilinx/Vivado/2024.1/bin` on Linux):

1. **`run_sim.bat` (Lines 14, 20, 27):**
   * Replace `D:\2025.2\Vivado\bin\xvlog.bat`, `xelab.bat`, and `xsim.bat` with your local Vivado `bin` path (or just `xvlog.bat`, `xelab.bat`, `xsim.bat` if Vivado's `bin` folder is added to your system `PATH`).
2. **`testing/run_all_game_engine_tests.py` (Line 6):**
   * Change:
     ```python
     VIVADO_BIN = r"D:\2025.2\Vivado\bin"
     ```
     to your local Vivado `bin` directory path (e.g., `r"C:\Xilinx\Vivado\2024.1\bin"`).
   * *(Linux note: on Linux, also change `"xvlog.bat"`, `"xelab.bat"`, `"xsim.bat"` on lines 31–33 to `"xvlog"`, `"xelab"`, `"xsim"`).*
3. **`testing/run_all_vga_tests.py` (Line 6):**
   * Change:
     ```python
     VIVADO_BIN = r"D:\2025.2\Vivado\bin"
     ```
     to your local Vivado `bin` directory path.
   * *(Linux note: on Linux, also change `"xvlog.bat"`, `"xelab.bat"`, `"xsim.bat"` on lines 28–30 to `"xvlog"`, `"xelab"`, `"xsim"`).*
4. **`testing/RV32IM/run_tests.py` (Line 35):**
   * Change the default argument:
     ```python
     def run_test(test_name, vivado_bin=r"D:\2025.2\Vivado\bin"):
     ```
     to your local Vivado `bin` path.

> **Alternative if you have a different RISC-V GCC prefix:** If your RISC-V toolchain binary is named `riscv64-unknown-elf-gcc` instead of `riscv-none-elf-gcc`, update the `gcc`, `objdump`, and `objcopy` variables in:
> * `software/build_and_export.py` (Lines 10–12)
> * `testing/RV32IM/run_tests.py` (Lines 43–45)
> * `testing/RV32IM/Makefile` (Lines 1–3)

---

### D. Step-by-Step Execution Guide

#### Step 1: Clone the Repository
```bash
git clone https://github.com/kaustavbhowal21/battle-tanks.git
cd battle-tanks
```

#### Step 2: Run the 129 Host C Physics & Game Logic Unit Tests (No Vivado Needed)
You can immediately verify the entire C game engine, Q24.8 trigonometry, wall reflection physics, brick destruction, and MMIO register packing on any laptop using standard `gcc`:
```bash
gcc -Isoftware/include software/tests/test_game.c software/src/game.c software/src/physics.c -DHOST_TEST -o test_game
./test_game
```
Expected result: `TEST EXECUTION SUMMARY: 129 RUN | 129 PASSED | 0 FAILED`.

#### Step 3: Compile the Embedded C Firmware into RISC-V Machine Code
Whenever you modify `software/src/game.c`, `physics.c`, or `main.c`, recompile and export the memory images:
```bash
python software/build_and_export.py
```
This generates:
* `software/game.elf` & `software/game.dis` (RISC-V executable and annotated disassembly)
* `imem.hex` & `dmem.hex` (copied automatically to root, `modules/`, `modules/cpu/`, and `modules/sim/`)
* `modules/cpu/firmware_imem.vh` & `modules/cpu/firmware_dmem.vh` (embedded Verilog headers for trouble-free Vivado synthesis)

#### Step 4: Run the Automated Hardware Verification Suites
* **Game Engine & Peripherals Test Suite (7 Testbenches):**
  ```bash
  python testing/run_all_game_engine_tests.py
  # Or on Windows: run_game_engine_tests.bat
  ```
  Verifies `tb_input_controller`, `tb_cooldown_timers`, `tb_maze_tile_ram`, `tb_sprite_hud_regfile`, `tb_collision_engine`, `tb_mmio_interconnect`, and `tb_game_engine_subsystem`.

* **VGA Display Subsystem Test Suite (5 Testbenches):**
  ```bash
  python testing/run_all_vga_tests.py
  # Or on Windows: run_vga_tests.bat
  ```
  Verifies `tb_maze_tile_renderer`, `tb_sprite_engine`, `tb_health_hud`, `tb_pixel_priority_mixer`, and `tb_vga_subsystem`.

* **RV32IM Processor ISA Verification Suite (4 C Test Programs on RTL CPU):**
  ```bash
  python testing/RV32IM/run_tests.py all
  ```
  Compiles and simulates `test_mul.c`, `test_div.c`, `test_auipc.c`, and `test_rv32im_all.c` on the 3-stage pipeline.

#### Step 5: Run Full Hardware-Software Co-Simulation (`tb_game_top`)
* **Windows 1-Click Script:**
  ```cmd
  run_sim.bat
  ```
* **Manual Cross-Platform Commands (Windows / Linux):**
  ```bash
  xvlog --sv -i modules/cpu \
    modules/cpu/pipeline.v modules/cpu/memory.v modules/cpu/multiplier_dsp.v \
    modules/cpu/divider_radix2.v modules/cpu/top_rv32m.v \
    modules/game_engine/collision_engine.v modules/game_engine/cooldown_timers.v \
    modules/game_engine/sprite_hud_regfile.v modules/game_engine/input_controller.v \
    modules/game_engine/maze_tile_ram.v modules/game_engine/mmio_interconnect.v \
    modules/vga/vga_timing_gen.v modules/vga/maze_tile_renderer.v \
    modules/vga/sprite_engine.v modules/vga/health_hud.v \
    modules/vga/pixel_priority_mixer.v modules/top_fpga.v modules/sim/tb_game_top.v

  xelab -debug typical -top tb_game_top -s tb_game_top_sim
  xsim tb_game_top_sim -R
  ```

#### Step 6: Synthesize & Program the Digilent Nexys A7-100T FPGA Board
1. Launch **Vivado** and create a new RTL project targeting **`xc7a100tcsg324-1`**.
2. Add all design sources from `modules/cpu/`, `modules/game_engine/`, `modules/vga/`, `modules/audio/`, and `modules/top_fpga.v`.
3. Add `modules/constraints.xdc` as the physical constraints file.
4. Ensure `imem.hex` and `dmem.hex` are added to the project (or set `IMEM_HEX = ""` and `DMEM_HEX = ""` on `top_fpga` to use the compiled-in `firmware_imem.vh` and `firmware_dmem.vh` headers).
5. Click **Generate Bitstream**, open **Hardware Manager**, connect the Nexys A7 via USB, and program the device with a VGA monitor attached to `J2`.

---

## 4. Detailed Hardware Accelerations Implemented

To achieve deterministic **60 FPS gameplay (~2,200 CPU cycles per frame)** while generating a continuous **25 MHz VGA pixel stream**, our design offloads eight major computational and I/O workloads into dedicated hardware modules.

---

### 1. RV32M Hardware Multiplier & Iterative Radix-2 Divider (`modules/cpu/`)

Standard `RV32I` processors require tens to hundreds of instructions to emulate 32-bit multiplication and division in software—operations that our C physics engine executes constantly for fixed-point velocity vectors ($\Delta x = (\cos\theta \cdot v) / 256$) and pixel-to-tile coordinate conversion ($\text{col} = x / 24, \text{row} = y / 24$).

* **Single-Cycle DSP48E1 Multiplier (`multiplier_dsp.v`):**
  * Supports all four RISC-V multiply instructions: `MUL` (lower 32 bits), `MULH` (signed $\times$ signed upper 32 bits), `MULHSU` (signed $\times$ unsigned upper 32 bits), and `MULHU` (unsigned $\times$ unsigned upper 32 bits).
  * Sign-extends or zero-extends operands to **33 bits** (`op_a_ext`, `op_b_ext`) and computes a unified **66-bit signed product** mapped directly onto Artix-7 `DSP48E1` slices.
  * Asserts `ready = start` combinationally, completing in **1 clock cycle (20 ns at 50 MHz)** with zero pipeline stall cycles.
* **32-Cycle Non-Restoring Radix-2 Divider (`divider_radix2.v`):**
  * Supports `DIV`, `DIVU`, `REM`, and `REMU` using a compact 3-state FSM (`IDLE`, `COMPUTE`, `DONE`) with a 64-bit shift-and-subtract working register (`working_dividend`), saving hundreds of Slice LUTs compared to a combinational array divider.
  * **Hardware Corner-Case Shortcuts:** Detects **division by zero** (`operand_b == 0` $\rightarrow$ quotient `0xFFFF_FFFF`, remainder `operand_a`) and **signed overflow** (`0x8000_0000 / -1` $\rightarrow$ quotient `0x8000_0000`, remainder `0`) in the `IDLE` state and jumps straight to `DONE` in **1 cycle**.
* **Pipeline Stall & Writeback Bubble Injection (`top_rv32m.v`, `execute.v`):**
  * During a multi-cycle division, `m_pipeline_stall` freezes the Program Counter (`fetch_pc`), captures any in-flight instruction fetch into a **skid buffer** in `IF_ID.v`, holds `id_ex_reg`, and gates `alu_to_reg` and `mem_write` low in `execute.v` so clean NOP bubbles enter `WB` until `div_ready` asserts.

---

### 2. Parallel Hardware Collision Engine (`modules/game_engine/collision_engine.v`)

Checking all pairwise projectile, tank, and wall intersections in software requires nested loops over every active object and tile. Our hardware collision engine performs these checks continuously in the background:

* **28 Parallel Bullet-Bullet AABB Comparators:**
  * Evaluates all $\binom{8}{2} = 28$ unique pairs among the 8 bullets simultaneously on every clock edge.
  * Dynamically selects each bullet's bounding box size (`6×6` for normal bullets, `12×12` for special big bullets via `bullet_big[i]`) and checks axis-aligned overlap:
    $$(a_x < b_x + b_w) \land (b_x < a_x + a_w) \land (a_y < b_y + b_h) \land (b_y < a_y + a_h)$$
* **16 Parallel Bullet-Tank AABB Comparators:**
  * Evaluates all $8 \times 2 = 16$ interactions between the 8 bullets and the two `20×20` pixel tanks in parallel every clock cycle, generating both per-bullet hit masks (`btk_hit[7:0]`) and per-tank hit flags (`tank_hit[1:0]`).
* **8-Clock Time-Shared Bullet-Wall Scanner:**
  * A 3-bit round-robin counter (`scan_q = 0..7`) inspects one bullet every 20 ns clock cycle.
  * It computes the bullet center $(cx, cy)$, converts pixel coordinates into tile grid coordinates $(\text{row} = cy / 24, \text{col} = cx / 24)$, and queries Port B of **Maze RAM Copy C** (`maze_c_addr = row * 20 + col`).
  * A 2-stage pipeline (`scan_d1/d2`, `act_d1/d2`) aligns with synchronous RAM read latency and flags a hit whenever the tile code is non-zero (`is_wall`). All 8 bullets are scanned every **8 clock cycles (160 ns)**—over **100,000 times per 60 Hz video frame**.
* **Write-1-to-Clear (W1C) Sticky Registers (`0x8000_0020`–`0x8000_002C`):**
  * Because a collision might last only a single clock edge while the CPU is executing other code, hardware latches hits into sticky flip-flops (`sticky_wall_q`, `sticky_bb_q`, `sticky_btk_q`, `sticky_tank_q`).
  * The C program polls these registers once per frame and clears handled bits atomically by writing a `1` bitmask back to the register.

---

### 3. Mirrored Dual-Port Maze Tile RAM (`modules/game_engine/maze_tile_ram.v`)

The `20×20` arena tile map (`400 × 2-bit` entries) must be accessed simultaneously by **three masters**:
1. The **VGA Maze Tile Renderer** reading tiles at 25 MHz pixel rate.
2. The **Hardware Collision Scanner** reading tiles at 50 MHz every clock cycle.
3. The **RV32IM CPU** reading/writing tiles when checking tank collisions or shattering destructible bricks.

Instead of a complex multi-port bus arbiter that would introduce display snow or CPU pipeline stalls, `maze_tile_ram.v` instantiates **two identical mirrored dual-port memories**:
* **Copy V (`ram_copy_v`):** Port A is wired to the CPU (read/write); Port B is dedicated exclusively to the VGA Maze Tile Renderer (`vga_tile_addr` $\rightarrow$ `vga_tile_data`).
* **Copy C (`ram_copy_c`):** Port A is wired in parallel to the CPU write bus; Port B is dedicated exclusively to the Collision Engine (`col_tile_addr` $\rightarrow$ `col_tile_data`).
* Whenever the CPU shatters a brick (`MAZE_TILE(r, c) = TILE_EMPTY`), both Copy V and Copy C update on the exact same rising clock edge with **zero bus contention**.

---

### 4. Real-Time "Racing-the-Beam" VGA Display Pipeline (`modules/vga/`)

A full 640×480×12-bit frame buffer would require **3,686,400 bits (~102 Block RAMs)** and massive memory bandwidth to clear and redraw every 16.7 ms. Instead, our VGA subsystem uses **zero frame-buffer memory**, computing each pixel's 12-bit RGB color on the fly in lockstep with the CRT/LCD electron beam:

1. **VGA Timing Generator (`vga_timing_gen.v`):**
   * Runs on the 50 MHz system clock gated by a 25 MHz pixel clock enable (`pix_ce`), generating standard 640×480 @ 60 Hz raster timing (`800×525` total pixels, active-low `hsync_n` and `vsync_n`).
   * Computes registered `x`, `y`, `active`, `hsync_n`, and `vsync_n` outputs from next-state counters (`hcnt_nxt`, `vcnt_nxt`) so beam coordinates and sync pulses have zero pixel skew.
2. **Procedural Maze Tile Renderer (`maze_tile_renderer.v`):**
   * Maps beam coordinates $(x, y)$ in the `480×480` arena to tile indices $(\text{tile\_x} = x / 24, \text{tile\_y} = y / 24)$ and intra-tile sub-pixel offsets $(\text{sub\_x} = x \bmod 24, \text{sub\_y} = y \bmod 24)$.
   * Procedurally shades 3D beveled highlights (`12'hCCD`) and shadows (`12'h445`) on steel walls (`2'b10`), staggered mortar grooves (`12'h444`) on orange-red destructible bricks (`2'b01`), and subtle tactical grid lines (`12'h112`) on the arena floor (`2'b00`).
3. **16-Angle Vector Sprite Engine (`sprite_engine.v`):**
   * **Tank Renderer:** Uses unsigned subtraction wrap-around (`dx = x - tank_x < 20`) to test bounding boxes in a single comparator, drawing tank treads, hull, and turret dome.
   * **16-Angle Gun Barrel Projection (`barrel_hit`):** Converts pixel offsets to half-pixel coordinates relative to the tank center $(u_x = 2\cdot dx - 19, u_y = 2\cdot dy - 19)$ and computes dot and cross products (`along` and `across`) against hardware-stored 16-angle sine/cosine vectors. This renders a crisp 2–3 pixel wide rotated gun barrel at all 16 angles without storing 16 separate bitmap ROMs.
   * **Circular Bullet Discs:** Evaluates $\Delta x^2 + \Delta y^2 \le r^2$ in parallel across all 8 bullet slots (`<= 6` for `6×6` normal bullets, `<= 18` for `10×10` special bullets).
4. **Bit-Sliced Health HUD (`health_hud.v`):**
   * In the right-hand HUD strip ($x \in [480, 639]$), extracts the heart index (`heart_slot = dx[7:3]`) and intra-heart pixel (`px_in_heart = dx[2:0]`) via pure wire bit-slicing (zero logic gates), indexing an `8×8` heart bitmap ROM and comparing `heart_slot < hp` to color full vs. depleted hearts.
5. **Pipelined Pixel Priority Mixer (`pixel_priority_mixer.v`):**
   * Composites all layers in strict hardware priority order:
     $$\text{HUD} > \text{Big Bullet} > \text{Normal Bullet} > \text{Tank P1} > \text{Tank P2} > \text{Maze Wall} > \text{Arena Floor}$$
   * Includes a **2-stage flip-flop delay line** (`hsync_pipe`, `vsync_pipe`, `active_pipe`) that matches the 1-cycle renderer register latency + 1-cycle mixer DAC output register latency, ensuring blanking intervals drive RGB strictly to `0`.

---

### 5. Hardware Cooldown Timers (`modules/game_engine/cooldown_timers.v`)

* A shared 17-bit **1 ms prescaler** (`ms_cnt` counting `50,000` clocks at 50 MHz) generates a precise 1 kHz `tick` strobe.
* Four independent 15-bit hardware down-counters (`cd_p1_shoot`, `cd_p1_spec`, `cd_p2_shoot`, `cd_p2_spec`) count down to zero in hardware:
  * **Primary Shoot Channels (P1 & P2):** Reload with `500` ticks (**0.500 seconds**).
  * **Special Attack Channels (P1 & P2):** Reload with `20,000` ticks (**20.000 seconds**).
* The CPU checks weapon readiness in a single MMIO read (`REG_TIMER_STATUS` @ `0x8000_0010`) and starts a cooldown with a single write (`REG_TIMER_TRIGGER` @ `0x8000_0014`).

---

### 6. Low-Latency Input Synchronizer, Debouncer & Hold Latch (`modules/game_engine/input_controller.v`)

* Instantiates **12 parallel input conditioning channels** (6 for Player 1, 6 for Player 2).
* **2-FF Metastability Synchronizer (`sync1`, `sync2`):** Safely crosses asynchronous mechanical button presses into the 50 MHz `clk_sys` domain.
* **3 ms Fast Debouncer (`DEBOUNCE_MAX = 150,000`):** Filters contact bounce while keeping turn/shoot input latency imperceptibly low.
* **20 ms Minimum-Hold Latch (`MIN_HOLD = 1,000,000`):** Because the C game loop runs at 60 FPS (sampling inputs once every ~16.7 ms), a very brief button tap could otherwise release between two software polls. The hardware `hold_q` counter guarantees every valid press remains asserted for at least 20 ms so the CPU never misses a quick tap.

---

### 7. Split-Address MMIO Interconnect (`modules/game_engine/mmio_interconnect.v`)

* Maps standard Data BRAM when `addr[31] == 0` (`0x0000_0000`–`0x0000_0FFF`) and hardware peripherals when `addr[31] == 1` (`0x8000_0000`–`0x8000_073F`).
* **Concurrent Load/Store Hazard Prevention:** In our 3-stage pipeline, a store instruction in `WB` and a load instruction in `EX` can access the bus on the exact same clock edge. `mmio_interconnect.v` decodes write enables from `d_addr` (WB store address) and read chip-selects from an independent `d_raddr` (EX load address), registering the read chip-selects by 1 cycle (`cs_*_q`) to match synchronous BRAM read latency.

| MMIO Address | Register Name | Access | Hardware Function |
| :--- | :--- | :---: | :--- |
| `0x8000_0000` | `REG_P1_KEYS` | RO | P1 debounced keys: `[0]` FWD, `[1]` BWD, `[2]` L, `[3]` R, `[4]` SHOOT, `[5]` SPEC |
| `0x8000_0004` | `REG_P2_KEYS` | RO | P2 debounced keys: `[0]` FWD, `[1]` BWD, `[2]` L, `[3]` R, `[4]` SHOOT, `[5]` SPEC |
| `0x8000_0010` | `REG_TIMER_STATUS` | RO | Ready flags (`1`=Ready): `[0]` P1 Shoot, `[1]` P1 Spec, `[2]` P2 Shoot, `[3]` P2 Spec |
| `0x8000_0014` | `REG_TIMER_TRIGGER` | WO | Write `1` to corresponding bit `[3:0]` to start 0.5s or 20s countdown |
| `0x8000_0020` | `REG_COLLISION_FLAG` | RO | Summary flags: `[0]` any wall hit, `[1]` any bullet-bullet hit, `[2]` any tank hit |
| `0x8000_0024` | `REG_COLLISION_WALL` | R/W1C | Sticky bullet-wall hit mask `[7:0]` (write `1` to clear bit) |
| `0x8000_0028` | `REG_COLLISION_BULLET` | R/W1C | Sticky bullet-bullet overlap mask `[7:0]` (write `1` to clear bit) |
| `0x8000_002C` | `REG_COLLISION_TANK` | R/W1C | Sticky tank hit mask: `[7:0]` bullet `i` hit tank, `[8]` P1 hit, `[9]` P2 hit |
| `0x8000_0040` | `REG_SPRITE_P1_TANK` | WO | Player 1 position: `{6'b0, y[9:0], 6'b0, x[9:0]}` |
| `0x8000_0044` | `REG_SPRITE_P2_TANK` | WO | Player 2 position: `{6'b0, y[9:0], 6'b0, x[9:0]}` |
| `0x8000_0048 + 4*i` | `REG_SPRITE_BULLET(i)` | WO | Bullet `i` (`0..7`): `{10'b0, is_big, active, y[9:0], x[9:0]}` |
| `0x8000_0080` | `REG_HUD_HEALTH` | WO | Packed health: `{16'b0, hp2[7:0], hp1[7:0]}` (`0..20` hearts each) |
| `0x8000_0084` | `REG_TANK_ANGLES` | WO | Packed angles: `{24'b0, ang2[3:0], ang1[3:0]}` (`0..15` each) |
| `0x8000_0100`–`0x073C` | `MAZE_TILE(r, c)` | R/W | 400-word (`20×20`) Mirrored Maze Tile RAM (`0`=Floor, `1`=Brick, `2`=Steel) |

---

### 8. Autonomous Hardware Event-Sniffing PWM Audio Engine (`modules/audio/sound_engine.v`)

* **Zero-CPU-Overhead Event Sniffer:** Passively monitors live hardware signals (`bullet_act`, `hp1`, `hp2`, `wall_hit_any`, `tank_hit_any`) to detect game events on the fly without requiring CPU driver writes:
  1. **Bullet Fire (`SFX_FIRE`):** Triggered on any rising edge of `bullet_act[7:0]`; generates a downward-sweeping square wave ("pew-pew").
  2. **Bullet Bounce (`SFX_BOUNCE`):** Triggered on `wall_hit_any`; generates a high-frequency metallic ricochet chirp.
  3. **Tank Hit / Damage (`SFX_HIT`):** Triggered when `hp1` or `hp2` decreases (above 0); generates a two-tone alert sound.
  4. **Tank Destroyed (`SFX_DESTROY`, Highest Priority):** Triggered when `hp1` or `hp2` drops to `0`; synthesizes a heavy decaying explosion rumble using a **16-bit Galois LFSR** ($x^{16} + x^{14} + x^{13} + x^{11} + 1$) mixed with a low-frequency tone.
* **195.3 kHz PWM DAC:** Mixes the signed tone and LFSR noise channels around mid-rail (`128`), clamps to 8-bit unsigned samples (`0..255`), and drives a 1-bit high-frequency PWM carrier (`50 MHz / 256 = 195.3 kHz`) to the Nexys A7 mono audio jack (`Pin A11`).
