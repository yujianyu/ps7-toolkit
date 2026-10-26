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
删除 `HKCU\Console\%%Startup` 的 `DelegationConsole` 与 `DelegationTerminal` 两个值
（或把两者都改成 `{B23D10C0-E52E-411E-9D5B-C09FDF709C7D}` 指定用旧控制台宿主）。

## Q: 默认终端改好了，但我的 `settings.json` 里注释没了？
A: 这是 1.1.4 及更早版本造成的。旧写法会先 `ConvertFrom-Json` 再 `ConvertTo-Json` 整文件重写，
注释、空行、字段顺序在那一步就丢了，本工具没有留原始副本，**没法自动还原**。
1.1.5 起改成文本级定点修改，只动 `defaultProfile` 那一行和 `profiles.list` 里的一条，其余字节原样保留；
并且即使本次无需修改也会留一份 `settings.json.ps7bak`（已存在则不覆盖，永远是「还没被改过」的那份）。

注释要找回，可以从这两个地方取：Windows Terminal 侧的默认配置模板
（`%LOCALAPPDATA%\Microsoft\Windows Terminal\defaults.json` 或设置界面的「打开 JSON 文件」），
以及任何你之前手工备份过的副本。已经丢掉的注释只能手工补，工具不会凭空生成。

## Q: `.ps7bak` 可以删吗？
A: 可以。它只是还原用的副本。想回到改之前的状态：把 `settings.json.ps7bak` 改名覆盖回
`settings.json`（先关掉 Windows Terminal）。删掉后下次运行会重新生成一份当时的快照。

## Q: jq 报 `INVALID_CHARACTER` / 处理不了中文键名？
A: jq 的裸字段名（`.名称`）只支持 ASCII，中文键名必须走括号写法：
`jq -r '.["名称"]'`（英文双引号包住键名）。中文**值**不受影响，`jq -r .name` 读到中文值是正常的。
AI 助手生成过滤器时最容易写成 `.名称`，报这个错先检查是不是中文键名没用 `["..."]`。

## Q: 命令里的反引号被吃掉了 / 报错 unmatched / 写出来的文件缺了反引号？
A: 反引号在 bash（Git Bash / MSYS2）里是**命令替换**，在 pwsh 里是**转义符**，两个 shell 都会先动它：
- bash：`` echo `date` `` 里的 `date` 会被真的执行，输出塞回命令行；落单的反引号报
  `unmatched` 或把后半段吞掉；`cat <<EOF` 未加引号时，正文里的反引号和 `$` 会被展开后再落盘。
- pwsh：反引号吞掉后面一个字符，`"a`nb"` 会变成换行，行尾的反引号是续行。

处理：① 命令替换写 `$(date)`；② 字面反引号放单引号 `'...`...'`；
③ 写文件用带引号的 heredoc：`cat <<'EOF' ... EOF`；④ 拿不准先跑
`scripts\shell-guard.ps1 -Text '...'` 让它诊断（退出码 0 安全 / 1 有风险）。
从 bash 调守卫时 `-Text` 后面必须**用单引号**，否则反引号到不了守卫就被吃掉了。

## Q: bash 里 `cd C:\Users\x` 报找不到目录，或路径诡异地变了？

反斜杠在 bash（引号外）是转义符，会被吃掉：`C:\Users\x` 实际变成 `C:Usersx`。
写法二选一：整段路径放进**单引号** `cd 'C:\Users\x'`，或改用**正斜杠** `cd C:/Users/x`（Windows 程序也认）。
执行前可先过守卫：`pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\shell-guard.ps1 -Text 'cd C:\Users\x'`，它会指出每一处被吃掉反斜杠的路径。

## Q: 在 Windows PowerShell 5.1 里 `curl`、`&&`、写文件都表现异常？

三个都是 5.1 的老问题，pwsh 7 全部没有：

- `curl` 在 5.1 是 Invoke-WebRequest 的**别名**，参数跟真 curl 完全不同 → 写 `curl.exe`
- `&&` / `||` / 三元 `?:` 在 5.1 直接报「token && 不是有效的语句元素」→ 用 pwsh 7 跑，或写成 `cmd1; if ($LASTEXITCODE -eq 0) { cmd2 }`
- `Out-File` / `>` 在 5.1 默认 **UTF-16**，bash、python 读到全是乱码 → 显式加 `-Encoding utf8`，或用 pwsh 7（默认 UTF-8）

另外判断上一条命令成败要用 `$LASTEXITCODE`（原生 exe），它不会自动清零，用前先置 0；`$?` 只是布尔值。
守卫会顺带提醒这些：`pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\shell-guard.ps1 -Shell pwsh -Text 'curl https://example.com'`。

> 守卫参数是 `-Text`（不是 `-Command`，避免撞上 powershell.exe 自身开关）。跨进程调守卫请用
> pwsh 7 的 `-File`；**任何 `-Command` 式跨进程转发都丢内层双引号（5.1 与 pwsh 7 实测均丢）**。

## Q: 明明写的是 `git commit -m "a  b"`，提交信息却变成好几段？

跨进程 `-Command` 转发会丢内层双引号：命令行在 argv 层被重新切分，`"a  b"` 变成两个独立参数——
**你看到的命令和实际执行的不是同一条**（5.1 与 pwsh 7 实测都丢，与版本无关）。
规避写法：在会话内直接执行；或写进 `.ps1` 用 `-File` 跑；程序化调用一律走
`-EncodedCommand`（Base64 UTF-16LE，本工具守卫的 `-Execute` 内部就是这么做的）。

## Q: 怎么彻底卸载？
A:
1. `& "$env:LOCALAPPDATA\ps7-toolkit\scripts\verify.ps1"` 先看现状
2. 删除整个 `%LOCALAPPDATA%\ps7-toolkit` 目录（安装时用了 `-ToolsRoot` 的，删那个目录）
3. 撤销注册表三项：App Paths\pwsh.exe、Classes\.ps1、Console\%%Startup 的 DelegationConsole / DelegationTerminal
4. 删除两个 profile 文件里的 `# ===== ps7-toolkit ...` 段落
5. 删除开始菜单 `PowerShell 7.lnk`
