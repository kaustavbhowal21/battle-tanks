@echo off
echo =========================================================================
echo   Battle Tanks: Running All VGA Hardware Verification Tests
echo =========================================================================

python testing\run_all_vga_tests.py
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] One or more VGA testbenches failed.
    exit /b %ERRORLEVEL%
)

echo [SUCCESS] All VGA hardware tests passed!
