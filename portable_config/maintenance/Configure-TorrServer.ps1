param([switch]$Library)
$ErrorActionPreference='Stop'
function Get-TorrServerConfig([string]$Address,[string]$Login,[string]$Password) {
    $uri=$null
    if(![Uri]::TryCreate($Address.Trim(),[UriKind]::Absolute,[ref]$uri) -or $uri.Scheme -notin @('http','https') -or !$uri.Host) {
        throw 'Укажите полный адрес с http:// или https://'
    }
    if($uri.AbsolutePath -ne '/' -or $uri.Query -or $uri.Fragment -or $uri.UserInfo) {
        throw 'Нужен адрес сервера без пути и данных входа. Логин и пароль вводятся отдельно.'
    }
    $authority=$uri.Host
    if($uri.HostNameType -eq [UriHostNameType]::IPv6 -and !$authority.StartsWith('[')) { $authority='['+$authority+']' }
    if($Login) { $authority=[Uri]::EscapeDataString($Login)+':'+[Uri]::EscapeDataString($Password)+'@'+$authority }
    elseif($Password) { throw 'Для пароля также нужен логин.' }
    return "scheme=$($uri.Scheme)`n"+"host=$authority`n"+"port=$($uri.Port)`nuse_edl=yes`n"
}
if($Library) { return }
Write-Host 'Настройка TorrServer для MPV'
Write-Host 'Введите тот же адрес сервера, который используется в Lampa.'
Write-Host 'Пример локального: http://127.0.0.1:8090'
Write-Host 'Для сервера без :порта используются 80 (http) или 443 (https).'
$address=Read-Host 'Адрес сервера'
$login=Read-Host 'Логин (Enter, если не требуется)'
$password=''
if($login) {
    $secure=Read-Host 'Пароль' -AsSecureString
    $ptr=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try { $password=[Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
}
$text=Get-TorrServerConfig $address $login $password
$config=Split-Path -Parent $PSScriptRoot
$path=Join-Path $config 'script-opts\torrserver-loader.conf'
[IO.File]::WriteAllText($path,$text,(New-Object Text.UTF8Encoding($false)))
$password=$null; $text=$null
Write-Host 'Сохранено. Перезапустите mpv. Для списка на сервере нажмите Ctrl+T.'
Write-Host 'После ввода учётных данных эта папка является вашей личной копией.'
