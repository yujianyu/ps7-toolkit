# 踩坑与排错

## Q: 安装脚本跑完，`powershell -v` 还是 5.1？
A: PATH 没刷新。脚本已广播 `WM_SETTINGCHANGE`，但**已开着的**窗口不会更新。关掉重开终端 / 应用。
若仍不行，检查用户 PATH 是否含 `%LOCALAPPDATA%\ps7-toolkit\ps7`。

## Q: 中文还是乱码？
A: 依次排查：
1. `[Console]::OutputEncoding` 应为 `utf-8`
2. `$OutputEncoding` 应为 `utf-8`
3. 输出被**管道**传递时，编码由管道两端决定 —— 在管道前显式设置 `[Console]::OutputEncoding = [Text.Encoding]::UTF8`
4. 用 `bat`/`rg` 这类原生写 UTF-8 的工具时，接收端要按 UTF-8 解码
5. 脚本自身若含中文却被 5.1 执行，脚本文件必须存成 **UTF-8 with BOM**

## Q: 下载 GitHub 失败 / 很慢？
A: 脚本内置三个镜像依次回退：`gh-proxy.com` → `ghfast.top` → `ghproxy.net` → 直连。
国内网络建议保持镜像在前。也可直接用 `-ZipPath` 指向本地已下载的 zip。

## Q: `Invoke-RestMethod` 调 api.github.com 报错？
A: PowerShell 5.1 默认 TLS 太老。脚本已设 `[Net.ServicePointManager]::SecurityProtocol = Tls12`。
若仍失败，会自动回退到内置的固定版本号（不联网也能装）。

## Q: `Expand-Archive` 很慢？
A: 正常，PS7 自带的压缩更快。7.6.7 的 zip 约 661 个文件、100MB，5.1 解压约 30~90 秒，属正常。

## Q: 安装后 `Add-Type` 报错？
A: 部分 AI 客户端（WorkBuddy 等）的安全策略禁止运行时编译 .NET 代码。
替代方案：解压用 `Expand-Archive`（内置，无需 Add-Type）；文件查找用 `rg`/`fd`（无需编译）。

## Q: `Get-Command pwsh` 找不到？
A: PATH 未刷新，或安装目录不在用户 PATH。检查：
`[Environment]::GetEnvironmentVariable('Path','User')`

## Q: 双击 .ps1 文件没反应 / 被拦？
A: 脚本把 `.ps1` 关联设为 `"pwsh.exe" -NoLogo -NoProfile -File "%1"`。
若系统 ExecutionPolicy 为 Restricted，双击会被拦。撤销关联：
删除注册表项 `HKCU:\Software\Microsoft\Classes\.ps1`

## Q: 改了默认终端后某个老程序全屏显示异常？
A: 撤销默认终端（回到 conhost）：
删除 `HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced` 的 `DelegationConsole` 值。

## Q: 怎么彻底卸载？
A:
1. `& "$env:LOCALAPPDATA\ps7-toolkit\scripts\verify.ps1"` 先看现状
2. 删除整个 `%LOCALAPPDATA%\ps7-toolkit` 目录
3. 撤销注册表三项：App Paths\pwsh.exe、Classes\.ps1、Explorer\Advanced\DelegationConsole
4. 删除两个 profile 文件里的 `# ===== ps7-toolkit ...` 段落
5. 删除开始菜单 `PowerShell 7.lnk`
