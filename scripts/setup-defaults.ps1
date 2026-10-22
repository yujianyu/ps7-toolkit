#Requires -Version 5.1
<#
.SYNOPSIS
    把 pwsh 配置为系统默认，并根治中文乱码。所有改动均为【用户级】，不需要管理员权限，可一键回退。
.PARAMETER PwshPath
    pwsh.exe 的完整路径。不填则自动探测系统里已安装的 PowerShell 7。
.PARAMETER BinDir
    Rust 工具目录（rg/fd/fzf/bat/delta/jq）。不填则用 $env:LOCALAPPDATA\ps7-toolkit\bin
.PARAMETER ToolsRoot
    安装根目录（仅用于推导默认路径）
#>
[CmdletBinding()]
param(
    [string]$PwshPath,
    [string]$BinDir,
    [string]$ToolsRoot = (Join-Path $env:LOCALAPPDATA 'ps7-toolkit')
)

$ErrorActionPreference = 'Continue'

# ---- 自动探测 pwsh ----
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
        if (Test-Path $k) { $v = (Get-ItemProperty $k -ErrorAction SilentlyContinue).'(default)'; if ($v) { $cands += $v } }
    }
    foreach ($c in ($cands | Where-Object { $_ } | Select-Object -Unique)) {
        if (Test-Path $c) { $PwshPath = $c; break }
    }
}
if (-not $PwshPath) { Write-Host "    [X] 找不到 pwsh.exe，跳过默认化" -ForegroundColor Red; exit 1 }

if (-not $BinDir) { $BinDir = Join-Path $ToolsRoot 'bin' }
$PS7Dir = Split-Path -Parent $PwshPath

function Say ($m) { Write-Host $m }

# ---------------------------------------------------------------- 1. profile（UTF-8 根治）
Say "`n[1/6] 写入 PowerShell profile（强制 UTF-8）"
$docs = [Environment]::GetFolderPath('MyDocuments')
$profiles = @{
    (Join-Path $docs 'WindowsPowerShell\Microsoft.PowerShell_profile.ps1') = 'PS5.1'
    (Join-Path $docs 'PowerShell\Microsoft.PowerShell_profile.ps1')          = 'PS7'
}
foreach ($p in $profiles.Keys) {
    $dir = Split-Path -Parent $p
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $extra = ''
    if ($profiles[$p] -eq 'PS7') {
        $extra = "`r`n# Rust high-performance tools (rg/fd/fzf/bat/delta/jq)`r`nif (`$env:PATH -notlike ('*' + '$BinDir' + '*')) { `$env:PATH = '$BinDir;' + `$env:PATH }"
    }
    $content = @"
# ===== ps7-toolkit: force UTF-8 everywhere =====
# Fixes garbled Chinese output for every app that shells out to PowerShell.
try {
    `$utf8 = New-Object System.Text.UTF8Encoding `$false
    [Console]::OutputEncoding = `$utf8
    `$global:OutputEncoding = `$utf8
    `$PSDefaultParameterValues['Out-File:Encoding']    = 'utf8'
    `$PSDefaultParameterValues['Set-Content:Encoding'] = 'utf8'
    `$PSDefaultParameterValues['Add-Content:Encoding'] = 'utf8'
} catch { }
$extra
"@
    if ((Test-Path $p) -and ((Get-Content $p -Raw -ErrorAction SilentlyContinue) -match 'ps7-toolkit')) {
        Say "    已存在(跳过): $p"
    } else {
        if (Test-Path $p) { Copy-Item $p "$p.bak" -Force }
        [System.IO.File]::WriteAllText($p, $content, (New-Object System.Text.UTF8Encoding $true))
        Say "    已写入: $p"
    }
}

# ---------------------------------------------------------------- 2. 用户 PATH
Say "`n[2/6] 配置用户 PATH"
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if (-not $userPath) { $userPath = '' }

