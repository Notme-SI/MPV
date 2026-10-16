param([int]$WaitProcessId,[string]$ResultPath,[switch]$Elevated,[switch]$Visible)
$ErrorActionPreference='Stop'
if($PSVersionTable.PSVersion.Major -eq 5) { $env:PSModulePath=[Environment]::GetEnvironmentVariable('PSModulePath','Machine') }
$playerRoot=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$exe=Join-Path $playerRoot 'mpv+.exe'
if(!(Test-Path -LiteralPath $exe)) { throw 'mpv+.exe is missing.' }
if(!$ResultPath) { $ResultPath=Join-Path $env:APPDATA 'mpv-plus\update-result.json' }
$resultDir=Split-Path -Parent $ResultPath
[IO.Directory]::CreateDirectory($resultDir)|Out-Null
$logPath=Join-Path $resultDir 'update.log'
$utf8=New-Object Text.UTF8Encoding($false)
function Log([string]$Text) { [IO.File]::AppendAllText($logPath,$Text+"`r`n",$utf8) }
function Quote([string]$Value) { return '"'+$Value.Replace('"','\"')+'"' }
try {
    if($Visible) { Write-Host 'mpv+ — обновление компонентов'; Write-Host 'Ожидание закрытия плеера...' }
    if(!$Elevated) { [IO.File]::WriteAllText($logPath,([DateTime]::Now.ToString('s')+"`r`n"),$utf8) }
    if($WaitProcessId -gt 0) { Wait-Process -Id $WaitProcessId -Timeout 120 -ErrorAction SilentlyContinue }
    if($WaitProcessId -gt 0 -and (Get-Process -Id $WaitProcessId -ErrorAction SilentlyContinue)) { throw 'Player has not exited.' }
    $writable=$true
    $probe=Join-Path $playerRoot ('.update-write-'+[guid]::NewGuid().ToString('N'))
    try { [IO.File]::WriteAllText($probe,'');Remove-Item -LiteralPath $probe } catch { $writable=$false }
    if(!$writable -and !$Elevated) {
        if($Visible) { Write-Host 'Требуются права Windows. Открывается окно подтверждения...' }
        $arguments='-NoProfile -ExecutionPolicy Bypass -File '+(Quote $PSCommandPath)+' -Elevated -ResultPath '+(Quote $ResultPath); if($Visible) { $arguments+=' -Visible' }
        $child=Start-Process powershell.exe -Verb RunAs -WindowStyle $(if($Visible){'Normal'}else{'Hidden'}) -ArgumentList $arguments -Wait -PassThru
        $child.WaitForExit()
        if($child.ExitCode -ne 0) { throw 'Update failed. See update.log.' }
    } else {
        if($Visible) { Write-Host 'Загрузка и проверка новых компонентов...' }
        $arguments='-NoProfile -ExecutionPolicy Bypass -File '+(Quote (Join-Path $PSScriptRoot 'Update-MPV.ps1'))+' -Mode Update'
        $stdout=Join-Path $resultDir ('update-'+[guid]::NewGuid().ToString('N')+'.stdout')
        $stderr=$stdout+'.errors'
        if($Visible) { Write-Host 'Установка файлов и обновление манифеста...'; $child=Start-Process powershell.exe -WindowStyle Normal -ArgumentList $arguments -PassThru } else { $child=Start-Process powershell.exe -WindowStyle Hidden -ArgumentList $arguments -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr }
        $null=$child.Handle
        $child.WaitForExit()
        foreach($output in @($stdout,$stderr)) {
            if(Test-Path -LiteralPath $output) {
                Log ([IO.File]::ReadAllText($output,$utf8))
                Remove-Item -LiteralPath $output
            }
        }
        $success=$child.ExitCode -eq 0
        [IO.File]::WriteAllText($ResultPath,(@{success=$success}|ConvertTo-Json),[Text.UTF8Encoding]::new($false))
        if(!$success) { throw 'Update failed. See update.log.' }
        if($Visible) { Write-Host 'Обновление завершено. Окно закроется через 2 секунды.'; Start-Sleep -Seconds 2 }
    }
} catch {
    [IO.File]::WriteAllText($ResultPath,(@{success=$false}|ConvertTo-Json),[Text.UTF8Encoding]::new($false))
    Log ($_.ToString())
    if($Elevated) { exit 1 }
} finally {
    # The non-elevated coordinator restarts the player with the user's privileges.
    if(!$Elevated) { Start-Process -FilePath $exe -WorkingDirectory $playerRoot -WindowStyle Hidden }
}
