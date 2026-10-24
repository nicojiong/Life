# CI 状态：已接入并在 GitHub Actions 上真实通过

- 日期：2026-10-24
- 关联：M0-02（隔离验证入口）、M1 集成验收
- 文件：`.github/workflows/verify.yml`、`tools/verify.ps1`

## 1. 现在的真实状态

| 项 | 状态 | 证据 |
|---|---|---|
| 工作流文件 | 已提交 | `.github/workflows/verify.yml` |
| 在 GitHub Actions 上运行 | **已运行并成功** | run `40051930378`（SHA `e893052`），全部 8 个步骤 success |
| 日志产物 | 已上传 | `verify-artifacts`，1207 B |
| 本地等价验证 | 通过 | `pass=26 fail=0`，exit 0 |

历史：`e8cf720` 与 `33a768b` 两次失败（退出码 2），原因见下。

## 2. 修掉的两个 CI 真问题

### 2.1 Linux 存档路径大小写

Godot 在 Linux 上把 `user://` 放在 `~/.local/share/godot/app_userdata/<项目名>`（**小写** `godot`），Windows 是 `%APPDATA%\Godot\...`（大写）。

脚本统一用 `Godot` 判定，于是 Linux 上 `Test-Path $userDir` 恒为假 → 脚本判定"隔离存档目录未创建" → 退出码 2。这正好是前两次失败的退出码。

修复：按平台选择目录名（Windows/macOS 用 `Godot`，Linux 用 `godot`）。

### 2.2 日志产物在上传前被清理

`finally` 会删掉临时目录，而日志写在临时目录里；`upload-artifact` 因此报 "No files were found"，失败时拿不到任何现场。

修复：日志先落盘到仓库内 `verify-artifacts/`，再清理临时目录；工作流改为 `if: always()` 上传。`verify-artifacts/` 已加入 `.gitignore`。

## 3. 断言完整性校验

原来只数 `[VERIFY] PASS/FAIL` 行，理论上"跑了一半就崩"也可能被算作通过。

现在 `verify.ps1` 增加 `-ExpectedAssertions`（当前 26）：

- 没有 `[VERIFY] SUMMARY` 行 → 失败；
- `pass` 条数与预期不符 → 失败；
- 失败原因会打印到控制台，并由工作流转成 `::error::` 注解（公开仓库无需登录即可读）。

## 4. 失败时怎么定位

工作流在 `if: always()` 的步骤里打印日志尾部，并把 `[VERIFY] FAIL`、`[verify] FAIL`、`[SAVE] refused`、`ERROR` 行转成注解。

实测有效：前两次失败就是通过 `check-runs/{job_id}/annotations` 读到 `Process completed with exit code 2.` 与 `No files were found with the provided path: /tmp/life-verify-*/run.log`，才定位到 §2 的两个问题。

## 5. 仍未覆盖

- 只在 ubuntu-latest 上跑，Windows/macOS 的 CI 未配置。
- 没有缓存 Godot 下载，每次运行都要重新拉取。
- Actions 版本仍是 `checkout@v4` / `upload-artifact@v4`，GitHub 已提示 Node 20 弃用（当前只是警告，未影响结果）。


## 6. 读 CI 结果的三种方式（含限流后的替代）

| 方式 | 用途 | 限制 |
|---|---|---|
| `api.github.com/repos/{repo}/actions/runs` | 按 SHA 精确查、看步骤 | 未认证 60 次/小时，轮询容易打满 |
| `api.github.com/repos/{repo}/check-runs/{job_id}/annotations` | 读失败原因的注解 | 同样计入限流 |
| `github.com/{repo}/commit/{sha}/checks`（HTML） | 限流后确认某次提交是否通过 | 需解析 HTML，不是结构化数据 |
| `github.com/{repo}/actions/workflows/verify.yml/badge.svg?branch=X` | 分支最新一次的状态 | 只反映最新一次，不能按 SHA 定位 |

本轮实测：连续轮询把未认证配额打满（`API rate limit exceeded`），随后改用
`commit/{sha}/checks` 页面确认——页面里出现 `color-bg-success-emphasis` 与 `data-conclusion="success"`，
即该 SHA 的 isolated-smoke 通过。
