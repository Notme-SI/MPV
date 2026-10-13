param([Parameter(Mandatory=$true)][string]$Name)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
function Quote-Argument([string]$Value) {
    $out = New-Object System.Text.StringBuilder
    [void]$out.Append('"')
    $slashes = 0
    foreach ($char in $Value.ToCharArray()) {
        if ($char -eq '\') { $slashes++; continue }
        if ($char -eq '"') {
            [void]$out.Append(('\' * (2 * $slashes + 1)))
        } else { [void]$out.Append(('\' * $slashes)) }
        [void]$out.Append($char)
        $slashes = 0
    }
    [void]$out.Append(('\' * (2 * $slashes)))
    [void]$out.Append('"')
    return $out.ToString()
}
$process = New-Object System.Diagnostics.Process
$process.StartInfo.FileName = Join-Path $PSScriptRoot 'bin\guessit.exe'
$process.StartInfo.Arguments = '-jE -- ' + (Quote-Argument $Name)
$process.StartInfo.UseShellExecute = $false
$process.StartInfo.CreateNoWindow = $true
$process.StartInfo.RedirectStandardOutput = $true
$process.StartInfo.RedirectStandardError = $true
[void]$process.Start()
$memory = New-Object System.IO.MemoryStream
$copy = $process.StandardOutput.BaseStream.CopyToAsync($memory)
$errors = $process.StandardError.ReadToEndAsync()
if (!$process.WaitForExit(10000)) { $process.Kill(); throw 'GuessIt timeout' }
$copy.Wait()
if ($process.ExitCode -ne 0) { throw 'GuessIt failed to parse this name' }
$bytes = $memory.ToArray()
try { $text = (New-Object System.Text.UTF8Encoding($false,$true)).GetString($bytes) }
catch { $text = [Text.Encoding]::Default.GetString($bytes) }
# Raw bytes are decoded before mpv can replace invalid UTF-8 with U+FFFD.
[Console]::Write($text)
$memory.Dispose()
$process.Dispose()
