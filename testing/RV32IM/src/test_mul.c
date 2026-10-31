#include "test_framework.h"

// Explicit inline assembly wrappers to guarantee RV32M opcode generation
static inline int32_t asm_mul(int32_t a, int32_t b) {
    int32_t res;
    __asm__ volatile ("mul %0, %1, %2" : "=r"(res) : "r"(a), "r"(b));
    return res;
}

static inline int32_t asm_mulh(int32_t a, int32_t b) {
    int32_t res;
    __asm__ volatile ("mulh %0, %1, %2" : "=r"(res) : "r"(a), "r"(b));
    return res;
}

static inline int32_t asm_mulhsu(int32_t a, uint32_t b) {
    int32_t res;
    __asm__ volatile ("mulhsu %0, %1, %2" : "=r"(res) : "r"(a), "r"(b));
    return res;
}

static inline uint32_t asm_mulhu(uint32_t a, uint32_t b) {
    uint32_t res;
    __asm__ volatile ("mulhu %0, %1, %2" : "=r"(res) : "r"(a), "r"(b));
    return res;
}

int main(void) {
    print_str("\n==========================================================\n");
    print_str("  STARTING TEST: RV32M Hardware Multiplier (DSP48E1)\n");
    print_str("==========================================================\n");

    // 1. MUL (Lower 32-bit product)
    assert_eq("MUL: Positive x Positive (15 * 25)", asm_mul(15, 25), 375);
    assert_eq("MUL: Positive x Negative (20 * -5)", asm_mul(20, -5), -100);
    assert_eq("MUL: Negative x Negative (-12 * -8)", asm_mul(-12, -8), 96);
    assert_eq("MUL: Zero operand (0 * 12345)", asm_mul(0, 12345), 0);
    assert_eq("MUL: 32-bit Overflow wrap (0x7FFFFFFF * 2)", asm_mul(0x7FFFFFFF, 2), 0xFFFFFFFEU);

    // 2. MULH (Signed x Signed -> Upper 32 bits)
    assert_eq("MULH: Small operands (100 * 200)", asm_mulh(100, 200), 0);
    assert_eq("MULH: (-1 * -1)", asm_mulh(-1, -1), 0);
    assert_eq("MULH: Max Positive (0x7FFFFFFF * 0x7FFFFFFF)", asm_mulh(0x7FFFFFFF, 0x7FFFFFFF), 0x3FFFFFFFU);
    assert_eq("MULH: Negative x Positive (-2 * 0x40000000)", asm_mulh(-2, 0x40000000), 0xFFFFFFFFU);

    // 3. MULHU (Unsigned x Unsigned -> Upper 32 bits)
    assert_eq("MULHU: Small operands (1000 * 2000)", asm_mulhu(1000, 2000), 0);
    assert_eq("MULHU: Max Unsigned (0xFFFFFFFF * 0xFFFFFFFF)", asm_mulhu(0xFFFFFFFFU, 0xFFFFFFFFU), 0xFFFFFFFEU);
    assert_eq("MULHU: 0x80000000 * 2", asm_mulhu(0x80000000U, 2), 1);

    // 4. MULHSU (Signed x Unsigned -> Upper 32 bits)
    assert_eq("MULHSU: Positive x Unsigned (100 * 200)", asm_mulhsu(100, 200), 0);
    assert_eq("MULHSU: (-1 * 0xFFFFFFFF)", asm_mulhsu(-1, 0xFFFFFFFFU), 0xFFFFFFFFU);
    assert_eq("MULHSU: (-1 * 1)", asm_mulhsu(-1, 1), 0xFFFFFFFFU);

    return test_summary("RV32M Multiplier Unit");
}
