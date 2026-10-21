# 启动与提交

## 会话边界

外部程序只启动 Max、写脚本并读取结果。`System.Windows.Forms.Timer` 的 Tick 在 Max 主线程运行，调用 `fileIn`；Python 作业再通过 `pymxs.runtime` 操作场景。不能从外部 Python、普通工作线程或未经验证的窗口句柄直接操纵场景。

本技能在 Windows / 3ds Max 2026 上验证。启动脚本默认安装路径是 `D:\Program Files\3ds Max 2026\3dsmax.exe`；其他电脑或版本必须重新定位，并通过 `-MaxExecutable` 显式传入。可靠的 INI 种子可从该版本的用户 ENU/CHS 配置或项目中已成功启动的独立配置取得。

每台电脑都应创建自己的会话。不要从其他电脑复制或复用旧 PID、就绪令牌、队列和 `session.json`。

## 示例命令

将 `$skillRoot` 设为实际安装目录，其余路径设为当前任务。以下路径均为示例，`$taskSeedIni` 必须指向本机同版本的有效 INI 文件；先确认目录语言和版本，不要创建空配置：

```powershell
$skillRoot = Join-Path $env:USERPROFILE '.agents\skills\3dsmax-native-control'
$taskRoot = 'C:\MaxProjects\ExampleTask'
$taskSession = Join-Path $taskRoot 'session-001'
$taskMaxExe = 'C:\Program Files\Autodesk\3ds Max 2026\3dsmax.exe'
$taskSeedIni = Join-Path $env:LOCALAPPDATA 'Autodesk\3dsMax\2026 - 64bit\ENU\3dsMax.ini'
& (Join-Path $skillRoot 'scripts\start-max.ps1') `
  -SessionDirectory $taskSession `
  -MaxExecutable $taskMaxExe `
  -SeedIni $taskSeedIni `
  -OutputDirectory $taskRoot
```

启动返回 `session.json`。`ready.txt` 出现后提交只读探针：

```powershell
Copy-Item -LiteralPath (Join-Path $skillRoot 'scripts\probe-max.py') `
  -Destination (Join-Path $taskSession 'probe-max.py')
$taskJob = & (Join-Path $skillRoot 'scripts\submit-job.ps1') `
  -SessionDirectory $taskSession `
  -ScriptPath (Join-Path $taskSession 'probe-max.py') | ConvertFrom-Json
Get-Content -LiteralPath $taskJob.status_path -Encoding UTF8
Get-Content -LiteralPath (Join-Path $taskSession 'probe.json') -Raw -Encoding UTF8
```

就绪和状态检查需要轮询；文件可能尚未产生。每次工具等待不超过 60 秒，期间向用户汇报有意义的进展。状态 `running` 表示已进入作业；`success` 表示执行结束；`error` 需读该作业的错误文件。状态正在写入时短暂为空可重读。桥接解析失败可能只有 `bridge_error.txt`。作业长时间运行时先检查渲染日志，不能因超时而重复提交。

桥接在执行后若不能删除 `pending.ms`，会暂停 Timer 并报告错误，避免同一作业反复执行。恢复前先确认作业已产生哪些结果，处理本会话的队列文件；不能把已经完成的变更当成未执行而重放。

## 独立配置的范围

启动参数使用 `-silent -mi -i "会话.ini" -U MAXScript "startup.ms"`。INI 从已知可用的同版本配置复制，仅改 `[Directories]` 下 PlugCFG、Temp、Page File、AutoBackup、RenderOutput。可选复制 PlugCFG 的配置文件；不复制整套用户场景或贴图库。

此前把全部 UI、MaxData 等目录隔离后，启动曾卡住；缩小到上述目录后可以工作。不要生成空 INI 或随意替换 UI 路径。Max 可能重写 INI 编码和部分目录键，因此以运行时 `getDir #plugcfg` 为身份依据，其他实际目录按需探测。桥接关闭自动备份，并把工作目录放在本任务输出目录。

脚本为 UTF-8 BOM，桥接状态通过 .NET 明确写 UTF-8。Max 可能将 INI 改写为 UTF-16，应使用自动 BOM 检测读取。旧 `createFile` 状态文件在中文 Windows 可能是 CP936；旧桥接的兼容读取需检查编码，不能把乱码当成目录不匹配。

较新的 PowerShell 会把 JSON 的 ISO 时间自动转换成 `DateTime`。提交脚本兼容这种类型和旧版的字符串，保留启动时间精度；不要把 `DateTime` 再隐式转成区域化字符串后解析，否则会误判 PID 身份。

## 原生 API 与异常

在 Max 内：

```python
from pymxs import runtime as rt
rt.loadMaxFile(input_max, quiet=True)  # 需要读取既有场景时明确加载
print(rt.classOf(rt.renderers.current))
print([str(p) for p in rt.getPropNames(rt.renderers.current)])
```

先用 `classOf`、`getPropNames`、`isProperty` 和 `getProperty` 探测真实类。Corona 和内置 PhysicalMaterial 的属性不相同，不凭记忆批量写字段。

`python.ExecuteFile` 返回枚举 `#success / #pathError / #initError / #scriptFileError / #executeError`。附带提交脚本用 `throwOnError:false`，检查 `#success`，并通过 `python.GetLastError()` 取得 Python traceback。使用 `clearUndoBuffer:false` 避免无意清空撤销栈；较老 Max 版本不支持该参数时按原生接口调整。

本机 Max 2026 的 `python.GetLastError()` 曾把中文 traceback 返回成乱码。提交工具为每个 Python 作业生成一个小包装脚本，在 Python 中先写 UTF-8 traceback，原生异常只作后备。包装用 `runpy.run_path(..., run_name="__main__")` 执行目标，正确设置 `__file__`，临时加入目标脚本目录后恢复 `sys.path`。作业间共享导入的模块，不依赖前一作业的裸全局变量；需要持久状态时用明确的模块、文件或 Max 全局引用。

Python 的模块缓存会跨作业保留。修改已导入的辅助模块后使用 `importlib.reload(module)`，必要时明确插入本任务模块路径。不要让另一项目的同名模块被误导入。

## 停止与恢复

普通作业期间桥接 Timer 停止。渲染取消需在渲染前另设 Timer，轮询本任务取消标记并执行 `setProgressCancel true`，渲染调用传 `cancelled:&变量`。结束后 Stop 取消 Timer、移除事件并清空引用；开始下一次渲染前处理旧取消标记。

必要时关闭辅助实例：先读本会话身份、重新验证进程，再确认没有应保存的任务工作，发送 `quitMax #noPrompt` 或停止已验证的那一个 PID。`quitMax` 会退出解释器，可能不会生成作业完成标记；用预先写出的关闭报告及该 PID 退出确认。不能按进程名全杀，也不能清理无关的用户配置。

从 Python 调用 `quitMax` 时，包装脚本可能记录 `SystemExit: 0`。这次实测中该记录随后伴随测试 PID 正常退出；关闭作业以关闭前报告和进程退出为准，不把它当作需要重新提交的失败。

## 依据

- 本机已完成的原生控制链：独立 Max 启动、Timer 队列、STEP 导入、材质编辑、Corona 输出和保存后重开检查。
- [Autodesk 3ds Max 2026 Python Interface](https://help.autodesk.com/cloudhelp/2026/ENU/MAXScript-Help/files/3ds-Max-Objects-and-Interfaces/Interfaces/Core-Interfaces/Core-Interfaces-Documentation/P-Q/GUID-860B6BEB-AE3E-4F99-96E9-CCD70DF4B772.html)：ExecuteFile 返回值及异常接口。
