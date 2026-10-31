#include "test_framework.h"

static inline int32_t asm_div(int32_t a, int32_t b) {
    int32_t res;
    __asm__ volatile ("div %0, %1, %2" : "=r"(res) : "r"(a), "r"(b));
    return res;
}

static inline uint32_t asm_divu(uint32_t a, uint32_t b) {
    uint32_t res;
    __asm__ volatile ("divu %0, %1, %2" : "=r"(res) : "r"(a), "r"(b));
    return res;
}

static inline int32_t asm_rem(int32_t a, int32_t b) {
    int32_t res;
    __asm__ volatile ("rem %0, %1, %2" : "=r"(res) : "r"(a), "r"(b));
    return res;
}

static inline uint32_t asm_remu(uint32_t a, uint32_t b) {
    uint32_t res;
    __asm__ volatile ("remu %0, %1, %2" : "=r"(res) : "r"(a), "r"(b));
    return res;
}

int main(void) {
    print_str("\n==========================================================\n");
    print_str("  STARTING TEST: RV32M Hardware Iterative Divider\n");
    print_str("==========================================================\n");

    // 1. DIV (Signed Division)
    assert_eq("DIV: 100 / 5", asm_div(100, 5), 20);
    assert_eq("DIV: -100 / 5", asm_div(-100, 5), -20);
    assert_eq("DIV: 100 / -5", asm_div(100, -5), -20);
    assert_eq("DIV: -100 / -5", asm_div(-100, -5), 20);
    assert_eq("DIV: Truncation towards zero (7 / 3)", asm_div(7, 3), 2);
    assert_eq("DIV: Truncation towards zero (-7 / 3)", asm_div(-7, 3), -2);

    // RISC-V Spec Corner Cases
    assert_eq("DIV: Divide-by-zero (123 / 0 -> -1)", asm_div(123, 0), -1);
    assert_eq("DIV: Signed Overflow (-2^31 / -1 -> -2^31)", asm_div((int32_t)0x80000000, -1), (int32_t)0x80000000);

    // 2. DIVU (Unsigned Division)
    assert_eq("DIVU: 100 / 5", asm_divu(100, 5), 20);
    assert_eq("DIVU: Large unsigned (0xFFFFFFFF / 2)", asm_divu(0xFFFFFFFFU, 2), 0x7FFFFFFFU);
    assert_eq("DIVU: Divide-by-zero (0x123 / 0 -> 0xFFFFFFFF)", asm_divu(0x123, 0), 0xFFFFFFFFU);

    // 3. REM (Signed Remainder)
    assert_eq("REM: 100 % 7", asm_rem(100, 7), 2);
    assert_eq("REM: -100 % 7", asm_rem(-100, 7), -2);
    assert_eq("REM: 100 % -7", asm_rem(100, -7), 2);
    assert_eq("REM: -100 % -7", asm_rem(-100, -7), -2);
    assert_eq("REM: Divide-by-zero (42 % 0 -> 42)", asm_rem(42, 0), 42);
    assert_eq("REM: Signed Overflow (-2^31 % -1 -> 0)", asm_rem((int32_t)0x80000000, -1), 0);

    // 4. REMU (Unsigned Remainder)
    assert_eq("REMU: 100 % 7", asm_remu(100, 7), 2);
    assert_eq("REMU: 0xFFFFFFFF % 10", asm_remu(0xFFFFFFFFU, 10), 5);
    assert_eq("REMU: Divide-by-zero (0xABC % 0 -> 0xABC)", asm_remu(0xABC, 0), 0xABC);

    return test_summary("RV32M Divider & Remainder Unit");
}
