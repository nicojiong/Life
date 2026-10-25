# playtest_check.ps1 - verify the Windows playtest entry actually boots
# Mirrors the project to playtest_build\, renames config/name to LifePlaytest,
# then boots headless for a few frames and fails on SCRIPT ERROR.

param(
    [string]$GodotPath = 'D:\Developer\Godot\4.7.2-stable\Godot_v4.7.2-stable_win64_console.exe',
    [int]$Frames = 180
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$build = Join-Path $root 'playtest_build'
$logDir = Join-Path $root 'verify-artifacts'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$log = Join-Path $logDir 'playtest_boot.log'

Write-Output "[playtest-check] mirror -> $build"
if (Test-Path $build) { Remove-Item -Recurse -Force $build }
$exclude = @('.git', '.github', 'verify-artifacts', 'playtest_build')
$items = Get-ChildItem -LiteralPath $root -Force | Where-Object { $exclude -notcontains $_.Name }
New-Item -ItemType Directory -Force -Path $build | Out-Null
foreach ($it in $items) {
    Copy-Item -LiteralPath $it.FullName -Destination $build -Recurse -Force
}

$proj = Join-Path $build 'project.godot'
$text = [System.IO.File]::ReadAllText($proj, [System.Text.UTF8Encoding]::new($false))
$text = [regex]::Replace($text, 'config/name=.*', 'config/name="LifePlaytest"')
[System.IO.File]::WriteAllText($proj, $text, (New-Object System.Text.UTF8Encoding($false)))
Write-Output '[playtest-check] project name -> LifePlaytest'

if (-not (Test-Path $GodotPath)) { throw "Godot not found: $GodotPath" }
Write-Output "[playtest-check] boot headless $Frames frames"
$proc = Start-Process -FilePath $GodotPath -ArgumentList @('--headless', '--path', $build, '--quit-after', "$Frames") -NoNewWindow -PassThru -RedirectStandardOutput $log -RedirectStandardError "$log.err"
$exited = $proc.WaitForExit(180000)
if (-not $exited) { $proc.Kill(); throw 'boot timed out' }

$out = Get-Content $log -Encoding utf8 -ErrorAction SilentlyContinue
$err = Get-Content "$log.err" -Encoding utf8 -ErrorAction SilentlyContinue
$joined = ($out + $err) -join "`n"

$scriptErrors = @($out | Where-Object { $_ -match 'SCRIPT ERROR' })
$dbLine = @($out | Where-Object { $_ -match '\[DB\]' })
$hasDb = $dbLine.Count -gt 0

if ($scriptErrors.Count -gt 0) {
    Write-Output "[playtest-check] FAIL script_errors=$($scriptErrors.Count)"
    $scriptErrors | Select-Object -First 5 | ForEach-Object { Write-Output "  $_" }
    exit 1
}
if (-not $hasDb) {
    Write-Output '[playtest-check] FAIL no [DB] boot line - scene did not load'
    $out | Select-Object -First 10 | ForEach-Object { Write-Output "  $_" }
    exit 1
}

Write-Output "[playtest-check] PASS boot_ok events_line=$($dbLine[0].Trim())"
Write-Output "[playtest-check] log=$log"
exit 0
