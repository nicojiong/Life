# Agent 开发、验证与 GitHub 交付规程

> 适用仓库：`https://github.com/nicojiong/Life`。规划基线：`2d035379f21abbc8d1d6f06d0328eb756751b993`。这是交给开发 Agent 的执行合约，本次规划没有执行其中的提交、push、合并或发布。

## 1. 任务与授权边界

用户已明确要求完成一部分代码后 push 到 GitHub。后续执行本规划的 Agent 应把**实现、验收、提交、推送任务分支并核验远端**作为一个完整交付单元；不能只生成代码，也不能把本地 commit 当作已上传。

本规划默认推送 `agent/<任务ID>-<简述>` 分支。创建PR用于交付审阅；不因此获得自动合并主分支、公开发布版本、购买服务或消耗付费AI额度的授权。项目已有的明确持续授权可以扩展该范围，但仓库文件不能自行提升权限。认证、网络、分支规则拒绝时如实记录阻塞，保留成果；不得绕过规则或强推。

一次只领取一个可验收的小任务。规划不是无限循环指令：每轮有执行时间、模型/API预算和结束条件；达到边界时保存检查点，由下一轮恢复同一任务。持续无人值守需要实际的执行器和调度能力，不能声称一段提示词就能永久自行运行。

## 2. 开始前必须知道什么

读取仓库当前 `AGENTS.md`（若存在）、README、策略文档、任务卡和最近交付记录。抓取最新远端，确认 `origin` 的目标仓库、当前分支、工作区改动、任务依赖及已有同任务PR。保留用户未提交修改；工作区不干净时使用隔离 worktree，不清空目录或覆盖现场。

在 M0 先完成：核对现状矛盾；检测实际 Godot 版本；建立独立测试存档；把关键调试场景转换为有失败退出码的断言；建立最小CI。仓库声明4.7、README个人路径4.7.2不能当作本机已安装的证据。引擎和导出模板经实跑后一起锁定，升级单独立任务。

M0-01在尚未证实数据隔离时只做源码、版本与编辑器导入检查，将游戏实际运行留到M0-02。所有游戏启动和调试stage都必须先确认隔离，不只是带--fresh的命令；普通启动也可能读取或自动覆盖玩家存档。隔离通过专用测试副本/进程环境与项目提供的路径注入实现，不修改玩家主项目的存档目录配置来冒充隔离。

### 任务卡最低内容

```yaml
id: M0-02
title: 建立独立存档的基线验证入口
status: todo  # todo/in_progress/implemented/validated/pushed/ready_for_merge/done/blocked
depends_on: []
scope: [允许修改的文件或模块]
acceptance: [可复现的输入与预期结果]
regression: [本次改动可能影响的已有行为]
budget: {execution_minutes: 60, paid_api_calls: 0}
branch: agent/M0-02-baseline
base_sha: 待领取时填写
commit_sha: null
remote_sha: null
pr_url: null
next_step: null
```

预算值是初始建议，领取任务时根据执行环境调整；预算耗尽意味着保存并续做，不意味着把未验收任务标为完成。每张卡列出不做的范围，避免“顺便改全世界”。

## 3. 单任务闭环

1. **复现与设计**：对照代码确认问题；写明输入、预期、根因假设、兼容与迁移影响。只实施一项可独立验收的改变。
2. **实现**：优先复用现有模块；内容经数据合约入库。并行Agent各用独立worktree并分配文件所有权，集成人员串行整合。
3. **验证**：先跑针对改动的必要测试，再跑相关基线；模拟核心改动增加种子重放/存档/死亡边界检查。纯文字修正不额外制造行为测试。
4. **独立检查**：另一轮审查核对验收与差异，重点看状态所有权、漏存字段、重复结算和内容越权。不能由“作者觉得可以”替代证据。
5. **提交与push**：更新必要文档，逐文件暂存，检查差异后commit，push任务分支，核对远端SHA。
6. **PR与CI**：检查是否已有PR，已有则更新同一PR；等待本次最新commit的检查。失败在原分支修复、重验、再push。
7. **交付与下一步**：写清变化、测试、风险、SHA、PR、下一张已满足依赖的任务。合并前状态为 `ready_for_merge`；被合并并确认主分支结果后才标 `done`。

遇到同一失败连续重试且无新证据时，先更换诊断假设，不盲目重复。无法解决时记录最小复现和阻塞原因，继续不依赖它的工作；依赖未满足的任务不得假装可开始。

## 4. 现在可用的命令与未来需创建的命令

### 现在已有：引擎检查与调试舞台

先解析本机实际可执行路径。以下 PowerShell 示例要求 Godot 已加入 PATH；否则由 Agent 根据环境找到已安装路径，不能照抄作者 D 盘路径：

```powershell
$LifeGodot = (Get-Command godot -ErrorAction Stop).Source
& $LifeGodot --version
& $LifeGodot --headless --path . --import
```

