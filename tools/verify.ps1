#Requires -Version 5.1
<#
.SYNOPSIS
  Life /《浮生》隔离验证入口（M0-02）。

.DESCRIPTION
  把项目复制到临时目录、把 project.godot 的 config/name 改成 LifeVerify-<id>，
  让 user:// 落到独立目录，然后运行 --stage=verify_smoke 的行为断言。
  全程不读写玩家的真实存档目录（app_userdata\浮生）。

  退出码：0 = 全部断言通过；1 = 有断言失败；2 = 环境/启动失败。

.EXAMPLE
  pwsh -File tools/verify.ps1 -GodotPath "D:\Developer\Godot\4.7.2-stable\Godot_v4.7.2-stable_win64_console.exe"
#>
param(
    [string]$GodotPath = $env:LIFE_GODOT,
    [switch]$KeepTemp,
    [int]$TimeoutSeconds = 180,
    [int]$ExpectedAssertions = 72,
    [string]$ArtifactDir = ''
)

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }
$repo = Split-Path -Parent $PSScriptRoot
if (-not (Test-Path (Join-Path $repo 'project.godot'))) {
    Write-Host "[verify] 找不到 project.godot，repo=$repo" -ForegroundColor Red
    exit 2
}

if (-not $GodotPath -or -not (Test-Path $GodotPath)) {
    Write-Host "[verify] 需要 Godot 可执行文件：-GodotPath 或环境变量 LIFE_GODOT" -ForegroundColor Red
    exit 2
}

$runId = [guid]::NewGuid().ToString('N').Substring(0, 8)
$testName = "LifeVerify-$runId"
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) "life-verify-$runId"
$proj = Join-Path $tempRoot 'project'
# 用户数据根：Windows/macOS 是 Godot，Linux 上是小写 godot（Godot 自己的约定）
$isWin = ($env:OS -eq 'Windows_NT')
$isMac = ($PSVersionTable.PSVersion.Major -ge 6 -and $IsMacOS) -or (Test-Path '/Applications')
if ($isWin) {
    $appDataRoot = $env:APPDATA
    $engineDir = 'Godot'
} elseif ($isMac) {
    $appDataRoot = Join-Path $HOME 'Library/Application Support'
    $engineDir = 'Godot'
} else {
    $appDataRoot = Join-Path $HOME '.local/share'
    $engineDir = 'godot'
}
$userBase = Join-Path (Join-Path $appDataRoot $engineDir) 'app_userdata'
$userDir = Join-Path $userBase $testName
$realUserDir = Join-Path $userBase '浮生'

# 产物目录：日志在这里留一份，CI 上传前不会被临时目录清理带走
if (-not $ArtifactDir) {
    $ArtifactDir = Join-Path $repo 'verify-artifacts'
}
New-Item -ItemType Directory -Force -Path $ArtifactDir | Out-Null

Write-Host "[verify] run=$runId godot=$GodotPath"
Write-Host "[verify] 隔离项目=$proj"
Write-Host "[verify] 隔离存档=$userDir"

# 记录真实存档目录状态，结束时确认未被触碰
$realBefore = $null
if (Test-Path $realUserDir) {
    $realBefore = (Get-ChildItem $realUserDir -File -ErrorAction SilentlyContinue |
        Sort-Object Name | ForEach-Object { "$($_.Name):$($_.Length):$($_.LastWriteTimeUtc.Ticks)" }) -join '|'
}

function Fail([string]$msg) {
    Write-Host "[verify] $msg" -ForegroundColor Red
    exit 2
}

