@echo off
echo =========================================================================
echo   Battle Tanks: Running All Game Engine Hardware Verification Tests
echo =========================================================================

python testing\run_all_game_engine_tests.py
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] One or more game engine testbenches failed.
    exit /b %ERRORLEVEL%
)

echo [SUCCESS] All Game Engine hardware tests passed!
