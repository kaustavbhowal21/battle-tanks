## battle-tanks
Hardware-Accelerated 2D Battle Tanks with Real-Time Reflection Physics on an RV32IM FPGA Soft-Core

# 1. System Description
A 2-player tank combat game on a VGA monitor, run by an RV32IM soft-core processor (3-stage pipeline) extended with the RV32M MUL/DIV instructions. Memory-mapped hardware tile/sprite, collision and timer units remove the rendering and collision bottleneck, so the game holds at least 30 FPS. Players steer tanks around a square maze arena and fire circular bullets that bounce off walls by angular reflection.
# 2. Use Cases
•	Interactive two-player gaming on a custom RISC-V soft-core, with buttons on the FPGA board or on a breadboard.
•	Real-time 2D projectile tracking and reflection physics (a small physics workload accelerated by MUL/DIV).
•	Teaching platform for memory-mapped peripherals: video, timers and collision units on a CPU bus.
# 3. FPGA Relevance
•	Dedicated VGA, tile and sprite hardware generates pixels in real time, so the CPU never redraws the arena.
•	Collision comparators and cooldown timers run in parallel with the CPU, which a software-only design would need extra cycles for.
•	A custom ISA extension (MUL/DIV) and custom peripherals are only possible on a reconfigurable fabric.
# 4. System Scope
Minimum System (Commitment)
•	RV32M MUL/DIV implemented in the pipeline and verified (module testbench + processor simulation).
•	Basic C tank movement and firing, with game state printed over UART/terminal.
•	VGA timing controller driving a stable 640x480 image on the FPGA.
Goal System
•	Playable VGA game at 30 FPS or more: maze tile map, 2 tank sprites and up to 10 circular bullets drawn by hardware.
•	Bullets bounce off maze walls with angular reflection; bullets collide and cancel; hits reduce health (normal bullet 1, special bullet 5, 20 hearts per tank).
•	Hardware cooldowns: 0.5 s per bullet, 20 s for the special move; 20-heart health bars on screen.
Stretch Goal
•	Destructible maze walls and a game-over / restart screen.
•	Audio synthesizer output for shooting and hit sound effects.
# 5. Design Goals
•	Latency: Game-logic update (movement, reflection, health) in 5,000 CPU cycles or fewer per frame, measured in simulation; hardware collision results available within 1 frame.
•	Throughput: Stable VGA output with game loop at 30 FPS or more.
•	Resource usage: Fits the target board's LUT, BRAM and DSP budget; MUL mapped to DSP slices, DIV multi-cycle (about 32 cycles) to save LUTs. Final utilisation numbers reported.
•	Correctness: MUL/DIV match golden vectors including edge cases (divide by zero, signed overflow); no bullet tunnelling through walls; bullet-vs-tank and bullet-vs-bullet collisions at boundaries; cooldowns exact.
# 6. Implementation Approach
•	New modules: RV32M MUL/DIV unit, VGA timing controller, tile/sprite engine with VRAM arbiter, collision unit, cooldown timer, button debouncer.
•	Datapath/control: Stall logic for multi-cycle DIV in the 3-stage pipeline; new bus address ranges for the memory-mapped peripherals; collision hit flags in a status register polled by the CPU.
•	Verification: Module-level testbenches with golden I/O vectors; processor-level simulation of RV32M programs; C game-loop testing on simulation and then on the FPGA (compiled for rv32im).
# 7. Demonstration Plan
•	Input: Per player: forward, backward, turn left, turn right, shoot, special move, using FPGA buttons or a breadboard.
•	Processing: The RV32IM CPU runs the C game loop (movement, reflection, health); hardware renders the arena and sprites and flags collisions and cooldown expiry.
•	Output: VGA display of the maze arena, tank sprites, moving bullets and 20-heart health bars; UART log for the minimum system.
# 8. High Level Timeline
A core module of the minimum system is tested by 25 Oct, and the minimum system (commitment) is met by 1 Nov.
Week	Milestone (deliverable)
5 - 11 Oct	RV32M MUL/DIV module in Verilog with module-level testbench passing golden vectors; VGA timing controller in simulation. (code + testbench)
12 - 18 Oct	Pipeline stall integration for DIV with processor-level simulation of MUL/DIV C tests; tile/sprite renderer and VRAM arbiter verified in simulation; button debouncer tested. (code + testbench)
19 - 25 Oct	Core functionality on FPGA: VGA output showing maze tile map and sprites; collision unit and cooldown timer with testbenches. (FPGA demo + testbench)
26 Oct - 1 Nov	C game loop integrated; MINIMUM SYSTEM end to end: MUL/DIV running, tank movement and firing over UART, stable VGA. (FPGA demo)
2 - 6 Nov	Angular bullet reflection, bullet cancelling, health bars and special move on the VGA game at 30 FPS or more; final demo rehearsal and report (stretch features only if time remains). (FPGA demo)


# 9. Teamwork Plan
•	Each member owns at least one hardware module with its own testbench and works on a feature branch with pull requests reviewed by a teammate; each member keeps regular, meaningful Git commits.
•	Short weekly sync to check milestones; interfaces (bus addresses, register maps) agreed in week 1 and documented in the repo.

Member	Responsibilities
Kaustav Bhowal	Hardware: RV32M MUL/DIV unit (multi-cycle DIV) and pipeline stall logic. Testing: golden I/O math testbenches, processor-level RV32M simulation.
Jayesh Banzal 	Hardware: VGA timing controller and VRAM bus arbiter. Testing: pixel clock, sync and blanking verification.
Mahendra  	Hardware: cooldown timer and bounding-box collision unit (bullet-tank, bullet-bullet). Software: C collision/health integration.
Kabir Gupta 	Hardware: button debouncer and I/O mapping. Software: main C game loop, physics engine, reflection and coordinate math.
Jayesh Vijaivargia 	Hardware: tile/sprite generator and tile map registers. Software/Testing: visual assets (maze, tanks, hearts), system-level simulation and FPGA integration.
