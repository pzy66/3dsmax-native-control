[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$SessionDirectory,
    [Parameter(Mandatory=$true)][string]$SeedIni,
    [string]$SeedPlugCfg,
    [string]$MaxExecutable = 'D:\Program Files\3ds Max 2026\3dsmax.exe',
    [string]$OutputDirectory,
    [switch]$PrepareOnly
)
$ErrorActionPreference = 'Stop'

function Read-IniText([string]$TaskPath) {
    # StreamReader detects UTF-16/UTF-8 BOM. Older BOM-less Chinese INIs may be CP936.
    try { return [IO.File]::ReadAllText($TaskPath, [Text.UTF8Encoding]::new($false, $true)) }
    catch [Text.DecoderFallbackException] {
        return [IO.File]::ReadAllText($TaskPath, [Text.Encoding]::GetEncoding(936))
    }
}

function Set-DirectoryKeys([string]$TaskText, [System.Collections.IDictionary]$TaskValues) {
    $taskPattern = '(?ims)(^\[Directories\][^\r\n]*\r?\n)(.*?)(?=^\[|\z)'
    $taskSection = [regex]::Match($TaskText, $taskPattern)
    if (!$taskSection.Success) { throw 'Seed INI has no [Directories] section.' }
    $taskBody = $taskSection.Groups[2].Value
    foreach ($taskKey in $TaskValues.Keys) {
        $taskLinePattern = '(?im)^' + [regex]::Escape($taskKey) + '\s*=[^\r\n]*'
        $taskReplacement = $taskKey + '=' + $TaskValues[$taskKey]
        if ([regex]::IsMatch($taskBody, $taskLinePattern)) {
            $taskBody = [regex]::Replace($taskBody, $taskLinePattern, [Text.RegularExpressions.MatchEvaluator]{ param($m) $taskReplacement })
        } else {
            $taskBody = $taskBody.TrimEnd([char[]]"`r`n") + "`r`n" + $taskReplacement + "`r`n"
        }
    }
    return $TaskText.Substring(0, $taskSection.Index) + $taskSection.Groups[1].Value + $taskBody + $TaskText.Substring($taskSection.Index + $taskSection.Length)
}

$taskSession = [IO.Path]::GetFullPath($SessionDirectory).TrimEnd('\')
$taskSeed = (Resolve-Path -LiteralPath $SeedIni).ProviderPath
$taskExe = (Resolve-Path -LiteralPath $MaxExecutable).ProviderPath
if ([IO.Path]::GetFileName($taskExe) -ine '3dsmax.exe') { throw 'MaxExecutable must be 3dsmax.exe.' }
if ($taskSession.Contains('"')) { throw 'Unsupported quote in session path.' }
if (Test-Path -LiteralPath $taskSession) {
    if (!(Test-Path -LiteralPath $taskSession -PathType Container)) { throw 'SessionDirectory is not a directory.' }
    if ((Get-Item -LiteralPath $taskSession).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'SessionDirectory may not be a reparse point.' }
    if (@(Get-ChildItem -LiteralPath $taskSession -Force).Count -ne 0) { throw 'Use a new empty session directory; do not overwrite an existing session.' }
}
if (!$OutputDirectory) { $OutputDirectory = Split-Path -Parent $taskSession }
$taskOutput = [IO.Path]::GetFullPath($OutputDirectory)
$taskPlugCfg = Join-Path $taskSession 'private_plugcfg'
$taskIni = Join-Path $taskSession 'private_Max.ini'
$taskToken = [guid]::NewGuid().ToString('N')
$taskUtf8 = [Text.UTF8Encoding]::new($true)
$taskValues = [ordered]@{
    'PlugCFG' = $taskPlugCfg
    'Temp' = (Join-Path $taskSession 'temp')
    'Page File' = (Join-Path $taskSession 'temp')
    'AutoBackup' = (Join-Path $taskSession 'autoback')
    'RenderOutput' = $taskOutput
}
# Check the template and INI before creating directories.
$taskIniText = Set-DirectoryKeys (Read-IniText $taskSeed) $taskValues
$taskBridgeText = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'bridge.ms'))
$taskBridgeText = $taskBridgeText.Replace('@@SESSION_DIRECTORY@@', $taskSession).Replace('@@SESSION_TOKEN@@', $taskToken)
foreach ($taskFolder in @($taskSession, $taskPlugCfg, (Join-Path $taskSession 'jobs')) + @($taskValues.Values)) {
    New-Item -ItemType Directory -Path $taskFolder -Force | Out-Null
}
if ($SeedPlugCfg) {
    $taskSourceCfg = (Resolve-Path -LiteralPath $SeedPlugCfg).ProviderPath.TrimEnd('\')
    if (!(Test-Path -LiteralPath $taskSourceCfg -PathType Container)) { throw 'SeedPlugCfg must be a directory.' }
    foreach ($taskConfig in Get-ChildItem -LiteralPath $taskSourceCfg -Recurse -File) {
        if ($taskConfig.Extension -in @('.ini', '.cfg', '.conf', '.config', '.xml', '.cuix')) {
            $taskRelative = $taskConfig.FullName.Substring($taskSourceCfg.Length).TrimStart('\')
            $taskDestination = Join-Path $taskPlugCfg $taskRelative
            New-Item -ItemType Directory -Path (Split-Path -Parent $taskDestination) -Force | Out-Null
            Copy-Item -LiteralPath $taskConfig.FullName -Destination $taskDestination
        }
    }
}
[IO.File]::WriteAllText($taskIni, $taskIniText, $taskUtf8)
$taskStartup = Join-Path $taskSession 'startup.ms'
[IO.File]::WriteAllText($taskStartup, $taskBridgeText, $taskUtf8)
$taskArguments = '-silent -mi -i "' + $taskIni + '" -U MAXScript "' + $taskStartup + '"'
$taskManifest = [ordered]@{
    session_directory = $taskSession
    token = $taskToken
    executable = $taskExe
    plugcfg = $taskPlugCfg
    seed_ini = $taskSeed
    ini = $taskIni
    startup = $taskStartup
    arguments = $taskArguments
    output_directory = $taskOutput
    prepared_at = [DateTimeOffset]::UtcNow.ToString('o')
    existing_pids = @(Get-Process -Name 3dsmax -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Id)
}
[IO.File]::WriteAllText((Join-Path $taskSession 'prepared.json'), ($taskManifest | ConvertTo-Json -Depth 4), $taskUtf8)
if ($PrepareOnly) { $taskManifest | ConvertTo-Json -Depth 4; return }
$taskProcess = Start-Process -FilePath $taskExe -ArgumentList $taskArguments -WorkingDirectory $taskOutput -WindowStyle Hidden -PassThru
$taskProcess.Refresh()
$taskManifest['pid'] = $taskProcess.Id
$taskManifest['process_start_utc'] = $taskProcess.StartTime.ToUniversalTime().ToString('o')
$taskManifest['launched_at'] = [DateTimeOffset]::UtcNow.ToString('o')
$taskManifest['window_style'] = 'Hidden'
[IO.File]::WriteAllText((Join-Path $taskSession 'session.json'), ($taskManifest | ConvertTo-Json -Depth 4), $taskUtf8)
$taskManifest | ConvertTo-Json -Depth 4
