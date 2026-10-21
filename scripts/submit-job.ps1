[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$SessionDirectory,
    [Parameter(Mandatory=$true)][string]$ScriptPath
)
$ErrorActionPreference = 'Stop'
$taskSession = (Resolve-Path -LiteralPath $SessionDirectory).ProviderPath.TrimEnd('\')
$taskManifest = Get-Content -LiteralPath (Join-Path $taskSession 'session.json') -Raw -Encoding UTF8 | ConvertFrom-Json
if ([IO.Path]::GetFullPath($taskManifest.session_directory).TrimEnd('\') -ine $taskSession) { throw 'Session manifest path mismatch.' }
if ([IO.Path]::GetFileName($taskManifest.executable) -ine '3dsmax.exe') { throw 'Manifest is not for 3dsmax.exe.' }
$taskProcess = Get-Process -Id ([int]$taskManifest.pid) -ErrorAction Stop
if ($taskProcess.Path -ine $taskManifest.executable) { throw 'PID belongs to a different executable.' }
$taskExpectedStart = if ($taskManifest.process_start_utc -is [DateTime]) {
    $taskManifest.process_start_utc.ToUniversalTime()
} elseif ($taskManifest.process_start_utc -is [DateTimeOffset]) {
    $taskManifest.process_start_utc.UtcDateTime
} else {
    [DateTimeOffset]::Parse($taskManifest.process_start_utc, [Globalization.CultureInfo]::InvariantCulture).UtcDateTime
}
if ($taskProcess.StartTime.ToUniversalTime().Ticks -ne $taskExpectedStart.Ticks) { throw 'Process start time mismatch; possible reused PID.' }
$taskReadyPath = Join-Path $taskSession 'ready.txt'
if (!(Test-Path -LiteralPath $taskReadyPath)) { throw 'Max is not ready; inspect its process and bridge_error.txt before retrying.' }
$taskReady = [IO.File]::ReadAllText($taskReadyPath)
if ($taskReady -notmatch ('(?m)^PID=' + $taskManifest.pid + '\r?$')) { throw 'Ready PID mismatch.' }
if ($taskReady -notmatch ('(?m)^TOKEN=' + [regex]::Escape($taskManifest.token) + '\r?$')) { throw 'Ready token mismatch.' }
$taskCfgMatch = [regex]::Match($taskReady, '(?m)^PLUGCFG=(.*)\r?$')
if (!$taskCfgMatch.Success -or [IO.Path]::GetFullPath($taskCfgMatch.Groups[1].Value.Trim()).TrimEnd('\') -ine [IO.Path]::GetFullPath($taskManifest.plugcfg).TrimEnd('\')) { throw 'Max uses a different PlugCFG.' }
if (Test-Path -LiteralPath (Join-Path $taskSession 'pending.ms')) { throw 'The session already has pending or running work.' }
$taskScript = (Resolve-Path -LiteralPath $ScriptPath).ProviderPath
if (!$taskScript.StartsWith($taskSession + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Copy the script into this session directory before submitting.' }
if (!(Test-Path -LiteralPath $taskScript -PathType Leaf)) { throw 'ScriptPath must be a file.' }
$taskExtension = [IO.Path]::GetExtension($taskScript).ToLowerInvariant()
if ($taskExtension -notin @('.py', '.ms')) { throw 'Only .py and .ms scripts are supported.' }
# FileInfo has Directory; DirectoryInfo has Parent. Reject redirected session paths.
$taskScriptItem = Get-Item -LiteralPath $taskScript
if (($taskScriptItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Script may not be a reparse point.' }
$taskCheck = $taskScriptItem.Directory
while ($taskCheck -and ($taskCheck.FullName -ieq $taskSession -or $taskCheck.FullName.StartsWith($taskSession + '\', [StringComparison]::OrdinalIgnoreCase))) {
    if (($taskCheck.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Session paths may not be reparse points.' }
    $taskCheck = $taskCheck.Parent
}
$taskJobId = [guid]::NewGuid().ToString('N')
$taskBase = Join-Path (Join-Path $taskSession 'jobs') $taskJobId
$taskStatus = $taskBase + '.status.txt'
$taskError = $taskBase + '.error.txt'
$taskStaging = $taskBase + '.queue.tmp'
if ($taskExtension -eq '.py') {
    # Max 2026 GetLastError may mojibake Chinese traceback text. Write it in Python first.
    $taskPythonWrapper = $taskBase + '.runner.py'
    $taskPythonTemplate = @'
import runpy
import sys
import traceback
from pathlib import Path
_task_script = Path(@@SCRIPT_LITERAL@@)
_task_error = Path(@@ERROR_LITERAL@@)
_task_paths = sys.path[:]
try:
    sys.path.insert(0, str(_task_script.parent))
    runpy.run_path(str(_task_script), run_name="__main__")
except BaseException:
    _task_error.write_text(traceback.format_exc(), encoding="utf-8")
    raise
finally:
    sys.path[:] = _task_paths
'@
    # JSON string escaping is also valid for these Python string literals, not shell quoting.
    $taskPythonText = $taskPythonTemplate.Replace('@@SCRIPT_LITERAL@@', ($taskScript | ConvertTo-Json -Compress)).Replace('@@ERROR_LITERAL@@', ($taskError | ConvertTo-Json -Compress))
    [IO.File]::WriteAllText($taskPythonWrapper, $taskPythonText, [Text.UTF8Encoding]::new($true))
    $taskAction = 'local taskPythonResult = python.ExecuteFile @"' + $taskPythonWrapper + '" throwOnError:false clearUndoBuffer:false' + "`n" +
        '        if taskPythonResult != #success do throw ("python.ExecuteFile returned " + (taskPythonResult as string) + "\n" + python.GetLastError())'
} else { $taskAction = 'fileIn @"' + $taskScript + '"' }
$taskQueue = @'
(
    local taskOk = true
    codexNativeWriteUtf8 @"@@STATUS@@" "running"
    try (
        @@ACTION@@
    ) catch (
        taskOk = false
        if not doesFileExist @"@@ERROR@@" do codexNativeWriteUtf8 @"@@ERROR@@" (getCurrentException() as string)
    )
    codexNativeWriteUtf8 @"@@STATUS@@" (if taskOk then "success" else "error")
)
'@
$taskQueue = $taskQueue.Replace('@@STATUS@@', $taskStatus).Replace('@@ERROR@@', $taskError).Replace('@@ACTION@@', $taskAction)
$taskUtf8 = [Text.UTF8Encoding]::new($true)
[IO.File]::WriteAllText($taskStaging, $taskQueue, $taskUtf8)
$taskJob = [ordered]@{ job_id=$taskJobId; pid=$taskProcess.Id; script=$taskScript; status_path=$taskStatus; error_path=$taskError; queued_at=[DateTimeOffset]::UtcNow.ToString('o') }
[IO.File]::WriteAllText(($taskBase + '.json'), ($taskJob | ConvertTo-Json), $taskUtf8)
try {
    # File.Move fails if a concurrent writer created pending.ms; it never overwrites.
    [IO.File]::Move($taskStaging, (Join-Path $taskSession 'pending.ms'))
} catch {
    if (Test-Path -LiteralPath $taskStaging) { Remove-Item -LiteralPath $taskStaging }
    throw
}
$taskJob | ConvertTo-Json
