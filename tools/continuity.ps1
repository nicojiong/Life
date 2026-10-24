#Requires -Version 5.1
<#
.SYNOPSIS
  跨进程续跑验收：三个独立 Godot 进程的状态比对。

.DESCRIPTION
  A：固定起点跑 N 步，正常存档，导出检查点，退出。
  B：新进程读档（不带 --fresh），立即导出加载状态，再跑 M 步，导出终态。
  C：另一套干净目录，从同样起点连续跑 N+M 步。

  比较 A 检查点 vs B 加载即刻；B 终态 vs C 终态。
  另做反向验证：删字段 / 改事实 / 改随机流后比较器必须报错。

.EXAMPLE
  tools/continuity.ps1 -GodotPath "C:\Godot\Godot_v4.7.2-stable_win64_console.exe"
#>
param(
  [Parameter(Mandatory = $true)][string]$GodotPath,
  [string]$Seed = "20261024",
  [int]$StepsA = 6,
  [int]$StepsB = 6,
  [string]$ArtifactDir = "verify-artifacts/continuity",
  [switch]$KeepTemp
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$ErrorActionPreference = "Stop"
$runId = [guid]::NewGuid().ToString("N").Substring(0, 8)
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) "life-cont-$runId"
if ([System.IO.Path]::IsPathRooted($ArtifactDir)) {
  $artifacts = $ArtifactDir
} else {
  $artifacts = Join-Path $root $ArtifactDir
}

function Write-Step([string]$msg) { Write-Host "[cont] $msg" }
try {
  $null = 0
} catch {
}


function Invoke-Godot {
  param([string]$Project, [string[]]$GodotArgs, [string]$LogPath, [int]$TimeoutSeconds = 180)
  $job = Start-Job -ScriptBlock {
    param($exe, $proj, $a)
    $list = @()
    foreach ($x in ($a -split "`n")) { if ($x -ne "") { $list += $x } }
    & $exe --headless --path $proj -- @list 2>&1
    "EXITCODE=$LASTEXITCODE"
  } -ArgumentList $GodotPath, $Project, ($GodotArgs -join "`n")
  $null = Wait-Job $job -Timeout $TimeoutSeconds
  $output = Receive-Job $job
  $state = $job.State
  Remove-Job $job -Force
  if ($state -ne "Completed") { throw "Godot 超时: $Project" }
  $output | Set-Content -Path $LogPath -Encoding utf8
  $code = 0
  foreach ($line in $output) {
    if ($line -match '^EXITCODE=(\d+)$') { $code = [int]$Matches[1] }
  }
  return $code
}

function ConvertTo-Canon {
  param($Value)
  if ($null -eq $Value) { return $null }
  if ($Value -is [bool]) { return $Value }
  if ($Value -is [int] -or $Value -is [long] -or $Value -is [double] -or $Value -is [single] -or $Value -is [decimal]) {
    return [double]$Value
  }
  if ($Value -is [string]) { return $Value }
  if ($Value -is [System.Collections.IDictionary]) {
    $h = [ordered]@{}
    foreach ($k in $Value.Keys) { $h[[string]$k] = ConvertTo-Canon $Value[$k] }
    return $h
  }
  if ($Value -is [System.Collections.IEnumerable]) {
    $a = @()
    foreach ($x in $Value) { $a += ,(ConvertTo-Canon $x) }
    return ,$a
  }
  if ($Value -is [System.Management.Automation.PSCustomObject]) {
    $h = [ordered]@{}
    foreach ($p in $Value.PSObject.Properties) { $h[$p.Name] = ConvertTo-Canon $p.Value }
    return $h
  }
  return $Value
}

function Compare-Snapshot {
  param($Left, $Right, [string]$Label, [int]$MaxDiffs = 12)
  $diffs = New-Object System.Collections.Generic.List[string]
  $script:pending = New-Object System.Collections.Generic.Queue[object]
  $script:pending.Enqueue(@{ a = $Left; b = $Right; path = $Label })
  while ($script:pending.Count -gt 0 -and $diffs.Count -lt $MaxDiffs) {
    $item = $script:pending.Dequeue()
    $a = ConvertTo-Canon $item.a
    $b = ConvertTo-Canon $item.b
    $path = $item.path
    if ($a -is [System.Collections.IDictionary] -and $b -is [System.Collections.IDictionary]) {
      $keys = @()
      foreach ($k in $a.Keys) { $keys += [string]$k }
      foreach ($k in $b.Keys) { if (-not ($keys -contains [string]$k)) { $keys += [string]$k } }
      foreach ($k in $keys) {
        $hasA = $a.Contains([string]$k)
        $hasB = $b.Contains([string]$k)
        if (-not $hasA) { $diffs.Add("$path.$k : 仅右侧存在") ; continue }
        if (-not $hasB) { $diffs.Add("$path.$k : 仅左侧存在") ; continue }
        $script:pending.Enqueue(@{ a = $a[[string]$k]; b = $b[[string]$k]; path = "$path.$k" })
      }
      continue
    }
    if ($a -is [System.Collections.IEnumerable] -and -not ($a -is [string]) -and $b -is [System.Collections.IEnumerable] -and -not ($b -is [string])) {
      $la = @($a); $lb = @($b)
      if ($la.Count -ne $lb.Count) { $diffs.Add("$path : 长度 $($la.Count) vs $($lb.Count)") ; continue }
      for ($i = 0; $i -lt $la.Count; $i++) {
        $script:pending.Enqueue(@{ a = $la[$i]; b = $lb[$i]; path = "$path[$i]" })
      }
      continue
    }
    if ("$a" -ne "$b") { $diffs.Add("$path : '$a' vs '$b'") }
  }
  return $diffs
}

