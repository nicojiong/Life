@echo off
setlocal
rem ===============================================================
rem  Life / Fusheng - normal game launcher
rem  Uses the project save dir: %APPDATA%\Godot\app_userdata\Fusheng
rem  (this file is ASCII-only on purpose: cmd.exe codepage safety)
rem ===============================================================
set "GODOT="

if defined GODOT_BIN if exist "%GODOT_BIN%" set "GODOT=%GODOT_BIN%"

if not defined GODOT if exist "D:\Developer\Godot\4.7.2-stable\Godot_v4.7.2-stable_win64.exe" set "GODOT=D:\Developer\Godot\4.7.2-stable\Godot_v4.7.2-stable_win64.exe"
if not defined GODOT if exist "%~dp0Godot_v4.7.2-stable_win64.exe" set "GODOT=%~dp0Godot_v4.7.2-stable_win64.exe"
if not defined GODOT if exist "%~dp0godot.exe" set "GODOT=%~dp0godot.exe"

if not defined GODOT (
  echo [ERROR] Godot 4.x executable not found.
  echo.
  echo   Option 1: set environment variable GODOT_BIN to the Godot exe
  echo   Option 2: copy Godot_v4.7.2-stable_win64.exe next to this file
  echo   Option 3: edit the GODOT line in play.bat
  echo.
  pause
  exit /b 1
)

echo [play] Godot : %GODOT%
echo [play] Project: %~dp0
echo [play] Saves  : %%APPDATA%%\Godot\app_userdata\Fusheng
echo.
start "" "%GODOT%" --path "%~dp0."
