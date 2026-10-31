import os
import sys
import subprocess
import struct
import shutil

TESTS = [
    "test_mul",
    "test_div",
    "test_auipc",
    "test_rv32im_all"
]

def bin_to_hex(bin_filename, hex_filename, num_words=1024, default_word=0):
    words = []
    if os.path.exists(bin_filename):
        with open(bin_filename, "rb") as f:
            data = f.read()
        for i in range(0, len(data), 4):
            chunk = data[i:i+4]
            if len(chunk) < 4:
                chunk = chunk.ljust(4, b'\x00')
            val = struct.unpack("<I", chunk)[0]
            words.append(val)
    
    while len(words) < num_words:
        words.append(default_word)

    words = words[:num_words]

    with open(hex_filename, "w", encoding="utf-8") as f:
        for w in words:
            f.write(f"{w:08x}\n")

def run_test(test_name, vivado_bin=r"D:\2025.2\Vivado\bin"):
    print(f"\n##########################################################")
    print(f"  RUNNING TESTCASE: {test_name}.c")
    print(f"##########################################################")

    cur_dir = os.path.dirname(os.path.abspath(__file__))
    os.chdir(cur_dir)

    gcc = "riscv-none-elf-gcc"
    objcopy = "riscv-none-elf-objcopy"
    objdump = "riscv-none-elf-objdump"

    elf_file = f"{test_name}.elf"
    src_file = os.path.join("src", f"{test_name}.c")

    # 1. Compile C testcase
    cmd_gcc = [
        gcc,
        "-march=rv32im",
        "-mabi=ilp32",
        "-O2",
        "-nostdlib",
        "-nostartfiles",
        "-ffreestanding",
        "-Iinclude",
        "-T", "linker_test.ld",
        "crt0_test.s",
        src_file,
        "-o", elf_file
    ]
    res = subprocess.run(cmd_gcc, capture_output=True, text=True)
    if res.returncode != 0:
        print(f"[ERROR] Compilation failed for {test_name}:\n{res.stderr}")
        return False

    # Disassembly
    with open(f"{test_name}.dis", "w", encoding="utf-8") as f:
        subprocess.run([objdump, "-d", "-M", "numeric", elf_file], stdout=f)

    # 2. Extract binary and create imem.hex & dmem.hex
    subprocess.run([objcopy, "-O", "binary", "--only-section=.text*", elf_file, "imem.bin"])
    subprocess.run([objcopy, "-O", "binary", "--only-section=.rodata*", "--only-section=.data*", elf_file, "dmem.bin"])

    bin_to_hex("imem.bin", "imem.hex", num_words=1024, default_word=0x00000013)
    bin_to_hex("dmem.bin", "dmem.hex", num_words=1024, default_word=0x00000000)

    # Also copy to root directory just in case simulator looks in cwd
    shutil.copyfile("imem.hex", os.path.join("..", "..", "imem.hex"))
    shutil.copyfile("dmem.hex", os.path.join("..", "..", "dmem.hex"))

    # 3. Compile Verilog with xvlog
    xvlog = os.path.join(vivado_bin, "xvlog.bat")
    xelab = os.path.join(vivado_bin, "xelab.bat")
    xsim  = os.path.join(vivado_bin, "xsim.bat")

    cmd_xvlog = [
        xvlog, "--sv",
        "-i", "../../modules/cpu",
        "../../modules/cpu/pipeline.v",
        "../../modules/cpu/memory.v",
        "../../modules/cpu/multiplier_dsp.v",
        "../../modules/cpu/divider_radix2.v",
        "../../modules/cpu/top_rv32m.v",
        "../../modules/game_engine/mmio_interconnect.v",
        "tb_rv32im_test.v"
    ]
    res_xvlog = subprocess.run(cmd_xvlog, capture_output=True, text=True)
    if res_xvlog.returncode != 0:
        print(f"[ERROR] xvlog failed:\n{res_xvlog.stderr}\n{res_xvlog.stdout}")
        return False

    # 4. Elaborate with xelab
    snapshot = f"sim_{test_name}"
    cmd_xelab = [
        xelab, "-debug", "typical", "-top", "tb_rv32im_test", "-s", snapshot
    ]
    res_xelab = subprocess.run(cmd_xelab, capture_output=True, text=True)
    if res_xelab.returncode != 0:
        print(f"[ERROR] xelab failed:\n{res_xelab.stderr}\n{res_xelab.stdout}")
        return False

    # 5. Run simulation with xsim
    cmd_xsim = [xsim, snapshot, "-R"]
    res_xsim = subprocess.run(cmd_xsim, capture_output=True, text=True)

    # Print simulator verbal output
    output_lines = res_xsim.stdout.split("\n")
    relevant = False
    passed = False
    for line in output_lines:
        if "STARTING TEST" in line or "RV32IM" in line or "CHECK" in line:
            relevant = True
        if "TEST SUITE PASS" in line or "Simulation completed with SUCCESS" in line:
            passed = True
        if relevant:
            print(line)

    if passed:
        print(f"\n>> VERBAL RESULT FOR {test_name}: [PASS]")
        return True
    else:
        print(f"\n>> VERBAL RESULT FOR {test_name}: [FAIL]")
        return False

def main():
    target = sys.argv[1] if len(sys.argv) > 1 else "all"

    tests_to_run = TESTS if target == "all" else [target]
    results = {}

    for t in tests_to_run:
        success = run_test(t)
        results[t] = "PASS" if success else "FAIL"

    print("\n" + "=" * 60)
    print("         RV32IM VERIFICATION SUITE FINAL SUMMARY")
    print("=" * 60)
    all_passed = True
    for t, status in results.items():
        print(f"  * {t.ljust(25)} : {status}")
        if status != "PASS":
            all_passed = False

    print("=" * 60)
    if all_passed:
        print("  OVERALL VERDICT: ALL TESTCASES PASSED ON RV32IM HARDWARE!")
    else:
        print("  OVERALL VERDICT: SOME TESTCASES FAILED!")
    print("=" * 60 + "\n")

    return 0 if all_passed else 1

if __name__ == "__main__":
    sys.exit(main())
