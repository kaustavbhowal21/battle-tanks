    .section .text.init
    .globl _start
    .type _start, @function

_start:
    # Set up global pointer and stack pointer at top of 4KB data memory
    .option push
    .option norelax
    la gp, __global_pointer$
    .option pop

    li sp, 0x00000FE0

    # Clear .bss section
    la t0, _sbss
    la t1, _ebss
bss_clear_loop:
    bge t0, t1, bss_done
    sw zero, 0(t0)
    addi t0, t0, 4
    j bss_clear_loop
bss_done:

    # Jump to C game entry point
    call main

    # Infinite loop if main returns
halt:
    j halt

    .size _start, . - _start
