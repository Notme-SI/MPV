param([int]$WaitProcessId,[string]$ResultPath,[switch]$Elevated)
$ErrorActionPreference='Stop'
if($PSVersionTable.PSVersion.Major -eq 5) { $env:PSModulePath=[Environment]::GetEnvironmentVariable('PSModulePath','Machine') }
$playerRoot=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$exe=Join-Path $playerRoot 'mpv+.exe'
if(!(Test-Path -LiteralPath $exe)) { throw 'mpv+.exe is missing.' }
if(!$ResultPath) { $ResultPath=Join-Path $env:LOCALAPPDATA 'mpv-plus\update-result.json' }
$resultDir=Split-Path -Parent $ResultPath
[IO.Directory]::CreateDirectory($resultDir)|Out-Null
$logPath=Join-Path $resultDir 'update.log'
function Quote([string]$Value) { return '"'+$Value.Replace('"','\"')+'"' }
try {
    if($WaitProcessId -gt 0) { Wait-Process -Id $WaitProcessId -Timeout 120 -ErrorAction SilentlyContinue }
    if($WaitProcessId -gt 0 -and (Get-Process -Id $WaitProcessId -ErrorAction SilentlyContinue)) { throw 'Player has not exited.' }
    $writable=$true
    $probe=Join-Path $playerRoot ('.update-write-'+[guid]::NewGuid().ToString('N'))
    try { [IO.File]::WriteAllText($probe,'');Remove-Item -LiteralPath $probe } catch { $writable=$false }
    if(!$writable -and !$Elevated) {
        $arguments='-NoProfile -ExecutionPolicy Bypass -File '+(Quote $PSCommandPath)+' -Elevated -ResultPath '+(Quote $ResultPath)
        $child=Start-Process powershell.exe -Verb RunAs -WindowStyle Hidden -ArgumentList $arguments -Wait -PassThru
        if($child.ExitCode -ne 0) { throw 'Update failed. See update.log.' }
    } else {
        $arguments='-NoProfile -ExecutionPolicy Bypass -File '+(Quote (Join-Path $PSScriptRoot 'Update-MPV.ps1'))+' -Mode Update'
        $child=Start-Process powershell.exe -WindowStyle Hidden -ArgumentList $arguments -Wait -PassThru -RedirectStandardOutput $logPath -RedirectStandardError ($logPath+'.errors')
        $success=$child.ExitCode -eq 0
        [IO.File]::WriteAllText($ResultPath,(@{success=$success}|ConvertTo-Json),[Text.UTF8Encoding]::new($false))
        if(!$success) { throw 'Update failed. See update.log.' }
    }
} catch {
    [IO.File]::WriteAllText($ResultPath,(@{success=$false}|ConvertTo-Json),[Text.UTF8Encoding]::new($false))
    [IO.File]::AppendAllText($logPath,"`r`n"+$_.Exception.Message)
    if($Elevated) { exit 1 }
} finally {
    # The non-elevated coordinator restarts the player with the user's privileges.
    if(!$Elevated) { Start-Process -FilePath $exe -WorkingDirectory $playerRoot -WindowStyle Hidden }
}
