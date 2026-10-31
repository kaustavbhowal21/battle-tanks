#include "test_framework.h"

// Inline assembly wrappers
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

// Test pipeline stall immunity during multi-cycle division
static int test_div_stall_immunity(void) {
    int32_t div_res = 0;
    int32_t add_res = 0;

    // Execute DIV immediately followed by ADD without NOPs
    // Tests that divider stalls EX stage without leaking uncomputed data to WB
    __asm__ volatile (
        "li t0, 1000\n"
        "li t1, 25\n"
        "li t2, 50\n"
        "div %0, t0, t1\n"    // 1000 / 25 = 40 (takes 32 cycles)
        "addi %1, t2, 10\n"   // 50 + 10 = 60
        : "=r"(div_res), "=r"(add_res)
        :
        : "t0", "t1", "t2"
    );

    return (div_res == 40) && (add_res == 60);
}

int main(void) {
    print_str("==========================================================\n");
    print_str("  RV32IM SOFT-CORE PROCESSOR EXTENSION VERIFICATION SUITE \n");
    print_str("==========================================================\n\n");

    print_str("--- SECTION 1: RV32M MULTIPLIER TESTS ---\n");
    assert_eq("MUL: 15 * 25", asm_mul(15, 25), 375);
    assert_eq("MUL: 20 * -5", asm_mul(20, -5), -100);
    assert_eq("MUL: -12 * -8", asm_mul(-12, -8), 96);
    assert_eq("MUL: 0x7FFFFFFF * 2 (overflow wrap)", asm_mul(0x7FFFFFFF, 2), 0xFFFFFFFEU);

    assert_eq("MULH: Max Positive (0x7FFFFFFF * 0x7FFFFFFF)", asm_mulh(0x7FFFFFFF, 0x7FFFFFFF), 0x3FFFFFFFU);
    assert_eq("MULH: Negative x Positive (-2 * 0x40000000)", asm_mulh(-2, 0x40000000), 0xFFFFFFFFU);

    assert_eq("MULHU: Max Unsigned (0xFFFFFFFF * 0xFFFFFFFF)", asm_mulhu(0xFFFFFFFFU, 0xFFFFFFFFU), 0xFFFFFFFEU);
    assert_eq("MULHSU: (-1 * 0xFFFFFFFF)", asm_mulhsu(-1, 0xFFFFFFFFU), 0xFFFFFFFFU);

    print_str("\n--- SECTION 2: RV32M DIVIDER & REMAINDER TESTS ---\n");
    assert_eq("DIV: 100 / 5", asm_div(100, 5), 20);
    assert_eq("DIV: -100 / 5", asm_div(-100, 5), -20);
    assert_eq("DIV: 100 / -5", asm_div(100, -5), -20);
    assert_eq("DIV: -100 / -5", asm_div(-100, -5), 20);
    assert_eq("DIV: Divide-by-Zero (123 / 0 -> -1)", asm_div(123, 0), -1);
    assert_eq("DIV: Signed Overflow (-2^31 / -1 -> -2^31)", asm_div((int32_t)0x80000000, -1), (int32_t)0x80000000);

    assert_eq("DIVU: 0xFFFFFFFF / 2", asm_divu(0xFFFFFFFFU, 2), 0x7FFFFFFFU);
    assert_eq("DIVU: Divide-by-Zero (0x123 / 0 -> 0xFFFFFFFF)", asm_divu(0x123, 0), 0xFFFFFFFFU);

    assert_eq("REM: 100 % 7", asm_rem(100, 7), 2);
    assert_eq("REM: -100 % 7", asm_rem(-100, 7), -2);
    assert_eq("REM: Divide-by-Zero (42 % 0 -> 42)", asm_rem(42, 0), 42);

    assert_eq("REMU: 0xFFFFFFFF % 10", asm_remu(0xFFFFFFFFU, 10), 5);
    assert_eq("REMU: Divide-by-Zero (0xABC % 0 -> 0xABC)", asm_remu(0xABC, 0), 0xABC);

    print_str("\n--- SECTION 3: AUIPC INSTRUCTION TEST ---\n");
    uint32_t pc1, pc2;
    __asm__ volatile (
        "auipc %0, 0\n"
        "auipc %1, 0\n"
        : "=r"(pc1), "=r"(pc2)
    );
    assert_eq("AUIPC: PC delta (pc2 - pc1 == 4)", pc2 - pc1, 4);

    print_str("\n--- SECTION 4: DIV PIPELINE STALL & HAZARD TEST ---\n");
    assert_eq("DIV STALL: Writeback Suppression & Hazard Immunity", test_div_stall_immunity(), 1);

    return test_summary("Comprehensive RV32IM Extension Suite");
}
