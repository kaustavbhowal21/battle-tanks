#include "test_framework.h"

// Custom-0 opcode (0x0B = 7'b0001011) inline assembly wrappers
static inline int32_t asm_mulq16(int32_t a, int32_t b) {
    int32_t res;
    __asm__ volatile (".insn r 0x0B, 0, 0, %0, %1, %2" : "=r"(res) : "r"(a), "r"(b));
    return res;
}

static inline int32_t asm_mulq8(int32_t a, int32_t b) {
    int32_t res;
    __asm__ volatile (".insn r 0x0B, 1, 0, %0, %1, %2" : "=r"(res) : "r"(a), "r"(b));
    return res;
}

static inline uint32_t asm_aabb(uint32_t box1, uint32_t box2) {
    uint32_t res;
    __asm__ volatile (".insn r 0x0B, 2, 0, %0, %1, %2" : "=r"(res) : "r"(box1), "r"(box2));
    return res;
}

int main(void) {
    print_str("\n==========================================================\n");
    print_str("  STARTING TEST: Custom-0 ISA Extensions (mulq & aabb)\n");
    print_str("==========================================================\n");

    // 1. MULQ16 (Q16.16 fixed-point multiply in 1 cycle)
    // 1.5 (0x00018000) * 2.0 (0x00020000) = 3.0 (0x00030000)
    assert_eq("MULQ16: 1.5 * 2.0 = 3.0", asm_mulq16(0x00018000, 0x00020000), 0x00030000);
    // 2.5 (0x00028000) * 4.0 (0x00040000) = 10.0 (0x000A0000)
    assert_eq("MULQ16: 2.5 * 4.0 = 10.0", asm_mulq16(0x00028000, 0x00040000), 0x000A0000);
    // Negative * Positive: -1.0 (0xFFFF0000) * 3.0 (0x00030000) = -3.0 (0xFFFD0000)
    assert_eq("MULQ16: -1.0 * 3.0 = -3.0", asm_mulq16((int32_t)0xFFFF0000, 0x00030000), (int32_t)0xFFFD0000);

    // 2. MULQ8 (Q24.8 fixed-point multiply matching game FP_SHIFT = 8)
    // 1.5 (384) * 2.0 (512) = 3.0 (768)
    assert_eq("MULQ8: 1.5 * 2.0 = 3.0", asm_mulq8(384, 512), 768);
    // 3.0 (768) * 0.5 (128) = 1.5 (384)
    assert_eq("MULQ8: 3.0 * 0.5 = 1.5", asm_mulq8(768, 128), 384);
    // Negative * Positive: -2.0 (-512) * 4.0 (1024) = -8.0 (-2048)
    assert_eq("MULQ8: -2.0 * 4.0 = -8.0", asm_mulq8(-512, 1024), -2048);

    // 3. AABB (Single-cycle 2D Box Overlap Unit)
    // Box 1 at (100, 100), Box 2 at (105, 105) -> overlap
    uint32_t box1 = (100U << 16) | 100U;
    uint32_t box2 = (105U << 16) | 105U;
    assert_eq("AABB: Overlapping boxes (100,100) vs (105,105)", asm_aabb(box1, box2), 1);

    // Box 3 at (200, 200) -> no overlap
    uint32_t box3 = (200U << 16) | 200U;
    assert_eq("AABB: Non-overlapping boxes (100,100) vs (200,200)", asm_aabb(box1, box3), 0);

    // Box 4 touching boundary at (116, 100) -> no overlap (strict <)
    uint32_t box4 = (116U << 16) | 100U;
    assert_eq("AABB: Touching boundary at edge (100+16, 100)", asm_aabb(box1, box4), 0);

    return test_summary("Custom-0 ISA Extensions (mulq & aabb)");
}

