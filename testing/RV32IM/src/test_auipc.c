#include "test_framework.h"

int main(void) {
    print_str("\n==========================================================\n");
    print_str("  STARTING TEST: AUIPC (Add Upper Immediate to PC)\n");
    print_str("==========================================================\n");

    uint32_t pc1, pc2;

    // Execute two consecutive AUIPC instructions with 0 immediate
    __asm__ volatile (
        "auipc %0, 0\n"
        "auipc %1, 0\n"
        : "=r"(pc1), "=r"(pc2)
    );

    // pc2 must be exactly pc1 + 4!
    assert_eq("AUIPC: PC delta check (pc2 - pc1 == 4)", pc2 - pc1, 4);

    // Execute AUIPC with non-zero upper immediate (0x1000 -> shifted << 12 = 0x01000000)
    uint32_t pc_offset;
    __asm__ volatile (
        "1: auipc %0, 0x1000\n"
        : "=r"(pc_offset)
    );

    // Delta between pc_offset and pc1 should include the 0x01000000 offset
    uint32_t delta = pc_offset - pc1;
    assert_eq("AUIPC: Upper 20-bit immediate addition (delta >= 0x01000000)", 
              (delta >= 0x01000000U) && (delta < 0x01000020U), 1);

    return test_summary("AUIPC Instruction Verification");
}