# 逐项处理，不用 -like "*$d*" 那种子串包含：
#   1) 子串匹配会让 G:\Tools\bin2 因为「含 G:\Tools\bin」而被跳过（其实没配）；
#   2) 老逻辑只做「缺了就追加」，换安装目录重装后旧 root 的项永远留着，最后变成死链。
$entries = @()
foreach ($e in $userPath.Split(';')) {
    $t = $e.Trim()
    if ($t) { $entries += $t }
}

$kept = @(); $pruned = @()
foreach ($e in $entries) {
    $exp = [Environment]::ExpandEnvironmentVariables($e).TrimEnd('\')
    # 只清理「看起来是本工具装的、且目录确实已经不在了」的项；别人的路径一律不动
    $ours = ($exp -match 'ps7-toolkit') -or ($exp -eq $PS7Dir.TrimEnd('\')) -or ($exp -eq $BinDir.TrimEnd('\'))
    # 再退一步：连所在的盘都不可用（移动硬盘没插、网络盘断线）就不动，免得拔一次盘配置就被删了
    $rootUsable = $true
    try {
        $root = [System.IO.Path]::GetPathRoot($exp)
        if ($root) { $rootUsable = Test-Path $root }
    } catch { }
    if ($ours -and $rootUsable -and -not (Test-Path $exp)) { $pruned += $e } else { $kept += $e }
}

$add = @()
foreach ($d in @($PS7Dir, $BinDir)) {
    $dn = $d.TrimEnd('\')
    $has = $false
    foreach ($e in $kept) {
        if ([string]::Equals($e.TrimEnd('\'), $dn, [StringComparison]::OrdinalIgnoreCase)) { $has = $true; break }
    }
    if (-not $has) { $add += $d }
}

if ($add.Count -gt 0 -or $pruned.Count -gt 0) {
    [Environment]::SetEnvironmentVariable('Path', ((@($kept) + @($add)) -join ';'), 'User')
    if ($pruned.Count -gt 0) { Say "    已移除失效的旧路径: $($pruned -join ', ')" }
    if ($add.Count -gt 0) { Say "    已加入: $($add -join ', ')" }
} else { Say "    PATH 已包含，无需修改" }

# ---------------------------------------------------------------- 3. App Paths
Say "`n[3/6] 注册 App Paths\pwsh.exe"
$k = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\pwsh.exe'
if (-not (Test-Path $k)) { New-Item -Path $k -Force | Out-Null }
Set-ItemProperty -Path $k -Name '(default)' -Value $PwshPath -ErrorAction SilentlyContinue
Set-ItemProperty -Path $k -Name 'Path' -Value $PS7Dir -ErrorAction SilentlyContinue
Say "    $PwshPath"

# ---------------------------------------------------------------- 4. .ps1 文件关联
Say "`n[4/6] 设置 .ps1 文件关联 -> pwsh"
$cmd = "`"$PwshPath`" -NoLogo -NoProfile -File `"%1`""
$k2 = 'HKCU:\Software\Microsoft\Classes\.ps1\shell\open\command'
if (-not (Test-Path $k2)) { New-Item -Path $k2 -Force | Out-Null }
Set-ItemProperty -Path $k2 -Name '(default)' -Value $cmd
Say "    $cmd"
Say "    (提示: 双击 .ps1 会直接执行脚本。想撤销: 删除 HKCU:\Software\Microsoft\Classes\.ps1)"

# ---------------------------------------------------------------- 5. 开始菜单快捷方式
Say "`n[5/6] 开始菜单快捷方式"
$menu = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'
$lnk = Join-Path $menu 'PowerShell 7.lnk'
try {
    $ws = New-Object -ComObject WScript.Shell
    $s = $ws.CreateShortcut($lnk)
    $s.TargetPath = $PwshPath
    $s.WorkingDirectory = $env:USERPROFILE
    $s.IconLocation = "$PwshPath,0"
    $s.Description = 'PowerShell 7'
    $s.Save()
    Say "    已创建: PowerShell 7.lnk"
} catch { Say "    跳过(无法创建快捷方式): $($_.Exception.Message)" }

# ---------------------------------------------------------------- 6. Windows Terminal / VSCode
Say "`n[6/6] 配置 Windows Terminal 与 VSCode"
$wt = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'
if (Test-Path $wt) {
    try {
        $cfg = Get-Content $wt -Raw -Encoding UTF8 | ConvertFrom-Json
        $guid = '{9e1b2a44-7c3d-4f8e-b5a1-2d6c9f0e3b71}'
        $plist = $cfg.profiles.list
        if (-not ($plist | Where-Object { $_.name -eq 'PowerShell 7' })) {
            $new = [PSCustomObject]@{ commandline = $PwshPath; guid = $guid; hidden = $false; name = 'PowerShell 7'; icon = 'ms-appx:///ProfileIcons/pwsh.png' }
            $cfg.profiles.list = @($plist) + $new
        }
        $cfg.defaultProfile = $guid
        $cfg | ConvertTo-Json -Depth 20 | Set-Content $wt -Encoding UTF8
        Say "    Windows Terminal 默认配置 -> PowerShell 7"
        # 「默认终端程序」真正的开关在 HKCU\Console\%%Startup 的两个 GUID 值（微软官方文档口径）。
        # 以前写的是 Explorer\Advanced\DelegationConsole —— 那个位置系统根本不读，等于什么都没做，
        # 体检那边也只查了「键是否存在」，所以一直是假 OK。
        $startup = 'HKCU:\Console\%%Startup'
        if (-not (Test-Path $startup)) { New-Item -Path $startup -Force | Out-Null }
        Set-ItemProperty -Path $startup -Name 'DelegationConsole'  -Value '{2EACA947-7F5F-4CFA-BA87-8F7FBEEFBE69}'
        Set-ItemProperty -Path $startup -Name 'DelegationTerminal' -Value '{E12CFF52-A866-4C77-9A90-F570A7AA2C6B}'
        Say "    默认终端程序 -> Windows Terminal"
    } catch { Say "    Windows Terminal 配置失败: $($_.Exception.Message)" }
} else { Say "    未检测到 Windows Terminal，跳过" }

$vs = Join-Path $env:APPDATA 'Code\User\settings.json'
if (Test-Path $vs) {
    try {
        $s = Get-Content $vs -Raw -Encoding UTF8 | ConvertFrom-Json
        $s | Add-Member -NotePropertyName 'terminal.integrated.defaultProfile.windows' -NotePropertyValue 'PowerShell 7' -Force
        $s | Add-Member -NotePropertyName 'terminal.integrated.profiles.windows' -NotePropertyValue ([PSCustomObject]@{'PowerShell 7' = [PSCustomObject]@{ path = $PwshPath; icon = 'terminal-powershell' }}) -Force
        $s | ConvertTo-Json -Depth 10 | Set-Content $vs -Encoding UTF8
        Say "    VSCode 默认终端 -> PowerShell 7"
    } catch { Say "    VSCode 配置失败: $($_.Exception.Message)" }
} else { Say "    未检测到 VSCode，跳过" }

try {
    Add-Type -Namespace Win -Name Native -MemberDefinition '[DllImport("user32.dll", SetLastError=true, CharSet=CharSet.Auto)] public static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint Msg, UIntPtr wParam, string lParam, uint fuFlags, uint uTimeout, out UIntPtr lpdwResult);'
    $r = [UIntPtr]::Zero
    [Win.Native]::SendMessageTimeout([IntPtr]0xffff, 0x1A, [UIntPtr]::Zero, 'Environment', 0x0002, 3000, [ref]$r) | Out-Null
    Say "`n    已广播环境变量变更（新开的应用立即生效）"
} catch { }
Say "`n默认化完成。`n"