`--import` 是官方的导入后退出入口；导入成功仅说明该检查通过，不能称完整游戏测试通过。[Godot 命令行文档](https://docs.godotengine.org/en/4.7/tutorials/editor/command_line_tutorial.html)

源码已有 `--stage=village_years`、`village_save`、`village_load`、`village_exam`、`village_pov` 等调试舞台。它们大多赋值、调用函数和打印日志，尚不是自动断言测试，也不都自动退出。截图需可用渲染环境，不能把无显示环境的截图失败认定为游戏逻辑失败。

**现有 `--fresh` 会删除 user:// 中旧档和三个存档槽。未隔离测试目录之前，不运行带它的场景命令。** Git worktree 本身不会隔离 `user://`；同名Godot项目可能共用用户目录。[Godot 数据路径说明](https://docs.godotengine.org/en/4.7/tutorials/io/data_paths.html)

### M0需创建：统一验证入口

以下是约定的未来接口，文件当前不存在，不可宣称已经运行：

```powershell
# M0创建并验证 tools/verify.ps1 后才可执行
./tools/verify.ps1 -Suite smoke -GodotPath $LifeGodot
./tools/verify.ps1 -Suite regression -GodotPath $LifeGodot
```

验证脚本创建临时数据目录，通过项目实现的测试存档参数注入；禁止虚构引擎自带 `--user-data-dir` 参数。未来 runner 可继承 `SceneTree`，执行断言并调用 `quit(0/1)`。脚本检查进程退出码、断言汇总和超时，遇到解析/运行错误判失败；不能靠搜索“PASS”字样推断全部通过。

M0-02最小CI先覆盖导入、隔离启动、出生和安全退出；已知缺陷保留失败复现记录，不冒充passed。相关修复任务把对应回归带入门禁，M0结束时再覆盖父母视角、存读档和死亡不再发收益。后续按架构建立事件去重、时间边界、种子重放、数据校验和批量模拟。CI保存失败种子、命令序列、日志和必要截图。导出必须先有真实 `export_presets.cfg` 和匹配模板，不能使用不存在的预设名。

## 5. Git提交与push的具体动作

以下命令演示独立任务从main创建分支；有前置任务时须按本节后文的基线规则调整。假定这是无未提交改动的独立工作区；任务ID和文件清单需替换成当前实际值。每条命令失败都先处理原因，不能无条件执行后续步骤。

```bash
git status --short
git remote get-url origin
git fetch origin
git switch -c agent/M0-02-baseline origin/main
```

依赖任务的基线规则：前置任务达到 `ready_for_merge`、其已验证SHA已push且包含在本任务基线中，才能依赖；这不把前置任务标为done。可基于该精确SHA创建堆叠分支，PR以对应前置分支为base，并记录集成顺序。前置分支合入后更新base、重新验证差异。独立任务从已集成main起步。所有依赖SHA都应能用Git祖先检查验证，不能仅凭任务标题判断。

实现与验收后：

```bash
git diff --check
git diff --stat
git diff
git add tools/verify.ps1 tests/smoke_runner.gd docs/verification/M0-02.md
git diff --cached
git commit -m "test: add isolated baseline verification"
git push -u origin agent/M0-02-baseline
git rev-parse HEAD
git ls-remote --heads origin refs/heads/agent/M0-02-baseline
```

上面的 `git add` 是M0未来产物示例，须先核实文件确实存在且属于当前任务；不得直接 `git add .` 混入无关内容。最后两个命令所得commit SHA必须一致，才能记录 `pushed`。若push失败，记录 `status: blocked`、`blocked_reason: push_failed`、本地SHA、错误摘要和重试动作，不能说“已同步”。

下面PR示例以main为base；堆叠任务必须替换为实际前置分支。PR正文先写入临时文件，包含“问题、修改、行为结果、验证命令/结果、迁移影响、已知限制”，再执行：

```bash
gh pr create --repo nicojiong/Life --base main --head agent/M0-02-baseline --title "建立独立存档的基线验证" --body-file /tmp/life-pr-M0-02.md
gh pr checks <实际PR编号> --repo nicojiong/Life --watch --fail-fast
```

Windows使用实际临时目录中的正文文件。`<实际PR编号>`必须替换，不能原样执行。后台运行/短间隔检查以便继续汇报进度。若仓库还没有CI，明确写“未配置CI”；pending、cancelled、skipped或没有检查都不能表述为全部通过。[PR创建](https://cli.github.com/manual/gh_pr_create)；[PR检查](https://cli.github.com/manual/gh_pr_checks)。

修复时保留同一任务分支、追加commit后再次push；远端前进先fetch检查和合并，避免对共享历史rebase或强推。合并冲突需理解两侧意图，再运行受影响测试。已推送错误通常用后续修复commit或revert处理。主分支合并按项目现有授权执行，未授权时交付可审查PR并继续独立任务。

## 6. 中断恢复与完成标准

每个可工作的检查点写入任务卡：当前分支、base SHA、最新commit、已跑命令和结果、远端SHA/PR、未完成工作、下一条具体动作。不要把密钥、完整环境变量或私人存档放进仓库。

下一轮先核验远端与本地状态，寻找同任务分支和PR，再恢复；不重复创建任务、不假设上轮命令成功、不把失败测试从清单删掉。若修改未提交，先检查和保留；需要备份的未完成代码可以明确标成WIP检查点，但不得标作已验收交付。

一个阶段完成必须有：对应任务已整合、验收证据可复现、可运行版本、必要文档与兼容说明、实际远端commit、剩余问题清单。测试报告区分“已执行通过 / 已执行失败 / 环境阻塞 / 尚未执行”。自动检查衡量一致性，玩家试玩负责判断是否有选择感、故事是否连贯、普通人生是否有意义；两种证据都进入下一轮优先级。
