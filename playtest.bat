@echo off
setlocal
rem ===============================================================
rem  Life / Fusheng - PLAYTEST launcher (separate save dir)
rem
rem  Mirrors the project into playtest_build\, renames config/name
rem  to "LifePlaytest", so Godot writes to:
rem    %APPDATA%\Godot\app_userdata\LifePlaytest
rem  Your normal saves (%APPDATA%\Godot\app_userdata\Fusheng)
rem  are never touched.
rem
rem  ASCII-only on purpose: cmd.exe codepage safety.
rem ===============================================================
set "ROOT=%~dp0"
set "BUILD=%ROOT%playtest_build"

set "GODOT="
if defined GODOT_BIN if exist "%GODOT_BIN%" set "GODOT=%GODOT_BIN%"
if not defined GODOT if exist "D:\Developer\Godot\4.7.2-stable\Godot_v4.7.2-stable_win64.exe" set "GODOT=D:\Developer\Godot\4.7.2-stable\Godot_v4.7.2-stable_win64.exe"
if not defined GODOT if exist "%ROOT%Godot_v4.7.2-stable_win64.exe" set "GODOT=%ROOT%Godot_v4.7.2-stable_win64.exe"

if not defined GODOT (
  echo [ERROR] Godot 4.x executable not found. See play.bat for options.
  pause
  exit /b 1
)

echo [playtest] syncing project to playtest_build ...
robocopy "%ROOT%." "%BUILD%" /MIR /XD .git .github verify-artifacts playtest_build /NFL /NDL /NJH /NJS /NP >nul
if errorlevel 8 (
  echo [ERROR] robocopy failed. Is the game already running?
  pause
  exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -Command "$p='%BUILD%\project.godot'; $q=[char]34; $t=[IO.File]::ReadAllText($p,[Text.UTF8Encoding]::new($false)); $t=[regex]::Replace($t,'config/name=.*',('config/name='+$q+'LifePlaytest'+$q)); [IO.File]::WriteAllText($p,$t,[Text.UTF8Encoding]::new($false))"
if errorlevel 1 (
  echo [ERROR] could not set playtest project name.
  pause
  exit /b 1
)

echo [playtest] build  : %BUILD%
echo [playtest] saves  : %%APPDATA%%\Godot\app_userdata\LifePlaytest
echo [playtest] godot  : %GODOT%
echo.
start "" "%GODOT%" --path "%BUILD%"

endlocal
