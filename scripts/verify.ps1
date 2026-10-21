#Requires -Version 5.1
<#
.SYNOPSIS
    体检脚本：检查 PowerShell 7 / Rust 工具 / 默认化配置是否到位，并输出诊断报告。
.PARAMETER ToolsRoot
    安装根目录，默认 $env:LOCALAPPDATA\ps7-toolkit
.PARAMETER PwshPath
    指定 pwsh.exe 路径。不填则自动探测。
.PARAMETER BinDir
    指定 Rust 工具目录。不填则自动探测。
.PARAMETER Json
    额外输出 JSON（便于其它程序解析）
#>
[CmdletBinding()]
param(
    [string]$ToolsRoot = (Join-Path $env:LOCALAPPDATA 'ps7-toolkit'),
    [string]$PwshPath,
    [string]$BinDir,
    [switch]$Json
)

$ErrorActionPreference = 'SilentlyContinue'
$report = [ordered]@{}

Write-Host "`n########## PowerShell 7 工具链体检 ##########" -ForegroundColor Magenta

# 0. 探测 pwsh
if (-not $PwshPath) {
    $cands = @(
        (Join-Path $ToolsRoot 'ps7\pwsh.exe'),
        'C:\Program Files\PowerShell\7\pwsh.exe',
        'C:\Program Files\PowerShell\7-preview\pwsh.exe',
        (Join-Path $env:LOCALAPPDATA 'Programs\PowerShell\7\pwsh.exe'),
        (Join-Path $env:USERPROFILE 'scoop\apps\powershell\current\pwsh.exe')
    )
    $g = Get-Command pwsh -ErrorAction SilentlyContinue
    if ($g) { $cands += $g.Source }
    foreach ($k in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\pwsh.exe',
                     'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\pwsh.exe')) {
        if (Test-Path $k) { $v = (Get-ItemProperty $k).'(default)'; if ($v) { $cands += $v } }
    }
    foreach ($c in ($cands | Where-Object { $_ } | Select-Object -Unique)) { if (Test-Path $c) { $PwshPath = $c; break } }
}
if (-not $BinDir) {
    $BinDir = Join-Path $ToolsRoot 'bin'
    if (-not (Test-Path $BinDir)) {
        foreach ($c in @((Join-Path $env:LOCALAPPDATA 'ps7-toolkit\bin'), 'G:\Tools\bin')) {
            if (Test-Path $c) { $BinDir = $c; break }
        }
    }
}

# 1. PowerShell 7
Write-Host "`n[1] PowerShell 7"
$ver = $null
if ($PwshPath -and (Test-Path $PwshPath)) {
    try { $ver = (& $PwshPath -NoProfile -Command '$PSVersionTable.PSVersion.ToString()' | Select-Object -First 1) } catch { }
}
if ($ver) { Write-Host ("    [OK] {0}  ->  {1}" -f $ver, $PwshPath) -ForegroundColor Green }
else { Write-Host "    [X] 未安装或不可用" -ForegroundColor Red }
$report['pwsh'] = @{ path = $PwshPath; version = $ver; ok = [bool]$ver }

# 2. Rust 工具
Write-Host "`n[2] Rust 高性能工具"
$tools = @{}
foreach ($t in 'rg','fd','fzf','bat','delta','jq') {
    $exe = Join-Path $BinDir "$t.exe"
    $src = $exe
    if (-not (Test-Path $exe)) {
        $g = Get-Command $t -ErrorAction SilentlyContinue
        if ($g) { $src = $g.Source }
    }
    if ($src -and (Test-Path $src)) {
        $v = (& $src --version 2>$null | Select-Object -First 1)
        Write-Host ("    [OK] {0,-6} {1}" -f $t, $v) -ForegroundColor Green
        $tools[$t] = $v
    } else {
        Write-Host ("    [X] {0,-6} 未安装" -f $t) -ForegroundColor Red
        $tools[$t] = $null
    }
}
$report['tools'] = $tools
$report['binDir'] = $BinDir

# 3. profile
Write-Host "`n[3] PowerShell profile（UTF-8 根治）"
$docs = [Environment]::GetFolderPath('MyDocuments')
foreach ($p in @((Join-Path $docs 'WindowsPowerShell\Microsoft.PowerShell_profile.ps1'), (Join-Path $docs 'PowerShell\Microsoft.PowerShell_profile.ps1'))) {
    if ((Test-Path $p) -and ((Get-Content $p -Raw) -match 'ps7-toolkit')) { Write-Host "    [OK] $p" -ForegroundColor Green }
    else { Write-Host "    [X] $p" -ForegroundColor Red }
}

# 4. 注册表与关联
Write-Host "`n[4] 注册表与文件关联"
foreach ($c in @(
    @{ n = 'App Paths\pwsh.exe'; p = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\pwsh.exe' },
    @{ n = '.ps1 关联';         p = 'HKCU:\Software\Microsoft\Classes\.ps1\shell\open\command' },
    @{ n = '默认终端(Terminal)'; p = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' })) {
    if (Test-Path $c.p) { Write-Host ("    [OK] " + $c.n) -ForegroundColor Green }
    else { Write-Host ("    [X] " + $c.n) -ForegroundColor Red }
}

# 5. 应用层
Write-Host "`n[5] 应用层配置"
$lnk = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\PowerShell 7.lnk'
if (Test-Path $lnk) { Write-Host "    [OK] 开始菜单 PowerShell 7" -ForegroundColor Green } else { Write-Host "    [X] 开始菜单 PowerShell 7" -ForegroundColor Red }
$wt = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'
if (Test-Path $wt) {
    $c = Get-Content $wt -Raw -Encoding UTF8 | ConvertFrom-Json
    $hit = $c.profiles.list | Where-Object { $_.name -eq 'PowerShell 7' }
    if ($hit -and $c.defaultProfile -eq $hit.guid) { Write-Host "    [OK] Windows Terminal 默认 = PS7" -ForegroundColor Green }
    else { Write-Host "    [!] Windows Terminal 未指向 PS7" -ForegroundColor Yellow }
} else { Write-Host "    [-] 未安装 Windows Terminal" -ForegroundColor DarkGray }

# 6. PATH
Write-Host "`n[6] PATH"
$up = [Environment]::GetEnvironmentVariable('Path','User')
$ps7dir = if ($PwshPath) { Split-Path -Parent $PwshPath } else { $null }
foreach ($d in @($ps7dir, $BinDir)) {
    if (-not $d) { continue }
    if ($up -like "*$d*") { Write-Host "    [OK] $d" -ForegroundColor Green } else { Write-Host "    [X] $d 不在用户 PATH" -ForegroundColor Red }
}

if ($Json) { Write-Host "`n----JSON----"; Write-Host ($report | ConvertTo-Json -Depth 6) }
Write-Host "`n体检结束。`n"
