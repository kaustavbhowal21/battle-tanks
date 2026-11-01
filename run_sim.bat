@echo off
echo =========================================================================
echo   Battle Tanks: Full Hardware-Software Simulation Script
echo =========================================================================

echo [1/3] Compiling C game software for RV32IM...
python software\build_and_export.py
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Software compilation failed.
    exit /b %ERRORLEVEL%
)

echo [2/3] Compiling and elaborating SystemVerilog modules...
call D:\2025.2\Vivado\bin\xvlog.bat --sv -i modules\cpu modules\cpu\pipeline.v modules\cpu\memory.v modules\cpu\multiplier_dsp.v modules\cpu\divider_radix2.v modules\cpu\top_rv32m.v modules\game_engine\collision_engine.v modules\game_engine\cooldown_timers.v modules\game_engine\sprite_hud_regfile.v modules\game_engine\input_controller.v modules\game_engine\maze_tile_ram.v modules\game_engine\mmio_interconnect.v modules\vga\vga_timing_gen.v modules\vga\maze_tile_renderer.v modules\vga\sprite_engine.v modules\vga\health_hud.v modules\vga\pixel_priority_mixer.v modules\top_fpga.v modules\sim\tb_game_top.v
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Verilog compilation failed.
    exit /b %ERRORLEVEL%
)

call D:\2025.2\Vivado\bin\xelab.bat -debug typical -top tb_game_top -s tb_game_top_sim
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Elaboration failed.
    exit /b %ERRORLEVEL%
)

echo [3/3] Running simulation in Vivado XSim...
call D:\2025.2\Vivado\bin\xsim.bat tb_game_top_sim -R
echo Simulation finished.
