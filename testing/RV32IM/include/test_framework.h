#ifndef TEST_FRAMEWORK_H
#define TEST_FRAMEWORK_H

#include <stdint.h>

#define MMIO_SIM_PUTC       (*(volatile uint32_t *)0x80000008U)
#define MMIO_SIM_STATUS     (*(volatile uint32_t *)0x8000000CU)

#define STATUS_PASS         0xCAFEF00DU
#define STATUS_FAIL         0xDEADBEEFU

static int g_tests_passed = 0;
static int g_tests_failed = 0;

static inline void put_char(char c) {
    MMIO_SIM_PUTC = (uint32_t)c;
}

static inline void print_str(const char *s) {
    while (*s) {
        put_char(*s++);
    }
}

static inline void print_hex(uint32_t val) {
    print_str("0x");
    for (int i = 7; i >= 0; i--) {
        int nibble = (val >> (i * 4)) & 0xF;
        if (nibble < 10)
            put_char('0' + nibble);
        else
            put_char('A' + (nibble - 10));
    }
}

static inline void print_dec(int32_t val) {
    if (val == 0) {
        put_char('0');
        return;
    }
    if (val < 0) {
        put_char('-');
        val = -val;
    }
    char buf[12];
    int idx = 0;
    while (val > 0) {
        buf[idx++] = '0' + (val % 10);
        val /= 10;
    }
    for (int i = idx - 1; i >= 0; i--) {
        put_char(buf[i]);
    }
}

static inline void test_start(const char *name) {
    print_str("  [CHECK] ");
    print_str(name);
    print_str(" ... ");
}

static inline void assert_eq(const char *name, uint32_t actual, uint32_t expected) {
    test_start(name);
    if (actual == expected) {
        print_str("PASS (Result: ");
        print_hex(actual);
        print_str(")\n");
        g_tests_passed++;
    } else {
        print_str("FAILED!\n");
        print_str("          Expected: ");
        print_hex(expected);
        print_str(" | Got: ");
        print_hex(actual);
        print_str("\n");
        g_tests_failed++;
    }
}

static inline int test_summary(const char *suite_name) {
    print_str("\n==========================================================\n");
    print_str("  TEST SUITE: ");
    print_str(suite_name);
    print_str("\n  Passed: ");
    print_dec(g_tests_passed);
    print_str(" | Failed: ");
    print_dec(g_tests_failed);
    print_str("\n");

    if (g_tests_failed == 0) {
        print_str("  >>> VERDICT: ALL TESTS PASSED SUCCESSFULLY! <<<\n");
        print_str("==========================================================\n");
        MMIO_SIM_STATUS = STATUS_PASS;
        return 0;
    } else {
        print_str("  >>> VERDICT: TEST SUITE FAILED! <<<\n");
        print_str("==========================================================\n");
        MMIO_SIM_STATUS = STATUS_FAIL;
        return 1;
    }
}

#endif // TEST_FRAMEWORK_H
