#requires -PSEdition Desktop
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$LabPath,
    [ValidateSet('Installed','Portable')][string]$Mode = 'Installed',
    [string]$TargetPath,
    [string[]]$AlternatePaths = @(),
    [switch]$Apply
)

$ErrorActionPreference = 'Stop'
$service = Get-CimInstance Win32_Service -Filter "Name='AnyDesk'" -ErrorAction SilentlyContinue
if (-not $TargetPath -and $Mode -eq 'Installed') {
    $TargetPath = @('C:\Program Files (x86)\AnyDesk\AnyDesk.exe','C:\Program Files\AnyDesk\AnyDesk.exe') |
        Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
}
if ($service) { $service | Select-Object Name,State,StartMode,StartName,PathName | Format-List }
if ($TargetPath -and (Test-Path -LiteralPath $TargetPath)) {
    Get-Item -LiteralPath $TargetPath | Select-Object FullName,@{n='Version';e={$_.VersionInfo.FileVersion}} | Format-List
    Get-AuthenticodeSignature -LiteralPath $TargetPath | Select-Object Status | Format-List
}
if (-not $LabPath) { Write-Host 'INCONCLUSIVO: inspeção somente leitura. Use -LabPath numa VM isolada.'; return }

. (Join-Path $PSScriptRoot 'Lab.Common.ps1')
Assert-LabVm -RequireAdmin:$Apply
$LabPath = Assert-LabPath $LabPath
$manifest = Read-LabManifest $LabPath
if ($manifest.machine -ne $env:COMPUTERNAME) { throw 'Manifesto pertence a outra VM.' }
if (-not $TargetPath -or -not (Test-Path -LiteralPath $TargetPath)) { throw 'Executável AnyDesk não encontrado. Informe -TargetPath.' }
$target = (Resolve-Path -LiteralPath $TargetPath).Path
if ([IO.Path]::GetExtension($target) -ine '.exe') { throw 'O alvo precisa ser um EXE.' }
if ((Get-Item -LiteralPath $target).VersionInfo.ProductName -notmatch 'AnyDesk') { throw 'O EXE não se identifica como AnyDesk.' }
$employee = Get-LocalUser -Name BGEmployeeLab -ErrorAction Stop
$broker = Get-LocalUser -Name BGBrokerLab -ErrorAction Stop
$paths = @($target)
foreach ($path in $AlternatePaths) {
    if (-not (Test-Path -LiteralPath $path)) { throw "Versão alternativa ausente: $path" }
    $paths += (Resolve-Path -LiteralPath $path).Path
}
$conditions = @()
foreach ($path in ($paths | Select-Object -Unique)) {
    $info = Get-AppLockerFileInformation -Path $path
    [xml]$generated = New-AppLockerPolicy -FileInformation $info -RuleType Hash -User $broker.SID.Value -Xml
    $condition = $generated.AppLockerPolicy.RuleCollection.FileHashRule.Conditions.FileHashCondition.OuterXml
    if (-not $condition) { throw "Hash AppLocker indisponível: $path" }
    $conditions += $condition
}
$conditions = $conditions | Select-Object -Unique
$allowRules = foreach ($condition in $conditions) {
    '<FileHashRule Id="' + [guid]::NewGuid() + '" Name="AnyDesk broker lab" UserOrGroupSid="' + $broker.SID.Value + '" Action="Allow"><Conditions>' + $condition + '</Conditions></FileHashRule>'
}
$policyText = '<AppLockerPolicy Version="1"><RuleCollection Type="Exe" EnforcementMode="Enabled">' +
    '<FilePathRule Id="' + [guid]::NewGuid() + '" Name="Other EXEs lab" UserOrGroupSid="S-1-1-0" Action="Allow"><Conditions><FilePathCondition Path="*" /></Conditions><Exceptions>' +
    ($conditions -join '') + '</Exceptions></FilePathRule>' + ($allowRules -join '') + '</RuleCollection></AppLockerPolicy>'
$policyFile = Join-Path $LabPath 'applocker-anydesk-lab.xml'
$policyText | Set-Content -LiteralPath $policyFile -Encoding UTF8
foreach ($path in ($paths | Select-Object -Unique)) {
    $denied = @(Test-AppLockerPolicy -XmlPolicy $policyFile -Path $path -User $employee.SID.Value)[0].PolicyDecision
    $allowed = @(Test-AppLockerPolicy -XmlPolicy $policyFile -Path $path -User $broker.SID.Value)[0].PolicyDecision
    Write-Host "Simulação: $path funcionário=$denied broker=$allowed"
    if ($denied -notlike 'Denied*' -or $allowed -notlike 'Allowed*') { throw 'A política candidata não passou na simulação.' }
}
if (-not $Apply) { Write-Host 'Política candidata salva. Nenhuma política ou serviço foi modificado.'; return }

