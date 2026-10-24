#Requires -Version 5.1
<#
.SYNOPSIS
  跨进程续跑验收：多个场景，各跑三个独立 Godot 进程并比对状态。

.DESCRIPTION
  A：固定起点跑 N 步，正常存档，导出检查点，退出。
  B：新进程读档（不带 --fresh），立即导出加载状态，再跑 M 步，导出终态。
  C：另一套干净目录，从同样起点连续跑 N+M 步。

  每个场景比较 A/B0 与 B1/C，并检查业务不变量。
  另做磁盘产物验证：未改动文件必须零差异；改事实/随机流/人物或删字段必须报错并给出字段路径。
#>
param(
  [Parameter(Mandatory = $true)][string]$GodotPath,
  [string]$Seed = "20261024",
  [int]$StepsA = 3,
  [int]$StepsB = 6,
  [string]$ArtifactDir = "verify-artifacts/continuity",
  [switch]$KeepTemp
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$runId = [guid]::NewGuid().ToString("N").Substring(0, 8)
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) "life-cont-$runId"
if ([System.IO.Path]::IsPathRooted($ArtifactDir)) {
  $artifacts = $ArtifactDir
} else {
  $artifacts = Join-Path $root $ArtifactDir
}

function Write-Step([string]$msg) { Write-Host "[cont] $msg" }

function Invoke-Godot {
  param([string]$Project, [string[]]$GodotArgs, [string]$LogPath, [int]$TimeoutSeconds = 240)
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
  $output | Set-Content -Path $LogPath -Encoding utf8
  if ($state -ne "Completed") { return 124 }
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
    $acc = @()
    foreach ($x in $Value) { $acc += ,(ConvertTo-Canon $x) }
    return ,$acc
  }
  if ($Value -is [System.Management.Automation.PSCustomObject]) {
    $h = [ordered]@{}
    foreach ($p in $Value.PSObject.Properties) { $h[$p.Name] = ConvertTo-Canon $p.Value }
    return $h
  }
  return $Value
}

