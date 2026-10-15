param([Parameter(Mandatory=$true)][string]$Directory)
$ErrorActionPreference='Stop'
[IO.Directory]::CreateDirectory($Directory) | Out-Null
