OUTPUT_ARCH("riscv")
ENTRY(_start)

MEMORY
{
    /* Instruction memory: ONLY .text lives here, so the linker enforces the real
       4 KB limit of imem on the code alone. */
    ROM     (rx)  : ORIGIN = 0x00000000, LENGTH = 4K
    /* Data memory (stack at the top). */
    RAM     (rwx) : ORIGIN = 0x00000000, LENGTH = 4K
    /* Load image of .rodata/.data. This is not a real memory: dmem.hex is built
       straight from these sections by build_and_export.py (there is no copy loop
       in crt0.s). Keeping it out of ROM stops the lookup tables from being
       counted against the 4 KB of instruction memory. */
    LOADIMG (r)   : ORIGIN = 0x00010000, LENGTH = 4K
}

SECTIONS
{
    .text : {
        *(.text.init)
        *(.text .text.*)
        _etext = .;
    } > ROM

    .rodata : {
        . = ALIGN(4);
        *(.rodata .rodata.*)
        *(.srodata .srodata.*)
        _erodata = .;
    } > RAM AT > LOADIMG

    .data : {
        . = ALIGN(4);
        _sdata = .;
        *(.data .data.*)
        *(.sdata .sdata.*)
        _edata = .;
    } > RAM AT > LOADIMG

    .bss : {
        . = ALIGN(4);
        _sbss = .;
        *(.bss .bss.*)
        *(.sbss .sbss.*)
        *(COMMON)
        _ebss = .;
    } > RAM

    . = ALIGN(4);
    _stack_top = ORIGIN(RAM) + LENGTH(RAM) - 32;
    __global_pointer$ = MIN(_sdata + 0x800, MAX(_sdata, _edata));
}
