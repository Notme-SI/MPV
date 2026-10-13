param([string]$ExecutablePath,[string]$ShortcutPath,[switch]$RebuildCache)
$ErrorActionPreference='Stop'
if(!$ExecutablePath) { $ExecutablePath=Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'mpv.exe' }
$ExecutablePath=(Resolve-Path -LiteralPath $ExecutablePath).Path
$iconPath=Join-Path (Split-Path -Parent $ExecutablePath) 'portable_config\assets\mpv-monochrome.ico'
if(!(Test-Path -LiteralPath $iconPath)) { throw 'Icon file not found' }
# A content-based name invalidates the per-path Windows shortcut icon cache.
$iconHash=(Get-FileHash -LiteralPath $iconPath -Algorithm SHA256).Hash.Substring(0,12).ToLowerInvariant()
$shellIcon=Join-Path (Split-Path -Parent $iconPath) ('mpv-shell-'+$iconHash+'.ico')
if(!(Test-Path -LiteralPath $shellIcon) -or (Get-FileHash -LiteralPath $shellIcon -Algorithm SHA256).Hash -ne (Get-FileHash -LiteralPath $iconPath -Algorithm SHA256).Hash) {
    Copy-Item -LiteralPath $iconPath -Destination $shellIcon -Force
}
if(-not ('MpvBuild.ShellIcons' -as [type])) {
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace MpvBuild {
public static class ShellIcons {
 [DllImport("shell32.dll",CharSet=CharSet.Unicode)]
 public static extern void SHChangeNotify(uint id,uint flags,string item1,IntPtr item2);
}
}
'@
}
$shortcuts=@()
if($ShortcutPath) { $shortcuts+=@($ShortcutPath) }
else {
    foreach($dir in @([Environment]::GetFolderPath('Programs'),[Environment]::GetFolderPath('DesktopDirectory'),
                      (Join-Path $env:APPDATA 'Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar'))) {
        if(Test-Path -LiteralPath $dir) {
            $shortcuts+=@(Get-ChildItem -LiteralPath $dir -Filter '*.lnk' -File | Select-Object -ExpandProperty FullName)
        }
    }
}
$ws=New-Object -ComObject WScript.Shell
foreach($path in $shortcuts) {
    if(!(Test-Path -LiteralPath $path)) { continue }
    $link=$ws.CreateShortcut($path)
    if(![StringComparer]::OrdinalIgnoreCase.Equals($link.TargetPath,$ExecutablePath)) { continue }
    $link.IconLocation=$shellIcon+',0'
    $link.Save()
    [MpvBuild.ShellIcons]::SHChangeNotify(0x2000,0x1005,$path,[IntPtr]::Zero)
}
foreach($path in @($ExecutablePath,$iconPath,$shellIcon)) {
    [MpvBuild.ShellIcons]::SHChangeNotify(0x2000,0x1005,$path,[IntPtr]::Zero)
}
[MpvBuild.ShellIcons]::SHChangeNotify(0x08000000,0,[string]$null,[IntPtr]::Zero)
if($RebuildCache) {
    $refresh=Join-Path $env:SystemRoot 'System32\ie4uinit.exe'
    if(Test-Path -LiteralPath $refresh) {
        $process=Start-Process -FilePath $refresh -ArgumentList '-show' -WindowStyle Hidden -PassThru
        [void]$process.WaitForExit(10000)
    }
}
