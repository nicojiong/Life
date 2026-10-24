@echo off
setlocal
rem ---------------------------------------------------------------
rem  浮生 · 正常游戏启动（使用项目自带的存档目录）
rem  首次运行：自动检测 Godot 4.x 可执行文件
rem ---------------------------------------------------------------
set "GODOT="

rem 1) 环境变量优先
if exist "%GODOT_BIN%" set "GODOT=%GODOT_BIN%"

rem 2) 本机常见安装位置
if not defined GODOT if exist "D:\Developer\Godot\4.7.2-stable\Godot_v4.7.2-stable_win64.exe" set "GODOT=D:\Developer\Godot\4.7.2-stable\Godot_v4.7.2-stable_win64.exe"

rem 3) 同目录下的绿色版
if not defined GODOT if exist "%~dp0Godot_v4.7.2-stable_win64.exe" set "GODOT=%~dp0Godot_v4.7.2-stable_win64.exe"
if not defined GODOT if exist "%~dp0godot.exe" set "GODOT=%~dp0godot.exe"

if not defined GODOT (
  echo [ERROR] 没找到 Godot 4.x 可执行文件。
  echo.
  echo 请任选一种方式：
  echo   1. 设置环境变量 GODOT_BIN 指向 Godot 的 exe；
  echo   2. 把 Godot_v4.7.2-stable_win64.exe 放到本目录；
  echo   3. 直接编辑 play.bat 里的 GODOT 行。
  echo.
  pause
  exit /b 1
)

echo [play] Godot: %GODOT%
echo [play] 项目:   %~dp0
echo [play] 存档:   %%APPDATA%%\Godot\app_userdata\浮生
echo.
start "" "%GODOT%" --path "%~dp0."