function Read-Snapshot([string]$path) {
  if (-not (Test-Path $path)) { throw "缺少快照: $path" }
  return (Get-Content $path -Raw -Encoding utf8 | ConvertFrom-Json)
}

# ---------------------------------------------------------------- 准备

if (Test-Path $tempRoot) { Remove-Item $tempRoot -Recurse -Force }
New-Item -ItemType Directory -Path $tempRoot | Out-Null
New-Item -ItemType Directory -Path $artifacts -Force | Out-Null

function New-ProjectCopy([string]$name) {
  $dir = Join-Path $tempRoot $name
  New-Item -ItemType Directory -Path $dir | Out-Null
  $proj = Join-Path $dir "project"
  New-Item -ItemType Directory -Path $proj -Force | Out-Null
  $skip = @('.git', '.github', 'verify-artifacts')
  foreach ($item in Get-ChildItem -Path $root -Force) {
    if ($skip -contains $item.Name) { continue }
    Copy-Item -Path $item.FullName -Destination $proj -Recurse -Force
  }
  $cfg = Join-Path $proj "project.godot"
  $text = [System.IO.File]::ReadAllText($cfg, [System.Text.UTF8Encoding]::new($false))
  $text = [regex]::Replace($text, 'config/name="[^"]*"', ('config/name="LifeCont-' + $name + '"'))
  [System.IO.File]::WriteAllText($cfg, $text, (New-Object System.Text.UTF8Encoding($false)))
  return $proj
}

function Get-UserDir([string]$name) {
  if ($IsLinux -or $IsMacOS) { return (Join-Path $HOME ".local/share/godot/app_userdata/LifeCont-$name") }
  return (Join-Path $env:APPDATA "Godot\app_userdata\LifeCont-$name")
}

$projAB = New-ProjectCopy "AB-$runId"
$projC = New-ProjectCopy "C-$runId"
$udAB = Get-UserDir "AB-$runId"
$udC = Get-UserDir "C-$runId"
Write-Step "临时目录 $tempRoot"
Write-Step "A/B 项目 $projAB"
Write-Step "C 项目 $projC"

# ---------------------------------------------------------------- 三个进程

$common = @("--seed=$Seed")
Write-Step "A：跑 $StepsA 步并存档"
$codeA = Invoke-Godot -Project $projAB -GodotArgs (@("--stage=continuity_a", "--steps=$StepsA", "--out=user://cont_a.json") + $common) -LogPath (Join-Path $artifacts "log-a.txt")
if ($codeA -ne 0) { Write-Host "[cont] A 进程失败 exit=$codeA" -ForegroundColor Red; exit 1 }

Write-Step "B：读档并续跑 $StepsB 步"
$codeB = Invoke-Godot -Project $projAB -GodotArgs (@("--stage=continuity_b", "--steps=$StepsB", "--out=user://cont_b0.json", "--out2=user://cont_b1.json")) -LogPath (Join-Path $artifacts "log-b.txt")
if ($codeB -ne 0) { Write-Host "[cont] B 进程失败 exit=$codeB" -ForegroundColor Red; exit 1 }

Write-Step "C：连续跑 $($StepsA + $StepsB) 步"
$codeC = Invoke-Godot -Project $projC -GodotArgs (@("--stage=continuity_c", "--steps=$StepsA", "--steps2=$StepsB", "--out=user://cont_c.json") + $common) -LogPath (Join-Path $artifacts "log-c.txt")
if ($codeC -ne 0) { Write-Host "[cont] C 进程失败 exit=$codeC" -ForegroundColor Red; exit 1 }

# ---------------------------------------------------------------- 收产物

foreach ($f in @("cont_a.json", "cont_b0.json", "cont_b1.json", "fusheng_save_1.json")) {
  Copy-Item (Join-Path $udAB $f) (Join-Path $artifacts $f) -Force
}
Copy-Item (Join-Path $udC "cont_c.json") (Join-Path $artifacts "cont_c.json") -Force
Copy-Item (Join-Path $udAB "fusheng_save_1.json") (Join-Path $artifacts "save_ab.json") -Force -ErrorAction SilentlyContinue

