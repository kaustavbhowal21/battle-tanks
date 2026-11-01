@echo off
echo =========================================================================
echo   Compiling RV32IM C Game Program with riscv-none-elf-gcc
echo =========================================================================

python build_and_export.py
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Build failed.
    exit /b %ERRORLEVEL%
)

echo [SUCCESS] imem.hex and dmem.hex generated successfully!
