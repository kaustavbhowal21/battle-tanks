import os
import sys
import subprocess
import time

VIVADO_BIN = r"D:\2025.2\Vivado\bin"

TESTS = [
    ("Input Controller", "tb_input_controller", ["modules/game_engine/input_controller.v", "modules/sim/tb_input_controller.v"]),
    ("Cooldown Timers",  "tb_cooldown_timers",  ["modules/game_engine/cooldown_timers.v",  "modules/sim/tb_cooldown_timers.v"]),
    ("Maze Tile RAM",    "tb_maze_tile_ram",    ["modules/game_engine/maze_tile_ram.v",    "modules/sim/tb_maze_tile_ram.v"]),
    ("Sprite HUD Regfile","tb_sprite_hud_regfile",["modules/game_engine/sprite_hud_regfile.v","modules/sim/tb_sprite_hud_regfile.v"]),
    ("Collision Engine", "tb_collision_engine", ["modules/game_engine/collision_engine.v", "modules/sim/tb_collision_engine.v"]),
    ("MMIO Interconnect","tb_mmio_interconnect",["modules/game_engine/mmio_interconnect.v","modules/sim/tb_mmio_interconnect.v"]),
    ("Game Engine Subsystem","tb_game_engine_subsystem", [
        "modules/game_engine/input_controller.v",
        "modules/game_engine/cooldown_timers.v",
        "modules/game_engine/maze_tile_ram.v",
        "modules/game_engine/sprite_hud_regfile.v",
        "modules/game_engine/collision_engine.v",
        "modules/game_engine/mmio_interconnect.v",
        "modules/sim/tb_game_engine_subsystem.v"
    ])
]

def run_test(title, top_module, sources, root_dir):
    print(f"\n==================================================================")
    print(f"  RUNNING HARDWARE TEST: {title} ({top_module})")
    print(f"==================================================================")

    xvlog = os.path.join(VIVADO_BIN, "xvlog.bat")
    xelab = os.path.join(VIVADO_BIN, "xelab.bat")
    xsim  = os.path.join(VIVADO_BIN, "xsim.bat")

    snapshot = f"sim_{top_module}"

    # 1. Compile sources with xvlog
    cmd_xvlog = [xvlog, "--sv"] + sources
    print("  [1/3] Compiling SystemVerilog sources...")
    res = subprocess.run(cmd_xvlog, cwd=root_dir, capture_output=True, text=True)
    if res.returncode != 0:
        print(f"  [ERROR] xvlog failed:\n{res.stderr}\n{res.stdout}")
        return False, "xvlog compilation failed"

    # 2. Elaborate with xelab
    cmd_xelab = [xelab, "-debug", "typical", "-top", top_module, "-s", snapshot]
    print(f"  [2/3] Elaborating top module {top_module}...")
    res = subprocess.run(cmd_xelab, cwd=root_dir, capture_output=True, text=True)
    if res.returncode != 0:
        print(f"  [ERROR] xelab failed:\n{res.stderr}\n{res.stdout}")
        return False, "xelab elaboration failed"

    # 3. Simulate with xsim
    cmd_xsim = [xsim, snapshot, "-R"]
    print("  [3/3] Executing simulation in Vivado XSim...")
    res = subprocess.run(cmd_xsim, cwd=root_dir, capture_output=True, text=True)
    output = res.stdout

    # Print filtered relevant output
    lines = output.splitlines()
    for line in lines:
        if "TEST" in line or "PASS" in line or "FAIL" in line or "ERROR" in line or "STEP" in line:
            print(f"    {line.strip()}")

    if "TEST PASSED" in output or "TESTS PASSED" in output:
        print(f"  >> RESULT: {title} PASSED! <<")
        return True, "PASSED"
    else:
        print(f"  >> RESULT: {title} FAILED! <<")
        return False, "FAILED"

def main():
    root_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
    print("==================================================================")
    print("        BATTLE TANKS: GAME ENGINE HARDWARE VERIFICATION SUITE     ")
    print(f"        Target Root: {root_dir}")
    print("==================================================================")

    results = []
    passed = 0
    failed = 0

    t_start = time.time()
    for title, top_mod, srcs in TESTS:
        ok, msg = run_test(title, top_mod, srcs, root_dir)
        results.append((title, ok, msg))
        if ok:
            passed += 1
        else:
            failed += 1

    t_total = time.time() - t_start

    print("\n==================================================================")
    print(f"  GAME ENGINE TEST SUITE SUMMARY ({t_total:.1f}s)")
    print("==================================================================")
    for title, ok, msg in results:
        status_str = "[PASS]" if ok else "[FAIL]"
        print(f"  {status_str:8} {title:<30} : {msg}")
    print("==================================================================")
    print(f"  TOTAL: {len(results)} | PASSED: {passed} | FAILED: {failed}")
    print("==================================================================")

    if failed == 0:
        print("\n>> ALL 7 GAME ENGINE TESTBENCHES PASSED WITH ZERO ERRORS! <<\n")
        return 0
    else:
        print(f"\n>> {failed} TESTBENCHES FAILED! <<\n")
        return 1

if __name__ == "__main__":
    sys.exit(main())
