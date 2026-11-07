@echo off
echo =========================================================================
echo   Battle Tanks: Hardware Cycle and Performance Profiler
echo =========================================================================

python profile_cycles.py
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Profiler execution failed.
    exit /b %ERRORLEVEL%
)