$effective = Get-AppLockerPolicy -Effective -Xml
if ($effective -notmatch '^<AppLockerPolicy Version="1"\s*/>$') { throw 'Política AppLocker efetiva preexistente; aplicação recusada.' }
if ($manifest.policyChanged) { throw 'Laboratório já registra política modificada; restaure primeiro.' }
if (-not $PSCmdlet.ShouldProcess($env:COMPUTERNAME, 'Parar AnyDesk, aplicar AppLocker e testar execução real na VM')) { return }
$serviceBefore = Get-Service -Name AnyDesk -ErrorAction SilentlyContinue
$serviceWasRunning = $serviceBefore -and $serviceBefore.Status -eq 'Running'
$serviceStartType = if ($serviceBefore) { [string]$serviceBefore.StartType } else { $null }
$launched = New-Object 'System.Collections.Generic.List[int]'
$results = @()
$manifest.policyChanged = $true
$manifest | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $LabPath 'manifest.json') -Encoding UTF8
try {
    if ($serviceBefore) {
        if ($serviceWasRunning) { Stop-Service -Name AnyDesk -ErrorAction Stop }
        Set-Service -Name AnyDesk -StartupType Disabled -ErrorAction Stop
    }
    if (Get-Process -Name AnyDesk -ErrorAction SilentlyContinue) { throw 'Processo AnyDesk preexistente; feche-o antes do teste.' }
    Set-AppLockerPolicy -XmlPolicy $policyFile -ErrorAction Stop
    Set-Service -Name AppIDSvc -StartupType Automatic -ErrorAction Stop
    Start-Service -Name AppIDSvc -ErrorAction Stop
    Start-Sleep -Seconds 3
    $copy = Join-Path $LabPath 'AnyDesk-renamed.exe'
    Copy-Item -LiteralPath $target -Destination $copy -Force
    $testStarted = Get-Date
    foreach ($path in (@($target, $copy) + $AlternatePaths)) {
        foreach ($entry in @(@{Name='employee';User='BGEmployeeLab'}, @{Name='broker';User='BGBrokerLab'})) {
            $secure = Get-Content -LiteralPath (Join-Path $LabPath "$($entry.User).dpapi") | ConvertTo-SecureString
            $credential = [pscredential]::new("$env:COMPUTERNAME\$($entry.User)", $secure)
            $running = $false
            $detail = ''
            try {
                $process = Start-Process -FilePath $path -Credential $credential -PassThru -ErrorAction Stop
                $launched.Add($process.Id)
                Start-Sleep -Seconds 3
                $process.Refresh()
                $running = -not $process.HasExited
                $detail = "pid=$($process.Id); running=$running"
            } catch { $detail = $_.Exception.Message }
            $results += [pscustomobject]@{Path=$path; Identity=$entry.Name; RunningAfter3Seconds=$running; Detail=$detail}
            if ($entry.Name -eq 'employee' -and $running) { throw "FALHA: funcionário iniciou $path diretamente." }
        }
    }
    $results | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $LabPath 'anydesk-execution-results.json') -Encoding UTF8
    $blockedEvents = @(Get-WinEvent -FilterHashtable @{LogName='Microsoft-Windows-AppLocker/EXE and DLL';Id=8004;StartTime=$testStarted} -ErrorAction SilentlyContinue)
    $blockedEvents | Select-Object TimeCreated,Id,Message | Export-Clixml -LiteralPath (Join-Path $LabPath 'anydesk-applocker-events.xml')
    foreach ($path in (@($target, $copy) + $AlternatePaths)) {
        if (-not @($blockedEvents | Where-Object { $_.Message -match [regex]::Escape($path) }).Count) {
            throw "INCONCLUSIVO: evento AppLocker 8004 ausente para $path. Não considerar bloqueio validado."
        }
    }
    $results | Format-Table -AutoSize
    Write-Host 'Bloqueio direto observado no log. Verifique interface na sessão correta e conexão remota antes de concluir.'
} finally {
    if ($results.Count) {
        $results | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $LabPath 'anydesk-execution-results.json') -Encoding UTF8
    }
    foreach ($processId in $launched) { Stop-Process -Id $processId -Force -ErrorAction SilentlyContinue }
    Set-AppLockerPolicy -XmlPolicy (Join-Path $LabPath 'applocker-before.xml') -ErrorAction Stop
    if (-not $manifest.appIdWasRunning) { Stop-Service -Name AppIDSvc -ErrorAction SilentlyContinue }
    Set-Service -Name AppIDSvc -StartupType $manifest.appIdStartType -ErrorAction Stop
    if ($serviceBefore) {
        Set-Service -Name AnyDesk -StartupType $serviceStartType -ErrorAction Stop
        if ($serviceWasRunning) { Start-Service -Name AnyDesk -ErrorAction Stop }
    }
    $manifest.policyChanged = $false
    $manifest | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $LabPath 'manifest.json') -Encoding UTF8
}
