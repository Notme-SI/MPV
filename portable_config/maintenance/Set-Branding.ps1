param([string]$PlayerRoot,[string]$GroupPath)
$ErrorActionPreference='Stop'
if(!$PlayerRoot) { $PlayerRoot=Split-Path -Parent (Split-Path -Parent $PSScriptRoot) }
$PlayerRoot=(Resolve-Path -LiteralPath $PlayerRoot).Path
$exe=Join-Path $PlayerRoot 'mpv+.exe'
$oldUpdate=Join-Path $PlayerRoot 'Обновить MPV.cmd'
$newUpdate=Join-Path $PlayerRoot 'Обновить mpv+.cmd'
$programs=[Environment]::GetFolderPath('Programs')
if(!$GroupPath) { $GroupPath=Join-Path $programs 'mpv+' }
$GroupPath=[IO.Path]::GetFullPath($GroupPath)
$roots=@($programs,[Environment]::GetFolderPath('DesktopDirectory'),
    (Join-Path $env:APPDATA 'Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar'))
$links=@()
foreach($dir in $roots) {
    if(Test-Path -LiteralPath $dir) {
        $links+=@(Get-ChildItem -LiteralPath $dir -Filter '*.lnk' -File -Recurse)
    }
}
$shell=New-Object -ComObject WScript.Shell
$updated=0
foreach($file in $links) {
    $link=$shell.CreateShortcut($file.FullName)
    $launcher=[StringComparer]::OrdinalIgnoreCase.Equals($link.TargetPath,$exe) -or [StringComparer]::OrdinalIgnoreCase.Equals($link.TargetPath,(Join-Path $PlayerRoot 'mpv.exe'))
    if($launcher) { $link.TargetPath=$exe; $link.WorkingDirectory=$PlayerRoot }
    $updater=[StringComparer]::OrdinalIgnoreCase.Equals($link.TargetPath,$oldUpdate)
    $configure=[StringComparer]::OrdinalIgnoreCase.Equals($link.TargetPath,(Join-Path $PlayerRoot 'Настроить TorrServer.cmd'))
    if(!$launcher -and !$updater -and !$configure) { continue }
    if($updater) { $link.TargetPath=$newUpdate }
    $link.Description=if($launcher) {'mpv+'} elseif($configure) {'TorrServer'} else {'Обновить mpv+'}
    $link.Save()
    $leaf=if($launcher) {'mpv+.lnk'} elseif($configure) {$file.Name} elseif($file.BaseName -eq 'Update MPV') {'Update mpv+.lnk'} else {'Обновить mpv+.lnk'}
    $parent=$file.DirectoryName
    $legacyGroup=Join-Path $programs 'MPV'
    if([StringComparer]::OrdinalIgnoreCase.Equals($parent,$legacyGroup)) { $parent=$GroupPath }
    $destination=[IO.Path]::GetFullPath((Join-Path $parent $leaf))
    $allowed=$false
    foreach($dir in @($roots)+@($GroupPath)) {
        if($destination.StartsWith([IO.Path]::GetFullPath($dir).TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)) { $allowed=$true }
    }
    if(!$allowed) { throw 'Shortcut destination is outside the selected folders.' }
    if(![StringComparer]::OrdinalIgnoreCase.Equals($destination,$file.FullName)) {
        if(Test-Path -LiteralPath $destination) {
            $existing=$shell.CreateShortcut($destination)
            if([StringComparer]::OrdinalIgnoreCase.Equals($existing.TargetPath,$link.TargetPath)) {
                Remove-Item -LiteralPath $file.FullName
            }
        } else {
            [IO.Directory]::CreateDirectory($parent)|Out-Null
            Move-Item -LiteralPath $file.FullName -Destination $destination
        }
    }
    $updated++
}
# Remove only an identical obsolete command launcher, never unrelated user files.
if((Test-Path -LiteralPath $oldUpdate) -and (Test-Path -LiteralPath $newUpdate)) {
    if([Convert]::ToBase64String([IO.File]::ReadAllBytes($oldUpdate)) -ceq [Convert]::ToBase64String([IO.File]::ReadAllBytes($newUpdate))) { Remove-Item -LiteralPath $oldUpdate }
}
$legacyGroup=Join-Path $programs 'MPV'
if((Test-Path -LiteralPath $legacyGroup) -and !(Get-ChildItem -LiteralPath $legacyGroup -Force | Select-Object -First 1)) {
    Remove-Item -LiteralPath $legacyGroup
}
Write-Host "mpv+: обновлено ярлыков: $updated"
