# 3ds Max Native Control

面向 Codex 的 Windows 本机技能，通过 MAXScript 文件队列和 3ds Max 内置 `pymxs` 控制原生场景。

支持场景检查、STEP/CAD 导入、材质编辑、Corona 渲染，以及保存后重开验证。技能包含脚本与操作说明，不包含 3ds Max、Corona、模型或贴图。

## 环境要求

- Windows 和已安装、激活的 Autodesk 3ds Max；当前工作流验证于 3ds Max 2026，其他版本需重新检查接口。
- PowerShell 和 Codex；通过 Git 同步时需要 Git。
- 使用 Corona 时，需要本机已安装并授权对应版本的 Corona。
- `pymxs` 作业在 3ds Max 内运行，无需在外部 Python 中安装 `pymxs`。

## 安装到另一台电脑

在 PowerShell 中执行，目标目录应当尚不存在：

```powershell
$taskSkills = Join-Path $env:USERPROFILE '.agents\skills'
New-Item -ItemType Directory -Path $taskSkills -Force | Out-Null
git clone https://github.com/pzy66/3dsmax-native-control.git (Join-Path $taskSkills '3dsmax-native-control')
```

也可以下载仓库 ZIP，将包含 `SKILL.md` 的整个目录放到 `%USERPROFILE%\.agents\skills\3dsmax-native-control`。如果 Codex 未显示该技能，重启后再检查。

在 Codex 中输入：

> 使用 $3dsmax-native-control，先检查这台电脑的 3ds Max 安装位置、配置文件和渲染器，再创建独立脚本会话并运行只读探针。

启动脚本的默认安装路径仅是示例。首次运行时须指定本机实际的 `-MaxExecutable`、同版本有效的 `-SeedIni` 和新的 `-SessionDirectory`。具体命令见 [控制流程](references/control-workflow.md)。

## 更新与两台电脑同步

获取 GitHub 上的最新版本：

```powershell
$taskSkill = Join-Path $env:USERPROFILE '.agents\skills\3dsmax-native-control'
git -C $taskSkill pull --ff-only
```

修改技能后，在有仓库写权限的电脑提交并推送，再到另一台电脑拉取：

```powershell
git -C $taskSkill status
git -C $taskSkill add SKILL.md README.md agents references scripts .gitignore
git -C $taskSkill commit -m 'Update native control workflow'
git -C $taskSkill push
```

推送需要本机自己的 GitHub 身份验证；Codex 的 GitHub 插件连接与本机 Git 凭据分别管理。同步前应先检查待提交内容，项目文件和会话输出放在仓库外。

## 文件结构

```text
SKILL.md                         技能入口与验收规则
agents/openai.yaml               Codex 展示信息
scripts/start-max.ps1            创建并启动独立辅助实例
scripts/bridge.ms                主线程队列模板
scripts/submit-job.ps1           校验会话身份并提交作业
scripts/probe-max.py             在 Max 中运行的只读探针
references/control-workflow.md   启动、提交与故障处理
references/cad-corona.md         CAD、材质、Corona 与 Alpha 验收
```

## 会话与结果

脚本会核对 PID、可执行路径、进程启动时间、会话令牌与实际 PlugCFG。每台电脑都要创建本机独立会话，不应同步旧 `session.json`、队列或用户配置。不要向未经验证的用户窗口注入脚本，也不要按进程名关闭所有 Max 实例。

作业状态成功表示脚本执行结束，场景与渲染结果仍须按任务要求检查；最终 MAX 应保存后重开验证。参见 [技能说明](SKILL.md)。

Codex 技能安装目录参考：[官方技能文档](https://learn.chatgpt.com/docs/build-skills)。
