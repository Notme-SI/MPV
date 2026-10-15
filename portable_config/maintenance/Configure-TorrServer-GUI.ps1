param([Parameter(Mandatory=$true)][string]$ConfigPath,[ValidateSet('ru','en')][string]$Language='ru')
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Configure-TorrServer.ps1') -Library
Add-Type -AssemblyName System.Windows.Forms
$form=New-Object Windows.Forms.Form
$form.Text='TorrServer'; $form.Width=450; $form.Height=255; $form.StartPosition='CenterScreen'
$labels=if($Language -eq 'en'){@('Server URL','Login','Password','Save','Saved. Restart the player.')}else{@('Адрес сервера','Логин','Пароль','Сохранить','Сохранено. Перезапустите плеер.')}
$inputs=@()
foreach($row in @(@($labels[0],20),@($labels[1],65),@($labels[2],110))) {
    $label=New-Object Windows.Forms.Label; $label.Text=$row[0]; $label.SetBounds(15,$row[1],100,25)
    $box=New-Object Windows.Forms.TextBox; $box.SetBounds(120,$row[1],290,25)
    if($row[0] -eq $labels[2]) {$box.UseSystemPasswordChar=$true}
    $form.Controls.Add($label); $form.Controls.Add($box); $inputs+=,$box
}
if(Test-Path -LiteralPath $ConfigPath) {
    $values=@{}; Get-Content -LiteralPath $ConfigPath -Encoding UTF8 | ForEach-Object {if($_ -match '^([^#=]+)=(.*)$') {$values[$Matches[1].Trim()]=$Matches[2].Trim()}}
    try {
        $uri=[Uri]($values.scheme+'://'+$values.host+':'+$values.port)
        $inputs[0].Text=$uri.GetLeftPart([UriPartial]::Authority) -replace '//[^/@]+@','//'
        $parts=$uri.UserInfo -split ':',2
        if($parts.Count -gt 0){$inputs[1].Text=[Uri]::UnescapeDataString($parts[0])}
        if($parts.Count -gt 1){$inputs[2].Text=[Uri]::UnescapeDataString($parts[1])}
    } catch {}
}
$save=New-Object Windows.Forms.Button; $save.Text=$labels[3]; $save.SetBounds(310,160,100,30)
$save.Add_Click({
    try {
        $content=Get-TorrServerConfig $inputs[0].Text $inputs[1].Text $inputs[2].Text
        [IO.Directory]::CreateDirectory((Split-Path -Parent $ConfigPath))|Out-Null
        [IO.File]::WriteAllText($ConfigPath,$content,[Text.UTF8Encoding]::new($false))
        [Windows.Forms.MessageBox]::Show($labels[4],'TorrServer')|Out-Null
        $form.Close()
    } catch {[Windows.Forms.MessageBox]::Show($_.Exception.Message,'TorrServer')|Out-Null}
})
$form.Controls.Add($save);$form.AcceptButton=$save
[void]$form.ShowDialog()
