# Hardware-Accelerated 2D Battle Tanks with Real-Time Reflection Physics on an RV32IM FPGA Soft-Core

**Course:** CSE Semester 3 — Hardware Laboratory Project  
**Group Number:** 3  
**Team Members:** Kaustav Bhowal, Kabir Gupta, Jayesh Vijaivargia, Mahendra, Jayesh Banzal  
**Target Platform:** Digilent Nexys A7-100T (Xilinx Artix-7 XC7A100T-1CSG324C FPGA)  
**Display Output:** 640×480 @ 60 Hz VGA (12-bit RGB color, 4,096 colors)  
**Processor Core:** Custom 3-Stage Pipelined RV32IM RISC-V Soft-Core (Instruction Fetch/Decode → Execute → Writeback) @ 50 MHz  

---

## Table of Contents

1. [Project Overview](#1-project-overview)
2. [The Game: Display Layout, Rules, Actions & How to Win](#2-the-game-display-layout-rules-actions--how-to-win)
3. [Running the Project on Any Laptop (Requirements, Setup & File Changes)](#3-running-the-project-on-any-laptop-requirements-setup--file-changes)
4. [Detailed Hardware Accelerations Implemented](#4-detailed-hardware-accelerations-implemented)

---

## 1. Project Overview

**Battle Tanks** is a real-time, two-player 2D tank combat game built as a hardware-software co-design on an FPGA. At the center of the system is a custom **32-bit RISC-V (RV32IM) soft-core processor** running at **50 MHz**, which executes an embedded C game program responsible for high-level game rules, fixed-point trigonometry, 2D projectile reflection physics, and arena state updates.

On a basic soft-core processor without hardware acceleration, drawing every pixel of a 640×480 screen in software, checking collisions across dozens of moving objects, and emulating multiplication and division in software would overwhelm the CPU and make real-time gameplay impossible. To achieve a smooth **60 FPS game loop** alongside a **640×480 @ 60 Hz VGA display**, our system combines software game logic with dedicated **hardware accelerators**:

* **Custom 3-Stage RV32IM Soft-Core Processor:** Executes the compiled C game firmware and accelerates arithmetic using a single-cycle hardware multiplier and a 32-cycle hardware divider integrated directly into the Execute stage.
* **Real-Time Hardware VGA Display Engine:** Renders the 20×20 maze arena, two 16-angle rotating tank sprites, up to 8 circular projectiles, and a 2×20-heart health bar display on the fly at 25 MHz without requiring a software frame buffer.
* **Parallel Hardware Collision Engine:** Checks all 28 bullet-to-bullet pairs and 16 bullet-to-tank pairs in parallel on every clock cycle, while scanning bullet-to-wall hits across all 8 bullets every 8 clock cycles.
* **Mirrored Dual-Port Maze Memory:** Maintains two synchronized copies of the 20×20 arena map in hardware so the VGA display engine, the collision engine, and the CPU can all access the maze simultaneously without stalling one another.
* **Hardware Cooldown Timers:** Tracks 0.5-second normal fire and 20-second special attack reload times in dedicated parallel hardware counters so the CPU never has to run software timing loops.

### Project Directory Organization

* **`modules/cpu/`** — 3-stage RV32IM processor pipeline, instruction/data Block RAMs, single-cycle DSP multiplier, and 32-cycle radix-2 divider.
* **`modules/game_engine/`** — Memory-mapped interconnect, parallel collision engine, mirrored dual-port maze RAM, hardware cooldown timers, sprite/HUD register file, and button debouncers.
* **`modules/vga/`** — 640×480 @ 60 Hz VGA timing generator, maze tile renderer, 16-angle tank and bullet sprite engine, heart health HUD, and pixel priority mixer.
* **`modules/audio/`** — Event-driven PWM sound effects generator for firing, ricochets, hits, and tank explosions.
* **`modules/sim/`** — 16 self-checking Verilog testbenches covering individual modules, subsystems, and full hardware-software co-simulation.
* **`software/`** — Bare-metal C game source code, fixed-point physics engine, memory-mapped register definitions, automated firmware build script, and 129 host unit tests.
* **`testing/`** — Automated Python test runners for the RV32IM CPU, Game Engine subsystem, and VGA display subsystem.
* **`diagrams/`** — System architecture block diagrams, pipeline/peripheral timing diagrams, and presentation slides.

---

## 2. The Game: Display Layout, Rules, Actions & How to Win

### A. What is Displayed on the VGA Monitor (640×480 @ 60 Hz)

The monitor screen is split into two side-by-side areas separated by a vertical steel divider line:

1. **The Combat Arena (Left 480×480 Pixels — 20×20 Grid of 24×24 Pixel Tiles):**
   * **Indestructible Steel Walls (Gray Beveled Blocks):** Form the outer boundary of the arena as well as interior pillar obstacles spaced every 4 rows and 4 columns. Bullets bounce off steel walls without damaging them.
   * **Destructible Brick Walls (Orange-Red Brick Blocks):** Located in the center of the arena as breakable cover. When hit by any bullet, a brick wall shatters into open floor while still reflecting the bullet.
   * **Arena Floor (Dark Green Tactical Grid):** Open ground where tanks can drive and maneuver freely.
   * **Player 1 Tank (Green Tank, Top-Left Spawn):** A 20×20 pixel armored tank with treads, a central turret dome, and a gun barrel that rotates smoothly across **16 directions** (in 22.5° steps). Starts in the top-left corner at coordinates (48, 48) facing East.
   * **Player 2 Tank (Red Tank, Bottom-Right Spawn):** A 20×20 pixel red armored tank with its own 16-direction rotating turret barrel. Starts in the bottom-right corner at coordinates (410, 410) facing West.
   * **Normal Bullets (6×6 Yellow Circles):** Fast standard projectiles fired by the primary weapon.
   * **Special "Big" Bullets (10×10 Orange-Red Circles):** Larger, heavy cannon projectiles fired by the special weapon.

2. **The Health HUD (Right 160×480 Pixels):**
   * **Player 1 Health Bar (Top-Right):** Shows a green Player 1 banner above **20 heart icons**. Full health points are displayed as bright red hearts, while lost health points appear as dark empty heart outlines.
   * **Player 2 Health Bar (Bottom-Right):** Shows a red Player 2 banner above Player 2's **20 heart icons**.

---

### B. What Players Can Do in the Game

Each player has **6 controls** and can perform the following actions during a match:

1. **Rotate in 16 Directions (Turn Left / Turn Right):**
   * Players can rotate their tank and gun barrel counter-clockwise or clockwise across 16 angles (22.5° per step, full 360° rotation) to aim precisely down corridors or set up angled bank shots.
2. **Drive Forward and Backward:**
   * Tanks drive forward or reverse along the exact direction they are facing.
   * **Smooth Wall Sliding:** Horizontal and vertical movement components are checked separately against walls and the other tank, allowing tanks to slide smoothly along walls when approaching at an angle instead of getting stuck.
   * **Tank-to-Tank Blocking:** Tanks are solid obstacles to one another and cannot drive through or overlap the opponent's tank.
3. **Fire Primary Bullets (0.5-Second Cooldown):**
   * Fires a fast 6×6 yellow circular bullet from the tip of the tank's gun barrel.
   * Each player can have up to **4 active bullets** flying in the arena at the same time (up to 8 bullets total on screen).
   * After firing, a 0.5-second hardware cooldown timer prevents the next primary shot until reloading completes.
4. **Fire Special Heavy Attack (20-Second Cooldown):**
   * Fires a large 10×10 fiery orange-red projectile that deals triple damage (**6 hearts** instead of 2).
   * Governed by a 20-second hardware cooldown timer per player.
5. **Perform Ricochet Bank Shots off Walls:**
   * Bullets bounce realistically off horizontal and vertical walls (reversing horizontal velocity on vertical walls and vertical velocity on horizontal walls).
   * Each bullet can bounce up to **5 times** before disappearing, allowing players to bounce shots around corners and pillars to hit a hidden opponent.
6. **Destroy Brick Cover:**
   * Players can shoot the destructible brick walls in the center of the map to break them down tile by tile and open up direct attack paths.
7. **Shoot Down Enemy Bullets Mid-Air:**
   * If two bullets collide in mid-air, both bullets cancel out and destroy each other. Players can defensively fire at incoming enemy special bullets to neutralize them before impact.

---

### C. Game Rules & How to Win

* **Starting Health:** Both players begin the match with **20 Hearts**.
* **Damage Rules:**
  * A **Normal Bullet** hit removes **2 Hearts** from the struck tank.
  * A **Special (Big) Bullet** hit removes **6 Hearts** from the struck tank.
* **Ricochet Self-Damage Rule:**
  * When a bullet leaves the barrel (before its first bounce), it cannot hurt the tank that fired it.
  * Once a bullet has **bounced off at least one wall**, it can damage **either tank**—including the player who fired it! Players must aim bank shots carefully to avoid hitting themselves.
* **How to Win:**
  * A player wins by reducing the opponent's health from **20 Hearts to 0 Hearts**.
  * When a tank reaches **0 Hearts**, it is destroyed and completely disabled (it can no longer move, rotate, or fire), and an explosion sound effect is triggered.
  * Pressing the **Red Reset Button (`CPU_RESETN`)** on the FPGA board restarts the match: both tanks return to their starting corners with 20 Hearts, all active bullets are cleared, and all destroyed brick walls are restored.

### D. FPGA Board Controls & LED Indicators (Digilent Nexys A7)

| Action | Player 1 Control (Pin) | Player 2 Control (Pin) | Description |
| :--- | :--- | :--- | :--- |
| **Move Forward** | `BTNU` (`M18`) | `SW1` (`L16`) | Drive forward in the direction the tank is facing |
| **Move Backward** | `BTND` (`P18`) | `SW2` (`M13`) | Reverse in the opposite direction |
| **Turn Left** | `BTNL` (`P17`) | `SW3` (`R15`) | Rotate tank and turret 22.5° counter-clockwise |
| **Turn Right** | `BTNR` (`M17`) | `SW4` (`R17`) | Rotate tank and turret 22.5° clockwise |
| **Primary Shoot** | `BTNC` (`N17`) | `SW5` (`T18`) | Fire normal bullet (2 hearts damage, 0.5 s cooldown) |
| **Special Attack** | `SW0` (`J15`) | `SW6` (`U18`) | Fire heavy bullet (6 hearts damage, 20.0 s cooldown) |
| **System Reset** | `CPU_RESETN` (`C12`) | `CPU_RESETN` (`C12`) | Reset game state, health bars, and brick walls |

* **Onboard Status LEDs (`LD0` to `LD15`):**
  * `LD0`: Lights up when a bullet-wall collision is detected.
  * `LD1`: Lights up when a bullet-bullet collision is detected.
  * `LD2`: Lights up when a bullet-tank collision is detected.
  * `LD3`: CPU exception indicator (remains off during normal operation).
  * `LD4`–`LD15`: Display the active CPU Program Counter word address in real time.

---

## 3. Running the Project on Any Laptop (Requirements, Setup & File Changes)

This section explains everything needed to set up, modify, compile, test, and simulate the project on any Windows, Linux, or macOS laptop.

---

### A. Requirements

| Requirement | Purpose | Version |
| :--- | :--- | :--- |
| **Python 3** | Running the build scripts and automated test suites | Python 3.8 or newer |
| **AMD / Xilinx Vivado Design Suite** | Running hardware simulations (`xvlog`, `xelab`, `xsim`) and generating the FPGA bitstream | Vivado ML Standard (free WebPACK edition), 2020.2 – 2025.2 |
| **RISC-V Bare-Metal GCC Toolchain** (`riscv-none-elf-gcc`) | Recompiling the C game code (`software/`) into RISC-V machine code | xPack RISC-V GCC 12.x / 13.x / 14.x |
| **Standard C Compiler (`gcc` or `clang`)** | Running the host-side C unit test suite (`software/tests/test_game.c`) | Any standard C compiler |

> **Important Note:** Pre-compiled RISC-V memory images (`imem.hex`, `dmem.hex`, `firmware_imem.vh`, and `firmware_dmem.vh`) are already included in the repository. If you only want to run the **Vivado hardware simulations** or **synthesize the bitstream for the FPGA**, you only need **Vivado** and **Python 3**—you do not even need to install the RISC-V GCC compiler unless you edit the C source files!

---

### B. How to Install the Requirements

#### 1. Install Python 3
* **Windows:** Download the installer from [python.org/downloads](https://www.python.org/downloads/) (make sure to check **"Add python.exe to PATH"**) or run in PowerShell:
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

#### 2. Install AMD / Xilinx Vivado
1. Visit the [AMD Vivado Download Page](https://www.xilinx.com/support/download.html) and download the **AMD Unified Installer** for Windows or Linux.
2. Run the installer and select **Vivado** → **Vivado ML Standard (Free WebPACK)**.
3. In the device selection screen, check **7 Series** → **Artix-7** (required for the Digilent Nexys A7-100T board).

#### 3. Install the RISC-V GCC Toolchain (`riscv-none-elf-gcc`)
* **Windows:**
  1. Download `xpack-riscv-none-elf-gcc-<version>-win32-x64.zip` from the [xPack RISC-V GCC Releases page](https://github.com/xpack-dev-tools/riscv-none-elf-gcc-xpack/releases).
  2. Extract the zip archive (for example, to `C:\xpack-riscv-none-elf-gcc`).
  3. Add the `bin` folder (`C:\xpack-riscv-none-elf-gcc\bin`) to your Windows **System PATH**.
  4. Open a new terminal and verify with `riscv-none-elf-gcc --version`.
* **Ubuntu / Debian Linux:**
  Download the xPack Linux archive or install the distribution's bare-metal RISC-V compiler and create command aliases:
  ```bash
  sudo apt update && sudo apt install -y gcc-riscv64-unknown-elf binutils-riscv64-unknown-elf
  sudo ln -s /usr/bin/riscv64-unknown-elf-gcc /usr/local/bin/riscv-none-elf-gcc
  sudo ln -s /usr/bin/riscv64-unknown-elf-objdump /usr/local/bin/riscv-none-elf-objdump
  sudo ln -s /usr/bin/riscv64-unknown-elf-objcopy /usr/local/bin/riscv-none-elf-objcopy
  ```
* **macOS:**
  ```bash
  brew install --cask xpack-dev-tools/xpack/xpack-riscv-none-elf-gcc
  ```

---

### C. What Changes Must Be Made in the Files to Run on Your Laptop

The batch and Python simulation scripts in this repository currently have the Vivado installation folder hardcoded to **`D:\2025.2\Vivado\bin`**. To run the automated testbenches or simulation scripts on a different laptop, update that path in the following **4 files** to match where Vivado is installed on your laptop (for example, `C:\Xilinx\Vivado\2024.1\bin` on Windows, or `/tools/Xilinx/Vivado/2024.1/bin` on Linux):

1. **`run_sim.bat` (Lines 14, 20, and 27):**
   * Replace `D:\2025.2\Vivado\bin\xvlog.bat`, `D:\2025.2\Vivado\bin\xelab.bat`, and `D:\2025.2\Vivado\bin\xsim.bat` with your laptop's Vivado `bin` path (or simply `xvlog.bat`, `xelab.bat`, and `xsim.bat` if Vivado is in your system `PATH`).
2. **`testing/run_all_game_engine_tests.py` (Line 6):**
   * Change `VIVADO_BIN = r"D:\2025.2\Vivado\bin"` to your local Vivado `bin` folder path.
   * *(Note for Linux/macOS users: also change `"xvlog.bat"`, `"xelab.bat"`, and `"xsim.bat"` on lines 31–33 to `"xvlog"`, `"xelab"`, and `"xsim"`).*
3. **`testing/run_all_vga_tests.py` (Line 6):**
   * Change `VIVADO_BIN = r"D:\2025.2\Vivado\bin"` to your local Vivado `bin` folder path.
   * *(Note for Linux/macOS users: also change `"xvlog.bat"`, `"xelab.bat"`, and `"xsim.bat"` on lines 28–30 to `"xvlog"`, `"xelab"`, and `"xsim"`).*
4. **`testing/RV32IM/run_tests.py` (Line 35):**
   * Change `vivado_bin=r"D:\2025.2\Vivado\bin"` to your local Vivado `bin` folder path.

*(Optional)* **If your RISC-V compiler uses a different prefix** (such as `riscv64-unknown-elf-gcc` instead of `riscv-none-elf-gcc` and you did not create symlinks), update the compiler variable names in:
* `software/build_and_export.py` (Lines 10–12)
* `testing/RV32IM/run_tests.py` (Lines 43–45)
* `testing/RV32IM/Makefile` (Lines 1–3)

---

### D. Step-by-Step Instructions to Run Everything

#### Step 1: Clone the Repository
```bash
git clone https://github.com/kaustavbhowal21/battle-tanks.git
cd battle-tanks
```

#### Step 2: Run the C Game Logic & Physics Unit Tests (Runs on Any Laptop Without Vivado)
You can test all 129 assertions covering tank movement, 16-angle trigonometry, wall reflection, brick destruction, and collision handling using your laptop's native C compiler:
```bash
gcc -Isoftware/include software/tests/test_game.c software/src/game.c software/src/physics.c -DHOST_TEST -o test_game
./test_game
```
Expected output: `TEST EXECUTION SUMMARY: 129 RUN | 129 PASSED | 0 FAILED`.

#### Step 3: Build the RISC-V Game Firmware (Optional if C Code Was Modified)
```bash
python software/build_and_export.py
```
This compiles the C code (`main.c`, `game.c`, `physics.c`) into `imem.hex`, `dmem.hex`, and the synthesizable Verilog headers `modules/cpu/firmware_imem.vh` and `modules/cpu/firmware_dmem.vh`.

#### Step 4: Run the Automated Hardware Verification Test Suites
* **Run all 7 Game Engine hardware testbenches:**
  ```bash
  python testing/run_all_game_engine_tests.py
  # Or on Windows: run_game_engine_tests.bat
  ```
* **Run all 5 VGA Display hardware testbenches:**
  ```bash
  python testing/run_all_vga_tests.py
  # Or on Windows: run_vga_tests.bat
  ```
* **Run all 4 RV32IM CPU instruction testbenches (MUL, DIV, AUIPC, Full ISA):**
  ```bash
  python testing/RV32IM/run_tests.py all
  ```

#### Step 5: Run the Full-System Hardware/Software Simulation (`tb_game_top`)
* **On Windows:**
  ```cmd
  run_sim.bat
  ```
* **Manual Command (Windows or Linux Terminal):**
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

#### Step 6: Synthesize and Run on the Digilent Nexys A7 FPGA Board
1. Open **Vivado**, create a new project, and select part **`xc7a100tcsg324-1`**.
2. Add all Verilog source files from `modules/cpu/`, `modules/game_engine/`, `modules/vga/`, and `modules/top_fpga.v`.
3. Add `modules/constraints.xdc` as the constraints file.
4. Add `imem.hex` and `dmem.hex` to the project (or set the `IMEM_HEX` and `DMEM_HEX` parameters on `top_fpga` to empty strings `""` so Vivado uses the built-in `firmware_imem.vh` and `firmware_dmem.vh` headers).
5. Click **Generate Bitstream**, open **Hardware Manager**, program the Nexys A7 board over USB, and connect a VGA monitor.

---

## 4. Detailed Hardware Accelerations Implemented

To keep the C game loop running in roughly **2,200 CPU clock cycles per frame** (well within the 60 FPS frame budget) while driving a real-time 640×480 @ 60 Hz display, five compute-intensive and memory-intensive workloads are accelerated directly in hardware:

---

### 1. RV32M Hardware Multiplier & Iterative Radix-2 Divider (`modules/cpu/`)

**What It Accelerates:**  
Every frame, the C physics engine calculates directional movement and bullet velocity vectors using fixed-point sine/cosine multiplication and converts pixel coordinates into maze grid coordinates by dividing by the 24-pixel tile size. On a standard RV32I processor without hardware multiply/divide, software emulation routines require 30 to 100+ instructions per operation.

**How the Hardware Accelerator Works:**
* **Single-Cycle DSP Multiplier (`multiplier_dsp.v`):**
  * Implements all four RISC-V multiply operations (`MUL`, `MULH`, `MULHSU`, and `MULHU`) using a unified 33×33-bit signed multiplier mapped directly onto the FPGA's dedicated **DSP48E1 slices**.
  * Produces the 32-bit lower or upper product in **1 clock cycle (20 ns)** with zero pipeline stalls.
* **32-Cycle Radix-2 Iterative Divider (`divider_radix2.v`):**
  * Implements signed and unsigned division and remainder (`DIV`, `DIVU`, `REM`, `REMU`) using a compact shift-and-subtract state machine that completes in **32 clock cycles**, saving hundreds of LUTs compared to a combinational divider.
  * Includes **1-cycle hardware shortcuts** for division by zero and signed overflow (`-2147483648 / -1`) so edge cases resolve immediately.
* **Automatic Pipeline Stall & Skid Buffering (`top_rv32m.v`, `IF_ID.v`, `execute.v`):**
  * While a 32-cycle division is in progress, the RV32M controller automatically freezes the Program Counter, buffers any in-flight instruction fetch in a hardware skid buffer, and inserts safe NOP bubbles into the Writeback stage until the quotient or remainder is ready.

---

### 2. Parallel Hardware Collision Engine (`modules/game_engine/collision_engine.v`)

**What It Accelerates:**  
In a software-only implementation, the CPU would have to run nested loops every frame comparing all 8 bullets against each other (28 pairs), all 8 bullets against both tanks (16 pairs), and all 8 bullets against the 400 maze tiles. Our hardware collision engine performs all of these checks continuously in parallel with zero CPU cycles spent on intersection math.

**How the Hardware Accelerator Works:**
* **28 Parallel Bullet-Bullet Bounding-Box Comparators:**
  * Dedicated combinational comparator cells simultaneously check all 28 unique pairs among the 8 active bullets on **every single clock cycle**.
  * Automatically adjusts each bullet's hitbox size between normal bullets (6×6 pixels) and special heavy bullets (12×12 pixels).
* **16 Parallel Bullet-Tank Bounding-Box Comparators:**
  * Simultaneously checks all 8 bullets against both 20×20 pixel tanks on **every single clock cycle**, immediately identifying both which bullet was involved and which player's tank was struck.
* **8-Clock Time-Shared Bullet-Wall Scanner:**
  * A hardware scanner steps through the 8 bullets one per clock cycle (completing a full sweep of all 8 bullets every **160 ns**—over 100,000 sweeps per video frame).
  * For each active bullet, it calculates the bullet's center pixel, converts it into a maze row and column index, and reads the corresponding tile from the dedicated collision port of the Maze RAM.
* **Write-1-to-Clear (W1C) Sticky Hit Registers:**
  * All detected wall, bullet-bullet, and bullet-tank collisions are latched into sticky hardware status registers. The CPU simply reads the summary bitmasks once per frame, applies reflections or health damage, and writes a `1` back to clear the handled collision flags.

---

### 3. Real-Time "Racing-the-Beam" VGA Display Pipeline (`modules/vga/`)

**What It Accelerates:**  
Rendering a 640×480 screen at 60 Hz requires generating **307,200 pixels per frame (18.4 million pixels per second)**. Maintaining and redrawing a full-screen frame buffer in software would consume over 100 Block RAMs and saturate the CPU bus. Instead, our VGA hardware pipeline computes every pixel's color on the fly in lockstep with the monitor's scanline beam, reducing the CPU's rendering workload to just writing 12 coordinate registers per frame.

**How the Hardware Accelerator Works:**
* **Procedural Maze Tile Renderer (`maze_tile_renderer.v`):**
  * Converts the current beam position into a tile row and column address and reads the 2-bit tile code from the Maze RAM.
  * Generates 3D beveled highlights and shadows for steel walls, brick-and-mortar patterns for destructible walls, and grid lines for the arena floor directly in hardware without bitmap textures.
* **16-Angle Vector Tank & Circular Bullet Sprite Engine (`sprite_engine.v`):**
  * Tests whether the current pixel falls inside Player 1's tank, Player 2's tank, or any of the 8 bullets in parallel.
  * **Hardware Vector Barrel Projection:** Instead of storing 16 separate rotated bitmap images per tank, the hardware projects each pixel's offset onto the tank's 16-angle sine/cosine direction vector in real time to draw a clean 2–3 pixel wide rotated gun barrel at any angle.
  * **Hardware Circle Equation Evaluators:** Evaluates the circle equation (`dx² + dy² ≤ r²`) in parallel for all 8 bullets to render smooth circular discs for both 6×6 normal and 10×10 special projectiles.
* **Zero-Divider Bit-Sliced Health HUD (`health_hud.v`):**
  * In the right-hand 160-pixel HUD panel, each heart icon is sized to 8×8 pixels so hardware can determine the heart slot number (`0` to `19`) and the pixel offset inside the heart using simple wire bit-slicing (dividing and taking modulo by 8 with zero logic gates).
* **Pipelined Pixel Priority Mixer (`pixel_priority_mixer.v`):**
  * Composites all visual layers in a single clock cycle using a strict hardware priority order:
    **Health HUD → Special Bullets → Normal Bullets → Player 1 Tank → Player 2 Tank → Maze Walls → Arena Floor**
  * Includes a 2-stage synchronization delay line so horizontal/vertical sync pulses stay perfectly aligned with the pipelined pixel colors.

---

### 4. Contention-Free Mirrored Dual-Port Maze Tile RAM (`modules/game_engine/maze_tile_ram.v`)

**What It Accelerates:**  
The 20×20 maze tile map is needed by three hardware subsystems at the exact same time: the **VGA renderer** (reading tiles at 25 MHz), the **Collision Engine** (scanning tiles at 50 MHz), and the **CPU** (reading tiles for tank movement and writing tiles when bricks are destroyed). A single shared memory would require a bus arbiter that stalls the CPU or causes visual glitches on screen.

**How the Hardware Accelerator Works:**
* Implements **two identical dual-port memories** (**Copy V** for Video and **Copy C** for Collision) that mirror each other:
  * Whenever the CPU updates a maze tile (such as turning a destroyed brick into empty floor), the write is broadcast to **Port A of both Copy V and Copy C simultaneously** on the same clock edge.
  * **Port B of Copy V** is wired exclusively to the VGA Maze Tile Renderer.
  * **Port B of Copy C** is wired exclusively to the Hardware Collision Engine's bullet-wall scanner.
* This architecture guarantees **zero bus contention, zero arbitration latency, and zero CPU wait states** across all three subsystems.

---

### 5. Parallel Hardware Cooldown Timers (`modules/game_engine/cooldown_timers.v`)

**What It Accelerates:**  
Tracking independent 0.5-second primary fire cooldowns and 20.0-second special attack cooldowns for two players in software would require cycle-counting loops or timer interrupts that add overhead to the main game loop.

**How the Hardware Accelerator Works:**
* A shared hardware prescaler divides the 50 MHz system clock down to a precise **1 millisecond tick** (every 50,000 clock cycles).
* Four independent 15-bit hardware down-counters (Player 1 Shoot, Player 1 Special, Player 2 Shoot, and Player 2 Special) automatically decrement on each millisecond tick down to zero:
  * **Primary Shoot Timers:** Load 500 ms (0.5 seconds) when triggered.
  * **Special Attack Timers:** Load 20,000 ms (20.0 seconds) when triggered.
* When a counter reaches zero, its hardware `ready` bit asserts automatically. The CPU checks all four weapon cooldowns in a single clock cycle by reading one status register (`0x8000_0010`) and starts any cooldown with a single write (`0x8000_0014`).
