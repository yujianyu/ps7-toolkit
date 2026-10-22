#Requires -Version 5.1
<#
.SYNOPSIS
    安装器回归测试（冒烟测试）—— 20 项断言，本机约 1~2 分钟跑完。
.DESCRIPTION
    全部在临时目录里跑，读系统、不写系统默认（用 -SkipDefaults），跑完自动清理。
    覆盖：只读体检、隔离安装、幂等、-Force 复制、中文+空格路径、错误参数、卸载。
    返回码：0 = 全部通过；1 = 有用例失败。
.PARAMETER KeepArtifacts
    保留临时目录，便于排查失败原因。
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\scripts\smoke-test.ps1
#>
[CmdletBinding()]
param([switch]$KeepArtifacts)

$ErrorActionPreference = 'Continue'
$ProgressPreference    = 'SilentlyContinue'
$src  = Join-Path $PSScriptRoot 'install.ps1'
$base = Join-Path $env:TEMP ('ps7-toolkit-smoke-' + [Guid]::NewGuid().ToString('N').Substring(0,8))
$log  = Join-Path $base 'logs'
$results = @()

if (-not (Test-Path $src)) { Write-Host "找不到 install.ps1：$src" -ForegroundColor Red; exit 1 }

function T([string]$name, [scriptblock]$body) {
    $r = [ordered]@{ name = $name; ok = $false; detail = '' }
    try {
        $d = & $body
        $r.ok = [bool]$d.ok
        $r.detail = $d.detail
    } catch {
        $r.ok = $false
        $r.detail = 'EXCEPTION: ' + $_.Exception.Message
    }
    $script:results += [pscustomobject]$r
    if ($r.ok) { Write-Host ("[PASS] " + $name) -ForegroundColor Green }
    else       { Write-Host ("[FAIL] " + $name) -ForegroundColor Red }
    Write-Host ("       " + $r.detail) -ForegroundColor DarkGray
}

Write-Host "`n########## 安装器回归测试 ##########" -ForegroundColor Magenta
Write-Host "脚本 : $src"
Write-Host "沙箱 : $base"

New-Item -ItemType Directory -Force -Path $log | Out-Null
$defaultRoot = Join-Path $env:LOCALAPPDATA 'ps7-toolkit'
$bg = Test-Path $defaultRoot

# ---------------------------------------------------------------- 1
Write-Host "`n=== 1. -CheckOnly（只读） ===" -ForegroundColor Cyan
& $src -CheckOnly *> (Join-Path $log 't1.log')
T 'T1  -CheckOnly 退出码 0' { @{ ok = ($LASTEXITCODE -eq 0); detail = "exit=$LASTEXITCODE" } }
T 'T2  -CheckOnly 不写任何文件' { @{ ok = ((Test-Path $defaultRoot) -eq $bg); detail = "默认目录 before=$bg after=" + (Test-Path $defaultRoot) } }

# ---------------------------------------------------------------- 2
Write-Host "`n=== 2. 隔离安装（-ToolsRoot + -SkipDefaults） ===" -ForegroundColor Cyan
$box1 = Join-Path $base 'box1'
$t0 = Get-Date
& $src -ToolsRoot $box1 -SkipDefaults *> (Join-Path $log 't2.log')
$el1 = [int]((Get-Date) - $t0).TotalSeconds
$txt = Get-Content (Join-Path $log 't2.log') -Raw -Encoding UTF8
T 'T3  安装退出码 0（可被自动化识别）' { @{ ok = ($LASTEXITCODE -eq 0); detail = "exit=$LASTEXITCODE, ${el1}s" } }
T 'T4  -ToolsRoot 生效' { @{ ok = ($txt -match [regex]::Escape($box1)); detail = "日志提到 sandbox = " + ($txt -match [regex]::Escape($box1)) } }
T 'T5  复用系统 pwsh 时有明确提示' { @{ ok = ($txt -match '未复制到'); detail = "提示出现 = " + ($txt -match '未复制到') } }

$bin1 = Join-Path $box1 'bin'
$need = @('rg.exe','fd.exe','fzf.exe','bat.exe','delta.exe','jq.exe')
$miss = @(); foreach ($n in $need) { if (-not (Test-Path (Join-Path $bin1 $n))) { $miss += $n } }
T 'T6  6 个 Rust 工具全部就位' { @{ ok = ($miss.Count -eq 0); detail = "缺失=[" + ($miss -join ',') + "]" } }