try {
    New-Item -ItemType Directory -Force -Path $proj | Out-Null

    # 复制项目（排除版本库、缓存与截图）
    $exclude = @('.git', '.godot', 'docs')
    Get-ChildItem $repo -Force | Where-Object { $exclude -notcontains $_.Name } | ForEach-Object {
        if ($_.PSIsContainer) {
            Copy-Item $_.FullName -Destination $proj -Recurse -Force
        } else {
            Copy-Item $_.FullName -Destination $proj -Force
        }
    }
    # 文档目录只保留必要部分（verify 不需要截图）
    New-Item -ItemType Directory -Force -Path (Join-Path $proj 'docs') | Out-Null

    # 改写项目名，隔离 user://
    $pgPath = Join-Path $proj 'project.godot'
    $pg = Get-Content $pgPath -Raw -Encoding utf8
    $pg2 = [regex]::Replace($pg, 'config/name="[^"]*"', "config/name=`"$testName`"")
    if ($pg2 -eq $pg -and $pg -notmatch 'config/name=') {
        $pg2 = $pg -replace '\[application\]', "[application]`nconfig/name=`"$testName`""
    }
    Set-Content -Path $pgPath -Value $pg2 -Encoding utf8
    # PowerShell 5.1 的 Set-Content -Encoding utf8 会写 BOM，这里改成无 BOM 写回
    $noBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($pgPath, [string]$pg2, $noBom)
    if ((Get-Content $pgPath -Raw -Encoding utf8) -notmatch [regex]::Escape($testName)) {
        Fail "改写 config/name 失败，无法确认隔离"
    }

    $env:LIFE_ALLOW_SAVE_WIPE = '1'
    $log = Join-Path $tempRoot 'run.log'
    # 用后台 Job 跑子进程：PS 5.1 的 Start-Process -PassThru 在重定向输出时拿不到 ExitCode
    $runner = {
        param($exe, $project, $logPath)
        & $exe --headless --path $project -- --stage=verify_smoke --fresh *> $logPath
        return $LASTEXITCODE
    }
    $job = Start-Job -ScriptBlock $runner -ArgumentList $GodotPath, $proj, $log
    if (-not (Wait-Job $job -Timeout $TimeoutSeconds)) {
        Stop-Job $job
        Remove-Job $job -Force
        Write-Host "[verify] 超时 ${TimeoutSeconds}s" -ForegroundColor Red
        Get-Content $log -ErrorAction SilentlyContinue | Select-Object -Last 20
        exit 2
    }
    $exitCode = Receive-Job $job | Select-Object -Last 1
    Remove-Job $job -Force
    if ($null -eq $exitCode) { $exitCode = 1 }

    $out = Get-Content $log -Raw -ErrorAction SilentlyContinue
    $err = Get-Content "$log.err" -Raw -ErrorAction SilentlyContinue
    $out | Write-Host

    # 日志留档：CI 的临时目录随后会被清理，产物必须在这里先落盘
    $outFile = Join-Path $ArtifactDir 'run.log'
    $errFile = Join-Path $ArtifactDir 'run.err.log'
    if ($out) { Set-Content -Path $outFile -Value $out -Encoding utf8 }
    if ($err) { Set-Content -Path $errFile -Value $err -Encoding utf8 }
    Write-Host "[verify] 日志留档：$outFile"

    $pass = ([regex]::Matches($out, '\[VERIFY\] PASS')).Count
    $fail = ([regex]::Matches($out, '\[VERIFY\] FAIL')).Count
    $summary = ($out -split "`n" | Where-Object { $_ -match '\[VERIFY\] SUMMARY' }) -join ''

    Write-Host "[verify] 断言 pass=$pass fail=$fail expected=$ExpectedAssertions exit=$exitCode"
    if ($summary) { Write-Host "[verify] $($summary.Trim())" }

    # 完整执行校验：必须跑完并给出总和，且条数与预期一致
    $incomplete = $false
    if (-not $summary) {
        Write-Host "[verify] FAIL 没有 SUMMARY 行，测试可能中途崩溃" -ForegroundColor Red
        $incomplete = $true
    } elseif ($pass -ne $ExpectedAssertions) {
        Write-Host "[verify] FAIL 断言条数不符：实际 $pass，预期 $ExpectedAssertions" -ForegroundColor Red
        $incomplete = $true
    }

    # 确认隔离生效且真实存档未被触碰
    if (-not (Test-Path $userDir)) {
        Write-Host "[verify] FAIL 隔离存档目录未创建：$userDir" -ForegroundColor Red
        exit 2
    }
    $realAfter = $null
    if (Test-Path $realUserDir) {
        $realAfter = (Get-ChildItem $realUserDir -File -ErrorAction SilentlyContinue |
            Sort-Object Name | ForEach-Object { "$($_.Name):$($_.Length):$($_.LastWriteTimeUtc.Ticks)" }) -join '|'
    }
    if ($realBefore -ne $realAfter) {
        Write-Host "[verify] FAIL 真实存档目录发生变化，隔离失败" -ForegroundColor Red
        exit 2
    }
    Write-Host "[verify] PASS 真实存档目录未被触碰"

    if ($incomplete -or $fail -gt 0 -or $exitCode -ne 0) { exit 1 }
    exit 0
}
finally {
    if (-not $KeepTemp) {
        Remove-Item -Recurse -Force $tempRoot -ErrorAction SilentlyContinue
        Remove-Item -Recurse -Force $userDir -ErrorAction SilentlyContinue
    } else {
        Write-Host "[verify] 保留临时目录：$tempRoot / $userDir"
    }
    Remove-Item Env:\LIFE_ALLOW_SAVE_WIPE -ErrorAction SilentlyContinue
}
