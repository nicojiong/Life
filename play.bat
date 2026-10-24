@echo off
setlocal
set "GODOT=D:\Developer\Godot\4.7.2-stable\Godot_v4.7.2-stable_win64.exe"
if not exist "%GODOT%" (
  echo [ERROR] Godot not found at:
  echo   %GODOT%
  echo Edit play.bat and set GODOT to your Godot 4 executable.
  pause
  exit /b 1
)
start "" "%GODOT%" --path "%~dp0."