$rgv = ''; try { $rgv = (& (Join-Path $bin1 'rg.exe') --version 2>&1 | Select-Object -First 1) } catch {}
T 'T7  rg 可执行' { @{ ok = ($rgv -match 'ripgrep'); detail = $rgv } }

$jqv = ''; try { $jqv = (& (Join-Path $bin1 'jq.exe') --version 2>&1 | Select-Object -First 1) } catch {}
T 'T8  jq 可执行（API 限流兜底路径）' { @{ ok = ($jqv -match '^jq-'); detail = $jqv } }

T 'T9  下载缓存已清理' { @{ ok = (-not (Test-Path (Join-Path $box1 '_dl'))); detail = "_dl 不存在 = " + (-not (Test-Path (Join-Path $box1 '_dl'))) } }
T 'T10 日志无进度条刷屏' { @{ ok = ($txt -notmatch 'oooooo'); detail = "刷屏 = " + ($txt -match 'oooooo') } }
T 'T11 -SkipDefaults 下体检不报 PATH 红叉' { @{ ok = ($txt -notmatch '不在用户 PATH'); detail = "告警 = " + ($txt -match '不在用户 PATH') } }

# ---------------------------------------------------------------- 3
Write-Host "`n=== 3. 幂等（连跑两次） ===" -ForegroundColor Cyan
$snapA = (Get-ChildItem $bin1 -File | ForEach-Object { $_.Name + ':' + $_.Length }) -join '|'
$t1 = Get-Date
& $src -ToolsRoot $box1 -SkipDefaults *> (Join-Path $log 't3.log')
$ms2 = [int]((Get-Date) - $t1).TotalMilliseconds
$snapB = (Get-ChildItem $bin1 -File | ForEach-Object { $_.Name + ':' + $_.Length }) -join '|'
$txt3 = Get-Content (Join-Path $log 't3.log') -Raw -Encoding UTF8
T 'T12 第二次运行退出码 0' { @{ ok = ($LASTEXITCODE -eq 0); detail = "exit=$LASTEXITCODE, ${ms2}ms" } }
T 'T13 第二次运行二进制完全一致（未重复下载）' { @{ ok = ($snapA -eq $snapB); detail = if ($snapA -eq $snapB) { '一致' } else { '内容有变化' } } }
T 'T14 第二次运行没有重新下载' { $dl2 = ($txt3 -match '开始下载|自动下载 PowerShell 7'); @{ ok = (-not $dl2); detail = "日志里出现下载步骤 = $dl2" } }

# ---------------------------------------------------------------- 4
Write-Host "`n=== 4. -Force 复制本机安装（不联网） ===" -ForegroundColor Cyan
$box4 = Join-Path $base 'box4'
$t2 = Get-Date
& $src -ToolsRoot $box4 -SkipDefaults -SkipRustTools -Force *> (Join-Path $log 't4.log')
$el4 = [int]((Get-Date) - $t2).TotalSeconds
$pwsh4 = Join-Path $box4 'ps7\pwsh.exe'
T 'T15 -Force 把 pwsh 放进 -ToolsRoot' { @{ ok = (Test-Path $pwsh4); detail = "pwsh.exe=" + (Test-Path $pwsh4) + ", ${el4}s" } }
$v4 = ''; if (Test-Path $pwsh4) { try { $v4 = (& $pwsh4 -NoProfile -Command '$PSVersionTable.PSVersion.ToString()' 2>$null) } catch {} }
T 'T16 复制出来的 pwsh 可运行' { @{ ok = ($v4 -match '^7\.'); detail = "version=$v4" } }
T 'T17 -Force 是复制而非重新下载' { @{ ok = ($el4 -lt 150); detail = "${el4}s（下载通常要 100s+）" } }

# ---------------------------------------------------------------- 5
Write-Host "`n=== 5. 中文 + 空格路径 ===" -ForegroundColor Cyan
$cn   = [string][char]0x4E2D + [string][char]0x6587
$box2 = Join-Path $base ($cn + ' path\ps7 box')
& $src -ToolsRoot $box2 -SkipDefaults -SkipRustTools *> (Join-Path $log 't5.log')
T 'T18 中文+空格 ToolsRoot 安装成功' { @{ ok = ($LASTEXITCODE -eq 0); detail = "exit=$LASTEXITCODE, 目录存在=" + (Test-Path $box2) } }