function Compare-Snapshot {
  param($Left, $Right, [string]$Label, [int]$MaxDiffs = 15)
  $diffs = New-Object System.Collections.Generic.List[string]
  $queue = New-Object System.Collections.Generic.Queue[object]
  $queue.Enqueue(@{ a = $Left; b = $Right; path = $Label })
  while ($queue.Count -gt 0 -and $diffs.Count -lt $MaxDiffs) {
    $item = $queue.Dequeue()
    $a = ConvertTo-Canon $item.a
    $b = ConvertTo-Canon $item.b
    $path = $item.path
    if ($a -is [System.Collections.IDictionary] -and $b -is [System.Collections.IDictionary]) {
      $keys = @()
      foreach ($k in $a.Keys) { $keys += [string]$k }
      foreach ($k in $b.Keys) { if (-not ($keys -contains [string]$k)) { $keys += [string]$k } }
      foreach ($k in $keys) {
        if (-not $a.Contains($k)) { $diffs.Add("$path.$k = <缺失于左侧>") ; continue }
        if (-not $b.Contains($k)) { $diffs.Add("$path.$k = <缺失于右侧>") ; continue }
        $queue.Enqueue(@{ a = $a[$k]; b = $b[$k]; path = "$path.$k" })
      }
      continue
    }
    if ($a -is [System.Collections.IEnumerable] -and -not ($a -is [string]) -and $b -is [System.Collections.IEnumerable] -and -not ($b -is [string])) {
      $la = @($a); $lb = @($b)
      if ($la.Count -ne $lb.Count) { $diffs.Add("$path : 长度 $($la.Count) vs $($lb.Count)") ; continue }
      for ($i = 0; $i -lt $la.Count; $i++) {
        $queue.Enqueue(@{ a = $la[$i]; b = $lb[$i]; path = "$path[$i]" })
      }
      continue
    }
    if ("$a" -ne "$b") { $diffs.Add("$path : '$a' vs '$b'") }
  }
  return @($diffs.ToArray())
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
  New-Item -ItemType Directory -Path $dir -Force | Out-Null
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

$results = New-Object System.Collections.Generic.List[object]
$allFailures = New-Object System.Collections.Generic.List[string]

function Invoke-Scenario {
  param([string]$Name, [int]$N, [int]$M)

  Write-Step "场景 $Name：A 跑 $N 步 / B 续跑 $M 步 / C 连续 $($N + $M) 步"
  $projAB = New-ProjectCopy "$Name-AB-$runId"
  $projC = New-ProjectCopy "$Name-C-$runId"
  $udAB = Get-UserDir "$Name-AB-$runId"
  $udC = Get-UserDir "$Name-C-$runId"
  $dir = Join-Path $artifacts $Name
  New-Item -ItemType Directory -Path $dir -Force | Out-Null
  $common = @("--seed=$Seed", "--scenario=$Name")

  $codeA = Invoke-Godot -Project $projAB -GodotArgs (@("--stage=continuity_a", "--steps=$N", "--out=user://cont_a.json") + $common) -LogPath (Join-Path $dir "log-a.txt")
  if ($codeA -ne 0) { $allFailures.Add("$Name : A 进程退出 $codeA") }
  $codeB = Invoke-Godot -Project $projAB -GodotArgs (@("--stage=continuity_b", "--steps=$M", "--out=user://cont_b0.json", "--out2=user://cont_b1.json", "--scenario=$Name")) -LogPath (Join-Path $dir "log-b.txt")
  if ($codeB -ne 0) { $allFailures.Add("$Name : B 进程退出 $codeB") }
  $codeC = Invoke-Godot -Project $projC -GodotArgs (@("--stage=continuity_c", "--steps=$N", "--steps2=$M", "--out=user://cont_c.json") + $common) -LogPath (Join-Path $dir "log-c.txt")
  if ($codeC -ne 0) { $allFailures.Add("$name : C 进程退出 $codeC") }

  foreach ($f in @("cont_a.json", "cont_b0.json", "cont_b1.json", "fusheng_save_1.json")) {
    if (Test-Path (Join-Path $udAB $f)) { Copy-Item (Join-Path $udAB $f) (Join-Path $dir $f) -Force }
  }
  if (Test-Path (Join-Path $udC "cont_c.json")) { Copy-Item (Join-Path $udC "cont_c.json") (Join-Path $dir "cont_c.json") -Force }

  $a = Read-Snapshot (Join-Path $dir "cont_a.json")
  $b0 = Read-Snapshot (Join-Path $dir "cont_b0.json")
  $b1 = Read-Snapshot (Join-Path $dir "cont_b1.json")
  $c = Read-Snapshot (Join-Path $dir "cont_c.json")

  $d1 = @(Compare-Snapshot -Left $a -Right $b0 -Label "A/B0")
  $d2 = @(Compare-Snapshot -Left $b1 -Right $c -Label "B1/C")

  $biz = @()
  if ($d1.Count -eq 0) { $biz += "A/B0 一致" } else { $biz += "A/B0 差异 $($d1.Count) 处" }
  if ($d2.Count -eq 0) { $biz += "B1/C 一致" } else { $biz += "B1/C 差异 $($d2.Count) 处" }
  foreach ($d in $d1) { $allFailures.Add("$Name A/B0 : $d") }
  foreach ($d in $d2) { $allFailures.Add("$Name B1/C : $d") }

  if ($b0.year -ne $a.year -or $b0.month -ne $a.month) {
    $allFailures.Add("$Name : 读档年月 $($b0.year)/$($b0.month) 与检查点 $($a.year)/$($a.month) 不同")
  }
  if (-not ($b1.year -gt $a.year -or ($b1.year -eq $a.year -and $b1.month -gt $a.month))) {
    $allFailures.Add("$Name : B 续跑后时间未推进")
  }
  if (@($c.facts).Count -le 0) { $allFailures.Add("$Name : C 路径没有事实，场景空转") }

  switch ($Name) {
    "pending" {
      $aQueue = @($a.queue)
      $b0Queue = @($b0.queue)
      if ($b0Queue.Count -ne $aQueue.Count) { $allFailures.Add("pending : 读档后队列条数 $($b0Queue.Count) 与检查点 $($aQueue.Count) 不同") }
      for ($i = 0; $i -lt [Math]::Min($aQueue.Count, $b0Queue.Count); $i++) {
        $sigA = "$([int]$aQueue[$i].sid)|$($aQueue[$i].target)|$([int]$aQueue[$i].due)|$($aQueue[$i].policy)"
        $sigB = "$([int]$b0Queue[$i].sid)|$($b0Queue[$i].target)|$([int]$b0Queue[$i].due)|$($b0Queue[$i].policy)"
        if ($sigA -ne $sigB) { $allFailures.Add("pending : 第 $i 条队列顺序/主体/到期/策略与检查点不同") }
      }
      if ($aQueue.Count -lt 2) { $allFailures.Add("pending : 检查点里没有未到期事件，场景无效") }
      $firedInB = @($b1.facts | Where-Object { "$($_.cause)" -like "pending_*" })
      if ($firedInB.Count -lt 1) { $allFailures.Add("pending : B 续跑后没有触发任何待办事件") }
      $biz += "队列 $($aQueue.Count) 条未到期、顺序/主体/到期一致；B 触发 $($firedInB.Count) 条"
    }
    "death" {
      if (-not $b1.actors.child.dead) { $allFailures.Add("death : B 续跑后孩子没有判死") }
      $rewardFacts = @($b1.facts | Where-Object { "$($_.cause)" -eq "death_after" })
      if ($rewardFacts.Count -ne 0) { $allFailures.Add("death : 致死后的奖励仍被执行（$($rewardFacts.Count) 条）") }
      $hitFacts = @($b1.facts | Where-Object { "$($_.cause)" -eq "death_hit" })
      if ($hitFacts.Count -ne 1) { $allFailures.Add("death : 致死事件应恰好记 1 条，实际 $($hitFacts.Count)") }
      $expectMoney = [double]$a.money - 700.0
      if ([Math]::Abs([double]$b1.money - $expectMoney) -gt 1e-9) {
        $allFailures.Add("death : 资金应为 $expectMoney（起点减旱灾 700），实际 $($b1.money)")
      }
      $biz += "孩子已死；奖励未执行；致死事件 1 条；资金 $($a.money)->$($b1.money)（应为 -700）"
    }
    "frac" {
      if ([Math]::Abs([double]$b0.month_frac - [double]$a.month_frac) -gt 1e-9) {
        $allFailures.Add("frac : 读档后 month_frac $($b0.month_frac) 与检查点 $($a.month_frac) 不同")
      }
      if ([double]$a.month_frac -le 0.0) { $allFailures.Add("frac : 检查点 month_frac 为 0，场景无效") }
      if ([int]$b0.frac_probe -ne [int]$a.frac_probe) { $allFailures.Add("frac : frac_probe 恢复后变化") }
      $biz += "month_frac $($a.month_frac)->$($b0.month_frac)->$($b1.month_frac)；frac_probe=$($b0.frac_probe)"
    }
    default {
      $biz += "事实 $($a.facts.Count) -> $($b1.facts.Count)"
    }
  }

  $results.Add([pscustomobject]@{
    scenario = $Name
    exitA = $codeA; exitB = $codeB; exitC = $codeC
    diffAB = $d1.Count; diffBC = $d2.Count
    invariants = ($biz -join "；")
    dir = $dir
  })
}

# ---------------------------------------------------------------- 四个场景

Invoke-Scenario -Name "plain" -N $StepsA -M $StepsB
Invoke-Scenario -Name "pending" -N 3 -M 6
Invoke-Scenario -Name "death" -N 1 -M 4
Invoke-Scenario -Name "frac" -N 2 -M 4

# ---------------------------------------------------------------- 磁盘产物验证

Write-Step "磁盘产物验证：同一读取与比较入口"
$diskDir = Join-Path $artifacts "disk-check"
New-Item -ItemType Directory -Path $diskDir -Force | Out-Null
Copy-Item (Join-Path $artifacts "plain/cont_a.json") (Join-Path $diskDir "good_a.json") -Force
Copy-Item (Join-Path $artifacts "plain/cont_b0.json") (Join-Path $diskDir "good_b0.json") -Force

$diskReport = New-Object System.Collections.Generic.List[string]
$goodA = Read-Snapshot (Join-Path $diskDir "good_a.json")
$goodB = Read-Snapshot (Join-Path $diskDir "good_b0.json")
$dGood = @(Compare-Snapshot -Left $goodA -Right $goodB -Label "DISK")
if ($dGood.Count -ne 0) {
  $allFailures.Add("disk : 未改动文件比较不为零差异（$($dGood.Count)）")
  $diskReport.Add("未改动：错误地出现 $($dGood.Count) 处差异")
} else {
  $diskReport.Add("未改动：0 处差异（通过）")
}

function Test-DiskMutation {
  param([string]$name, [scriptblock]$mutate, [string]$expectPathFragment)
  $file = Join-Path $diskDir "mut_$name.json"
  $json = Get-Content (Join-Path $diskDir "good_a.json") -Raw -Encoding utf8 | ConvertFrom-Json
  $mutated = $mutate.Invoke($json)
  $mutated | ConvertTo-Json -Depth 40 | Set-Content $file -Encoding utf8
  $m = Read-Snapshot $file
  $d = @(Compare-Snapshot -Left $m -Right $goodB -Label "MUT")
  if ($d.Count -eq 0) {
    $allFailures.Add("disk : 修改 $name 后比较器没有报错")
    $diskReport.Add("$name：未检出（失败）")
    return
  }
  $hit = $false
  foreach ($line in $d) { if (("$line").Contains($expectPathFragment)) { $hit = $true } }
  if (-not $hit) { $allFailures.Add("disk : 修改 $name 的报错路径不含 $expectPathFragment，实际 $($d[0])") }
  $diskReport.Add("$name：检出 $($d.Count) 处，首条：$($d[0])")
}

Test-DiskMutation -name "fact" -mutate {
  param($s) $s.facts[0].kind = "tampered"; return $s
} -expectPathFragment "facts[0].kind"

Test-DiskMutation -name "rng" -mutate {
  param($s) $s.rng.actor = "0"; return $s
} -expectPathFragment "rng.actor"

Test-DiskMutation -name "actor" -mutate {
  param($s) $s.actors.child.health = 1.0; return $s
} -expectPathFragment "actors.child.health"

Test-DiskMutation -name "missing" -mutate {
  param($s) $s.PSObject.Properties.Remove("queue"); return $s
} -expectPathFragment "queue"

$restored = Read-Snapshot (Join-Path $diskDir "good_a.json")
$dRestore = @(Compare-Snapshot -Left $restored -Right $goodB -Label "RESTORE")
if ($dRestore.Count -ne 0) {
  $allFailures.Add("disk : 恢复正确文件后仍有差异 $($dRestore.Count)")
  $diskReport.Add("恢复：仍有 $($dRestore.Count) 处差异（失败）")
} else {
  $diskReport.Add("恢复：0 处差异（通过）")
}

# ---------------------------------------------------------------- 报告

$report = New-Object System.Collections.Generic.List[string]
$report.Add("seed=$Seed stepsA=$StepsA stepsB=$StepsB run=$runId")
$report.Add("godot=$GodotPath")
$report.Add("")
$report.Add("scenario | exitA | exitB | exitC | A/B0 差异 | B1/C 差异 | 业务不变量 | 产物")
foreach ($r in $results) {
  $report.Add("$($r.scenario) | $($r.exitA) | $($r.exitB) | $($r.exitC) | $($r.diffAB) | $($r.diffBC) | $($r.invariants) | $($r.dir)")
}
$report.Add("")
$report.Add("== 磁盘产物验证 ==")
foreach ($l in $diskReport) { $report.Add("  $l") }
$report.Add("")
if ($allFailures.Count -gt 0) {
  $report.Add("== 失败 ==")
  foreach ($f in $allFailures) { $report.Add("  $f") }
  $allFailures | Set-Content (Join-Path $artifacts "failures.txt") -Encoding utf8
}
$report | Set-Content (Join-Path $artifacts "report.txt") -Encoding utf8
$report | ForEach-Object { Write-Host $_ }

if ($KeepTemp) { Write-Step "保留临时目录 $tempRoot" } else { Remove-Item $tempRoot -Recurse -Force -ErrorAction SilentlyContinue }

if ($allFailures.Count -gt 0) {
  Write-Host "[cont] FAIL" -ForegroundColor Red
  exit 1
}
Write-Step "PASS 四个场景（A/B0 与 B1/C）与磁盘产物验证全部通过"
exit 0