$a = Read-Snapshot (Join-Path $artifacts "cont_a.json")
$b0 = Read-Snapshot (Join-Path $artifacts "cont_b0.json")
$b1 = Read-Snapshot (Join-Path $artifacts "cont_b1.json")
$c = Read-Snapshot (Join-Path $artifacts "cont_c.json")

# ---------------------------------------------------------------- 比较

$failures = New-Object System.Collections.Generic.List[string]
$report = New-Object System.Collections.Generic.List[string]
$report.Add("seed=$Seed stepsA=$StepsA stepsB=$StepsB run=$runId")
$report.Add("godot=$GodotPath")
$report.Add("A 快照 year=$($a.year) month=$($a.month) frac=$($a.month_frac) facts=$($a.facts.Count)")
$report.Add("B0 快照 year=$($b0.year) month=$($b0.month) frac=$($b0.month_frac) facts=$($b0.facts.Count)")
$report.Add("B1 快照 year=$($b1.year) month=$($b1.month) frac=$($b1.month_frac) facts=$($b1.facts.Count)")
$report.Add("C  快照 year=$($c.year) month=$($c.month) frac=$($c.month_frac) facts=$($c.facts.Count)")

$d1 = Compare-Snapshot -Left $a -Right $b0 -Label "A/B0"
if ($d1.Count -gt 0) {
  $failures.Add("A 检查点与 B 加载状态不一致：" + ($d1 -join " | "))
  $report.Add("== A vs B0 差异 ==")
  foreach ($d in $d1) { $report.Add("  $d") }
} else {
  $report.Add("A vs B0：一致")
}

$d2 = Compare-Snapshot -Left $b1 -Right $c -Label "B1/C"
if ($d2.Count -gt 0) {
  $failures.Add("B 续跑终态与 C 连续运行终态不一致：" + ($d2 -join " | "))
  $report.Add("== B1 vs C 差异 ==")
  foreach ($d in $d2) { $report.Add("  $d") }
} else {
  $report.Add("B1 vs C：一致")
}

# 业务不变量：不能只验证两边相等
if ([double]$a.month_frac -eq 0.0 -and [double]$c.month_frac -eq 0.0) {
  # 允许为 0，但必须显式记录：首轮场景的保存点不在月中
  $report.Add("注意：本轮保存点 month_frac=0（非零月内进度用例另列）")
}
if (-not ($b1.year -gt $a.year -or ($b1.year -eq $a.year -and $b1.month -gt $a.month))) {
  $failures.Add("B 续跑后时间没有推进：A y$($a.year)m$($a.month) -> B1 y$($b1.year)m$($b1.month)")
}
if ($b0.year -ne $a.year -or $b0.month -ne $a.month) {
  $failures.Add("读档后年月与检查点不同：$($a.year)/$($a.month) vs $($b0.year)/$($b0.month)")
}
if ([int]$c.fact_seq -le 0 -or @($c.facts).Count -le 0) {
  $failures.Add("C 路径没有产生任何事实，场景可能空转")
}
if ([int]$b1.fact_seq -lt [int]$a.fact_seq) {
  $failures.Add("B 续跑后事实序号回退：$($a.fact_seq) -> $($b1.fact_seq)")
}

# ---------------------------------------------------------------- 反向验证

function Test-ComparatorCatches {
  param([string]$name, [scriptblock]$mutate)
  $copy = (Get-Content (Join-Path $artifacts "cont_a.json") -Raw -Encoding utf8 | ConvertFrom-Json)
  $mutated = $mutate.Invoke($copy)
  $d = Compare-Snapshot -Left $mutated -Right $b0 -Label "MUT"
  if ($d.Count -eq 0) {
    $failures.Add("反向验证失败：$name 改动后比较器没有报差异")
    $report.Add("反向验证 $name：未检出（错误）")
  } else {
    $report.Add("反向验证 $name：检出 $($d.Count) 处，例如 $($d[0])")
  }
}

Test-ComparatorCatches -name "删除事实" -mutate { param($s) $s.facts = @(); return $s }
Test-ComparatorCatches -name "修改随机流" -mutate { param($s) $s.rng.actor = "0"; return $s }
Test-ComparatorCatches -name "修改人物健康" -mutate { param($s) $s.actors.child.health = 1.0; return $s }
Test-ComparatorCatches -name "删除月内进度" -mutate { param($s) $s.PSObject.Properties.Remove("month_frac"); return $s }

# ---------------------------------------------------------------- 结果

$report | Set-Content (Join-Path $artifacts "report.txt") -Encoding utf8

if ($KeepTemp) { Write-Step "保留临时目录 $tempRoot" } else { Remove-Item $tempRoot -Recurse -Force -ErrorAction SilentlyContinue }

if ($failures.Count -gt 0) {
  $failures | Set-Content (Join-Path $artifacts "failures.txt") -Encoding utf8
  Write-Host "[cont] FAIL" -ForegroundColor Red
  foreach ($f in $failures) { Write-Host "  $f" -ForegroundColor Red }
  exit 1
}
Write-Step "PASS 三进程续跑一致（A/B0 与 B1/C），反向验证全部检出"
exit 0