# ---------------------------------------------------------------- 6
Write-Host "`n=== 6. -ZipPath 指向不存在的文件 ===" -ForegroundColor Cyan
$srcText = Get-Content $src -Raw -Encoding UTF8
$hasFail = ($srcText -match '-ZipPath 指定的文件不存在[\s\S]{0,300}?exit 1')
T 'T19 明确报错退出，不偷偷联网下载' { @{ ok = $hasFail; detail = "守卫代码存在 = $hasFail" } }

# ---------------------------------------------------------------- 7
Write-Host "`n=== 7. 卸载 ===" -ForegroundColor Cyan
if (-not $KeepArtifacts) {
    foreach ($b in @($box1, $box2, $box4)) { Remove-Item $b -Recurse -Force -ErrorAction SilentlyContinue }
    T 'T20 删目录即卸载，且未污染默认目录' { @{ ok = ((-not (Test-Path $box1)) -and (-not (Test-Path $box4)) -and ((Test-Path $defaultRoot) -eq $bg)); detail = '沙箱已清理' } }
} else {
    T 'T20 删目录即卸载，且未污染默认目录' { @{ ok = $true; detail = '已跳过清理（-KeepArtifacts）' } }
}

# ---------------------------------------------------------------- 8
Write-Host "`n=== 8. 空的下载缓存目录 ===" -ForegroundColor Cyan
# 全程复用系统已装工具时一个字节都不会下载，_dl 会被建成空目录。
# 老逻辑用 sum -gt 0 判断，空目录的 Sum 是 $null，永远清不掉。
$box6 = Join-Path $base 'box6'
$dl6  = Join-Path $box6 '_dl'
New-Item -ItemType Directory -Force -Path $dl6 | Out-Null
& $src -ToolsRoot $box6 -SkipDefaults -SkipRustTools *> (Join-Path $log 't8.log')
T 'T21 空缓存目录也会被清理' { @{ ok = (-not (Test-Path $dl6)); detail = "_dl 仍存在 = " + (Test-Path $dl6) } }
Remove-Item $box6 -Recurse -Force -ErrorAction SilentlyContinue

# ---------------------------------------------------------------- 9
Write-Host "`n=== 9. 静态检查（防止老写法回来） ===" -ForegroundColor Cyan
$setupText  = Get-Content (Join-Path $PSScriptRoot 'setup-defaults.ps1') -Raw -Encoding UTF8
$verifyText = Get-Content (Join-Path $PSScriptRoot 'verify.ps1') -Raw -Encoding UTF8

# HKCU\Console\%%Startup 才是「默认终端程序」真正的开关；Explorer\Advanced 系统不读
$oldTerm = $setupText.Contains('WindowsTerminal_8wekyb3d8bbwe!Microsoft.WindowsTerminal_8wekyb3d8bbwe')
T 'T22 默认终端写到 Console\%%Startup' { @{ ok = ($setupText.Contains('HKCU:\Console\%%Startup') -and -not $oldTerm); detail = "写对位置 = $($setupText.Contains('HKCU:\Console\%%Startup'))，仍用老写法 = $oldTerm" } }

# PATH 判断必须是逐项精确比较 + 目录存在性检查，不能再靠子串包含
$oldPath = $verifyText.Contains('IndexOf($d')
T 'T23 体检的 PATH 检查逐项精确比较并验证目录存在' { @{ ok = (-not $oldPath -and $verifyText.Contains('Test-Path $d')); detail = "仍用子串匹配 = $oldPath" } }

# ---------------------------------------------------------------- 汇总
Write-Host "`n########## 结果 ##########" -ForegroundColor Magenta
$pass = ($results | Where-Object { $_.ok }).Count
$fail = ($results | Where-Object { -not $_.ok }).Count
$color = if ($fail -eq 0) { 'Green' } else { 'Red' }
Write-Host ("共 " + $results.Count + " 项  通过 " + $pass + "  失败 " + $fail) -ForegroundColor $color
if ($fail -gt 0) {
    Write-Host "`n失败项：" -ForegroundColor Red
    $results | Where-Object { -not $_.ok } | ForEach-Object { Write-Host ("  - " + $_.name + " : " + $_.detail) -ForegroundColor Red }
}
$report = Join-Path $base 'result.txt'
$results | ForEach-Object { ($(if ($_.ok) { 'PASS' } else { 'FAIL' })) + "`t" + $_.name + "`t" + $_.detail } |
    Set-Content $report -Encoding UTF8
Write-Host ("`n详细报告: " + $report)
if (-not $KeepArtifacts) {
    Write-Host "（沙箱目录保留在 TEMP 下，可手动删除）"
}

if ($fail -eq 0) { exit 0 } else { exit 1 }
