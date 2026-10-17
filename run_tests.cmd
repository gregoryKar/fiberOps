@echo off
rem Runs the headless test suite. Optional first argument filters tests by name.
set GODOT=C:\Users\Karianakis\Programming\Godot_4_7\Godot_v4.7.2-stable_mono_win64\Godot_v4.7.2-stable_mono_win64_console.exe
"%GODOT%" --headless --path "%~dp0." -s res://tests/run_tests.gd -- %*
