---
name: 3dsmax-native-control
description: "在 Windows 上通过 MAXScript 文件队列与 pymxs 原生控制 Autodesk 3ds Max（3dmax）：检查或修改 MAX 场景、导入 STEP/CAD、分配真实材质、配置 Corona、输出渲染并重开验证。适用于用户要求实际操作 3ds Max 或沿用脚本控制方法；不用于 Blender、纯图片生成或仅讲解建模。"
---

# 3ds Max 原生脚本控制

用外部 PowerShell 管理文件和进程；让 3ds Max 自己在主线程执行 MAXScript，再通过 `python.ExecuteFile` 运行 `pymxs`。外部 Python 只做数据、贴图和结果检查，不能直接导入 `pymxs` 控制 Max。

## 先确定控制对象

1. 读取项目已有脚本、输入文件和交付要求。找到 Max 可执行文件、可用的 `Max.ini` 和渲染器，不把本技能示例中的安装路径、Corona、分辨率或采样数强加给其他任务。
2. 检查现有进程和任务的 `session.json`。只有 PID、可执行路径、进程启动时间、就绪令牌和实际 PlugCFG 均匹配，才复用已有脚本实例。新聊天必须重新检查，不能沿用旧 PID。
3. 没有可验证的脚本实例时，在当前项目下建立独立会话目录，用附带的 `scripts/start-max.ps1` 启动隐藏的辅助实例。保留用户其他 Max 会话；不向未知或有未保存工作的窗口注入脚本。
4. 先运行 `scripts/probe-max.py`，读取实际场景、版本和渲染器，再写修改脚本。任务输出和脚本留在同一个项目子文件夹。

启动、提交和进程识别的完整命令见 [control-workflow.md](references/control-workflow.md)。不要把命令中的中文项目路径复制成其他项目的固定依赖。

## 执行与验收

- 将 `.py` 或 `.ms` 作业放在会话目录内，用 `scripts/submit-job.ps1` 原子提交。队列一次只接收一个作业；Max 的 Timer 在作业期间停止，完成后恢复。
- 等待该作业的 `jobs/<id>.status.txt`，并读取错误文件及作业报告。`pending.ms` 消失、进程存在、渲染窗口关闭均不能证明任务成功。
- Python 脚本修改后需要重新执行；若复用导入的模块，用 `importlib.reload` 更新缓存。MAXScript 中 `python.ExecuteFile` 成功返回 `#success`，不是布尔值。
- 作业自己给出可检查的结果，例如节点/材质快照、导入统计、保存路径、渲染日志和图像检查。脚本完成标记只表示执行没有抛异常。
- 明确加载输入场景，并保存到用户授权的输出位置。不得覆盖参考场景或源 CAD。需要保留结构时，前后比较节点全名与层级、变换、顶点/三角形和材质分配；跨重开不用节点 handle 当身份。
- 保存后重开输出 MAX 验证，再交付最终 MAX、渲染图及依赖贴图。不要只验证内存里的场景。

处理 STEP、材质、Corona 和真实 Alpha 时，按需读 [cad-corona.md](references/cad-corona.md)。那里记录了已遇到的接口差异和视觉陷阱。

## 故障处理

- 就绪文件缺失时先看进程和本会话的 `bridge_error.txt`，不要反复启动新实例。INI 编码和过度隔离配置是优先排查项。
- Python 异常读本作业 `.error.txt`；解析失败读桥接错误。修复原因后才提交下一份作业。
- 长渲染先使用协作取消与 `cancelled:` 参数。普通队列在渲染期间不能执行取消命令；需要提前安装取消 Timer。强制停止仅限身份已经重新验证、确由本任务启动的辅助实例。
- 不使用 `Stop-Process -Name 3dsmax`，不把暂时无响应认定为进程死亡，也不重置或关闭用户其他场景。

## 附带工具

- `scripts/start-max.ps1`：复制选定配置，生成 UTF-8 桥接脚本，创建独立 PlugCFG，记录会话身份；`-PrepareOnly` 可只准备文件。
- `scripts/bridge.ms`：由启动脚本填入本会话路径与令牌，不能直接以未替换模板启动。
- `scripts/submit-job.ps1`：验证实例身份，提交 `.py/.ms`，输出可轮询的作业状态路径。
- `scripts/probe-max.py`：在 Max 内执行，只读检查并写出 `probe.json`；不加载、保存或修改用户场景。
