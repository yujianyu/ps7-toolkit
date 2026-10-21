# Changelog

本文件记录 PowerShell 7 工具链技能包的版本变化。

## 1.1.1

### 变更
- **优化技能描述（description），让 AI 更准地判断何时该用它。**
  原描述只讲「部署 PowerShell 7 + Rust 工具链」，偏技术术语；AI 在 Windows 上撞到
  「字符串缺少终止符」「中文乱码」「引号被拆散」「连 GitHub 超时」「不支持 `&&` / `?:`」
  「Select-String 太慢」这类具体报错时，未必能联想到本技能。
  新描述把这些**症状**直接写进去，并点明「多半是系统自带的 PowerShell 5.1 太老所致」，命中率更高。
- 英文描述（`description_en`）同步更新。

> 只有描述文字变化，安装器脚本无任何改动。

## 1.1.0

### 新增
- 安装器支持 `-Mirror` 参数：用户可指定自定义下载镜像，自动插到内置镜像列表最前。
- 安装器支持 `-CheckOnly` 参数：只做体检，不做任何持久化改动。
- `setup-defaults.ps1` 支持 `-PwshPath` / `-BinDir` 参数，无参数时自动探测已装位置，不再依赖硬编码路径。
- 新增 `assets/icon.png`（512×512）用于市场展示。
- SKILL.md 新增「这个技能会改动什么」章节，逐项列出所有持久化改动点与撤销方式。

### 变更
- 安装目录默认改为 `%LOCALAPPDATA%\ps7-toolkit`，移除对 `D:\Tools\ps7` 等固定盘符的依赖。
- 下载链改为「官方 API 查版本 → 三镜像回退 → 微软 aka.ms 短链 → 内置版本表兜底」，断网场景也能装。
- Rust 工具下载改为调用 GitHub Releases API 取真实 `browser_download_url`，不再靠猜文件名。

## 1.0.0

### 新增
- 初始版本：PowerShell 7 便携版安装、Rust 工具链安装、UTF-8 全局编码根治、pwsh 默认化（profile / PATH / App Paths / .ps1 关联 / 开始菜单 / Windows Terminal / VSCode）。
- `verify.ps1` 六段体检脚本，支持 `-Json` 输出。
- `references/troubleshooting.md` 踩坑文档。
