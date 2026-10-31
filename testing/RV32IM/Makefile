CC      = riscv-none-elf-gcc
OBJDUMP = riscv-none-elf-objdump
OBJCOPY = riscv-none-elf-objcopy

CFLAGS  = -march=rv32im -mabi=ilp32 -O2 -nostdlib -nostartfiles -ffreestanding -Iinclude
LDFLAGS = -T linker_test.ld

TESTS   = test_mul test_div test_auipc test_rv32im_all

.PHONY: all clean check $(TESTS)

all: $(TESTS)

test_mul: src/test_mul.c crt0_test.s
	@echo [CC] Compiling test_mul...
	$(CC) $(CFLAGS) $(LDFLAGS) crt0_test.s src/test_mul.c -o test_mul.elf
	$(OBJDUMP) -d -M numeric test_mul.elf > test_mul.dis

test_div: src/test_div.c crt0_test.s
	@echo [CC] Compiling test_div...
	$(CC) $(CFLAGS) $(LDFLAGS) crt0_test.s src/test_div.c -o test_div.elf
	$(OBJDUMP) -d -M numeric test_div.elf > test_div.dis

test_auipc: src/test_auipc.c crt0_test.s
	@echo [CC] Compiling test_auipc...
	$(CC) $(CFLAGS) $(LDFLAGS) crt0_test.s src/test_auipc.c -o test_auipc.elf
	$(OBJDUMP) -d -M numeric test_auipc.elf > test_auipc.dis

test_rv32im_all: src/test_rv32im_all.c crt0_test.s
	@echo [CC] Compiling test_rv32im_all...
	$(CC) $(CFLAGS) $(LDFLAGS) crt0_test.s src/test_rv32im_all.c -o test_rv32im_all.elf
	$(OBJDUMP) -d -M numeric test_rv32im_all.elf > test_rv32im_all.dis

check:
	python run_tests.py all

clean:
	rm -f *.elf *.dis *.bin *.hex *.wdb *.log *.jou
