@echo off
setlocal enabledelayedexpansion
rem ---------------------------------------------------------------
rem  浮生 · 试玩版启动（独立存档目录，不动已有存档）
rem
rem  做法：把工程同步到 playtest_build\，改掉 config/name，
rem  于是 Godot 会写到另一个 user:// 目录：
rem    %APPDATA%\Godot\app_userdata\浮生试玩
rem  原来的 %APPDATA%\Godot\app_userdata\浮生 完全不动。
rem ---------------------------------------------------------------
set "ROOT=%~dp0"
set "BUILD=%ROOT%playtest_build"

set "GODOT="
if exist "%GODOT_BIN%" set "GODOT=%GODOT_BIN%"
if not defined GODOT if exist "D:\Developer\Godot\4.7.2-stable\Godot_v4.7.2-stable_win64.exe" set "GODOT=D:\Developer\Godot\4.7.2-stable\Godot_v4.7.2-stable_win64.exe"

if not defined GODOT (
  echo [ERROR] 没找到 Godot 4.x 可执行文件，请参考 play.bat 里的说明。
  pause
  exit /b 1
)

echo [playtest] 同步工程到试玩目录...
robocopy "%ROOT%." "%BUILD%" /MIR /XD .git .github verify-artifacts playtest_build /NFL /NDL /NJH /NJS /NP >nul
if errorlevel 8 (
  echo [ERROR] 同步失败，检查目录权限。
  pause
  exit /b 1
)

rem 独立存档目录：改名即可
powershell -NoProfile -Command "$p='%BUILD%\project.godot'; $t=[IO.File]::ReadAllText($p,[Text.UTF8Encoding]::new($false)); $t=[regex]::Replace($t,'config/name=\"[^\"]*\"','config/name=\"浮生试玩\"'); [IO.File]::WriteAllText($p,$t,[Text.UTF8Encoding]::new($false))"

echo [playtest] 存档目录: %%APPDATA%%\Godot\app_userdata\浮生试玩
echo [playtest] 启动中...
start "" "%GODOT%" --path "%BUILD%"
