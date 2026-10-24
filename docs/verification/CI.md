# CI 状态：已提交工作流，尚未在 GitHub 上运行

- 日期：2026-10-24
- 关联：M0-02（隔离验证入口）、M1 收尾
- 文件：`.github/workflows/verify.yml`

## 1. 做了什么

把本地的隔离验证入口搬进 CI：checkout → 下载 Godot 4.7.2（Linux headless）→ `pwsh -File tools/verify.ps1`。

为了让脚本能在 Linux 上跑，`tools/verify.ps1` 增加了平台分支：

| 平台 | `user://` 根目录 |
|---|---|
| Windows | `%APPDATA%\Godot\app_userdata` |
| Linux/macOS | `$HOME/.local/share/godot/app_userdata` |

Windows 路径已回归（20 条断言全绿，真实存档目录未被触碰）。

## 2. 真实状态

| 项 | 状态 | 说明 |
|---|---|---|
| 工作流文件 | 已提交 | `.github/workflows/verify.yml` |
| 在 GitHub Actions 上运行 | **未运行** | 开发机没有 runner、没有 `gh` CLI、没有 API token，无法触发也无法读日志 |
| 首次运行是否通过 | **未知** | 不宣称通过 |
| Windows 本地等价验证 | 已通过 | `tools/verify.ps1` → `pass=20 fail=0`，exit 0 |

## 3. 首次运行可能遇到的问题（预判）

1. **引擎下载地址**：`https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_linux.x86_64.zip` 是按版本号推测的命名。若 404，需要改成实际的发布资产名。
2. **PowerShell 在 Linux 上的行为**：`Start-Job`、`Join-Path`、`[System.IO.Path]::GetTempPath()` 理论可用，但未实测。
3. **`user://` 大小写与路径分隔符**：Godot 在 Linux 上返回正斜杠路径，脚本里的 `find`/字符串比较是分隔符无关的，但未实测。
4. **中文字符**：`浮生` 目录在 Linux 上不存在时脚本按"无真实存档"处理，属预期。

以上都在工作流注释里标了"尚未真实运行"。

## 4. 为什么不标为"CI 已接通"

规划明确要求：**没有 runner 时如实标 blocked，不能宣称 CI 完成**。

工作流文件存在 ≠ CI 通过。目前能说的只有："入口已编码并提交，Windows 本地等价路径已验证，GitHub 侧未运行。"
