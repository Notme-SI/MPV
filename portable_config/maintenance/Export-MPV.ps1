param([string]$OutputDirectory=(Join-Path $env:USERPROFILE 'Downloads'))
$ErrorActionPreference='Stop'
$config=Split-Path -Parent $PSScriptRoot
$manifest=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$parent=Split-Path -Parent $config
$player=if(Test-Path -LiteralPath (Join-Path $parent 'mpv+.exe')) {$parent} else {[string]$manifest.playerRoot}
$stamp=Get-Date -Format 'yyyyMMdd-HHmmss'
$work=Join-Path $env:TEMP ('mpv-export-'+[guid]::NewGuid().ToString('N'))
$bundle=Join-Path $work 'mpv+-Portable'
[IO.Directory]::CreateDirectory($bundle)|Out-Null
foreach($name in @('mpv+.exe','compat','ffmpeg.exe','7z','doc','mpv','LICENSES','SOURCES','VERSION.txt','SOURCES.txt','ПРОЧТИ МЕНЯ.txt','Настроить TorrServer.cmd')) {
    $source=Join-Path $player $name
    if(Test-Path -LiteralPath $source) { Copy-Item -LiteralPath $source -Destination $bundle -Recurse }
}
if(!(Test-Path -LiteralPath (Join-Path $bundle 'mpv+.exe'))) { throw 'mpv+.exe не найден.' }
$portableConfig=Join-Path $bundle 'portable_config'
[IO.Directory]::CreateDirectory($portableConfig)|Out-Null
foreach($file in Get-ChildItem -LiteralPath $config -Recurse -File -Force) {
    $rel=$file.FullName.Substring($config.Length+1)
    if($rel -match '(^|\\)(watch_later|watch_history)(\\|$)' -or $rel -match '\.bak$') { continue }
    $dest=Join-Path $portableConfig $rel
    [IO.Directory]::CreateDirectory((Split-Path -Parent $dest))|Out-Null
    Copy-Item -LiteralPath $file.FullName -Destination $dest
}
$utf8=New-Object Text.UTF8Encoding($true)
$cmd=@{
    'Обновить mpv+.cmd'='Update-MPV.ps1" -Mode Interactive';
    'Сохранить бэкап.cmd'='Export-MPV.ps1"'
}
foreach($name in $cmd.Keys) {
    $text="@echo off`r`npowershell.exe -NoProfile -ExecutionPolicy Bypass -File `"%~dp0portable_config\maintenance\"+$cmd[$name]+"`r`npause`r`n"
    [IO.File]::WriteAllText((Join-Path $bundle $name),$text,[Text.Encoding]::ASCII)
}
if(!(Test-Path -LiteralPath (Join-Path $bundle 'ПРОЧТИ МЕНЯ.txt'))) { Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'README.txt') -Destination (Join-Path $bundle 'ПРОЧТИ МЕНЯ.txt') }
[IO.Directory]::CreateDirectory($OutputDirectory)|Out-Null
$zip=Join-Path $OutputDirectory ("mpv+-Portable-$stamp.zip")
Add-Type -AssemblyName System.IO.Compression.FileSystem
[IO.Compression.ZipFile]::CreateFromDirectory($work,$zip,[IO.Compression.CompressionLevel]::Optimal,$false)
Write-Host "Сборка сохранена: $zip"
Write-Host 'Архив содержит настройки и данные входа TorrServer. Храните его как личную резервную копию.'
