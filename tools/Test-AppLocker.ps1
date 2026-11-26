#requires -PSEdition Desktop
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][string]$LabPath,
    [string]$TargetPath = "$env:WINDIR\System32\whoami.exe",
    [switch]$Apply
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Lab.Common.ps1')
Assert-LabVm -RequireAdmin
$LabPath = Assert-LabPath $LabPath
$manifest = Read-LabManifest $LabPath
if ($manifest.machine -ne $env:COMPUTERNAME) { throw 'Manifesto pertence a outra VM.' }
if (-not (Test-Path -LiteralPath $TargetPath)) { throw "EXE ausente: $TargetPath" }
$target = (Resolve-Path -LiteralPath $TargetPath).Path
$employee = Get-LocalUser -Name BGEmployeeLab -ErrorAction Stop
$broker = Get-LocalUser -Name BGBrokerLab -ErrorAction Stop
$info = Get-AppLockerFileInformation -Path $target
[xml]$generated = New-AppLockerPolicy -FileInformation $info -RuleType Hash -User $broker.SID.Value -Xml
$hash = $generated.AppLockerPolicy.RuleCollection.FileHashRule.Conditions.FileHashCondition.OuterXml
$policyText = @"
<AppLockerPolicy Version="1"><RuleCollection Type="Exe" EnforcementMode="Enabled">
<FilePathRule Id="bd954694-fb33-44f8-a0bf-89653e1fab4c" Name="Demais EXEs no laboratório" Description="Blind Guardian Lab" UserOrGroupSid="S-1-1-0" Action="Allow"><Conditions><FilePathCondition Path="*" /></Conditions><Exceptions>$hash</Exceptions></FilePathRule>
<FileHashRule Id="08fbaf33-4821-4f15-8a7d-0fdc2b89411c" Name="Apenas broker" Description="Blind Guardian Lab" UserOrGroupSid="$($broker.SID.Value)" Action="Allow"><Conditions>$hash</Conditions></FileHashRule>
</RuleCollection></AppLockerPolicy>
"@
$policyFile = Join-Path $LabPath 'applocker-lab.xml'
$policyText | Set-Content -LiteralPath $policyFile -Encoding UTF8
$simEmployee = @(Test-AppLockerPolicy -XmlPolicy $policyFile -Path $target -User $employee.SID.Value)
$simBroker = @(Test-AppLockerPolicy -XmlPolicy $policyFile -Path $target -User $broker.SID.Value)
Write-Host "Simulação: funcionário=$($simEmployee[0].PolicyDecision), broker=$($simBroker[0].PolicyDecision)"
if ($simEmployee[0].PolicyDecision -notlike 'Denied*' -or $simBroker[0].PolicyDecision -notlike 'Allowed*') { throw 'Simulação não aprovada.' }
if (-not $Apply) { Write-Host 'Somente simulação. Use -Apply exclusivamente na VM para o teste real.'; return }
if ([IO.Path]::GetFileName($target) -ne 'whoami.exe') { throw 'Teste real automático limitado a whoami.exe. AnyDesk exige ensaio manual controlado.' }
$effective = Get-AppLockerPolicy -Effective -Xml
if ($effective -notmatch '^<AppLockerPolicy Version="1"\s*/>$') { throw 'Política efetiva preexistente: aplicação automática recusada.' }
if (-not $PSCmdlet.ShouldProcess($env:COMPUTERNAME, 'Aplicar AppLocker de laboratório e iniciar AppIDSvc temporariamente')) { return }

$manifest.policyChanged = $true
$manifest | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $LabPath 'manifest.json') -Encoding UTF8
try {
    Set-AppLockerPolicy -XmlPolicy $policyFile -ErrorAction Stop
    Set-Service AppIDSvc -StartupType Automatic
    Start-Service AppIDSvc -ErrorAction Stop
    Start-Sleep -Seconds 3
    $results = @()
    foreach ($entry in @(@{Name='employee';User='BGEmployeeLab';ShouldRun=$false}, @{Name='broker';User='BGBrokerLab';ShouldRun=$true})) {
        $secure = Get-Content -LiteralPath (Join-Path $LabPath "$($entry.User).dpapi") | ConvertTo-SecureString
        $credential = [pscredential]::new("$env:COMPUTERNAME\$($entry.User)", $secure)
        $ran = $false
        $detail = ''
        try {
            $process = Start-Process -FilePath $target -Credential $credential -PassThru -Wait -WindowStyle Hidden -ErrorAction Stop
            $ran = $process.ExitCode -eq 0
            $detail = "exit=$($process.ExitCode)"
        } catch { $detail = $_.Exception.Message }
        $results += [pscustomobject]@{Identity=$entry.Name; Ran=$ran; Expected=$entry.ShouldRun; Detail=$detail}
    }
    $results | Format-Table -AutoSize
    if (@($results | Where-Object { $_.Ran -ne $_.Expected }).Count -gt 0) { throw 'Teste de execução real não correspondeu à política.' }
    Write-Host 'PASS: execução direta bloqueada para funcionário e permitida ao broker na VM.'
} finally {
    $backup = Join-Path $LabPath 'applocker-before.xml'
    Set-AppLockerPolicy -XmlPolicy $backup -ErrorAction Stop
    if (-not $manifest.appIdWasRunning) { Stop-Service AppIDSvc -ErrorAction SilentlyContinue }
    Set-Service AppIDSvc -StartupType $manifest.appIdStartType
    $manifest.policyChanged = $false
    $manifest | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $LabPath 'manifest.json') -Encoding UTF8
}
