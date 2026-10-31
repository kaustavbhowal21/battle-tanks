import os
import sys
import subprocess
import time

VIVADO_BIN = r"D:\2025.2\Vivado\bin"

VGA_TESTS = [
    ("Maze Tile Renderer",   "tb_maze_tile_renderer",   ["modules/vga/maze_tile_renderer.v",   "modules/sim/tb_maze_tile_renderer.v"]),
    ("Sprite Engine",        "tb_sprite_engine",        ["modules/vga/sprite_engine.v",        "modules/sim/tb_sprite_engine.v"]),
    ("Health HUD",           "tb_health_hud",           ["modules/vga/health_hud.v",           "modules/sim/tb_health_hud.v"]),
    ("Pixel Priority Mixer", "tb_pixel_priority_mixer", ["modules/vga/pixel_priority_mixer.v", "modules/sim/tb_pixel_priority_mixer.v"]),
    ("Integrated VGA Subsystem", "tb_vga_subsystem", [
        "modules/vga/vga_timing_gen.v",
        "modules/vga/maze_tile_renderer.v",
        "modules/vga/sprite_engine.v",
        "modules/vga/health_hud.v",
        "modules/vga/pixel_priority_mixer.v",
        "modules/sim/tb_vga_subsystem.v"
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

    cmd_xvlog = [xvlog, "--sv"] + sources
    print("  [1/3] Compiling SystemVerilog sources...")
    res = subprocess.run(cmd_xvlog, cwd=root_dir, capture_output=True, text=True)
    if res.returncode != 0:
        print(f"  [ERROR] xvlog failed:\n{res.stderr}\n{res.stdout}")
        return False, "xvlog compilation failed"

    cmd_xelab = [xelab, "-debug", "typical", "-top", top_module, "-s", snapshot]
    print(f"  [2/3] Elaborating top module {top_module}...")
    res = subprocess.run(cmd_xelab, cwd=root_dir, capture_output=True, text=True)
    if res.returncode != 0:
        print(f"  [ERROR] xelab failed:\n{res.stderr}\n{res.stdout}")
        return False, "xelab elaboration failed"

    cmd_xsim = [xsim, snapshot, "-R"]
    print("  [3/3] Executing simulation in Vivado XSim...")
    res = subprocess.run(cmd_xsim, cwd=root_dir, capture_output=True, text=True)
    output = res.stdout

    lines = output.splitlines()
    for line in lines:
        if "TEST" in line or "PASS" in line or "FAIL" in line or "ERROR" in line or "REPORT" in line or "Rendered" in line:
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
    print("        BATTLE TANKS: VGA DISPLAY HARDWARE VERIFICATION SUITE     ")
    print(f"        Target Root: {root_dir}")
    print("==================================================================")

    results = []
    passed = 0
    failed = 0

    t_start = time.time()
    for title, top_mod, srcs in VGA_TESTS:
        ok, msg = run_test(title, top_mod, srcs, root_dir)
        results.append((title, ok, msg))
        if ok:
            passed += 1
        else:
            failed += 1

    t_total = time.time() - t_start

    print("\n==================================================================")
    print(f"  VGA SUBSYSTEM TEST SUITE SUMMARY ({t_total:.1f}s)")
    print("==================================================================")
    for title, ok, msg in results:
        status_str = "[PASS]" if ok else "[FAIL]"
        print(f"  {status_str:8} {title:<30} : {msg}")
    print("==================================================================")
    print(f"  TOTAL: {len(results)} | PASSED: {passed} | FAILED: {failed}")
    print("==================================================================")

    if failed == 0:
        print("\n>> ALL VGA HARDWARE TESTBENCHES PASSED WITH ZERO ERRORS! <<\n")
        return 0
    else:
        print(f"\n>> {failed} TESTBENCHES FAILED! <<\n")
        return 1

if __name__ == "__main__":
    sys.exit(main())
