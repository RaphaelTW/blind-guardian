#requires -PSEdition Desktop
[CmdletBinding(SupportsShouldProcess)]
param([Parameter(Mandatory)][string]$LabPath)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Lab.Common.ps1')
Assert-LabVm -RequireAdmin
$LabPath = Assert-LabPath $LabPath
$manifest = Read-LabManifest $LabPath
if ($manifest.machine -ne $env:COMPUTERNAME) { throw 'Manifesto pertence a outra máquina.' }
if (-not $PSCmdlet.ShouldProcess($LabPath, 'Restaurar AppLocker/AppIDSvc e remover somente contas de laboratório')) { return }

$policyPath = Join-Path $LabPath 'applocker-before.xml'
if (-not (Test-Path -LiteralPath $policyPath)) { throw 'Backup AppLocker ausente; restauração automática interrompida.' }
if ($manifest.policyChanged) {
    Set-AppLockerPolicy -XmlPolicy $policyPath -ErrorAction Stop
}
if (-not $manifest.appIdWasRunning) { Stop-Service -Name AppIDSvc -ErrorAction SilentlyContinue }
Set-Service -Name AppIDSvc -StartupType $manifest.appIdStartType -ErrorAction Stop
foreach ($name in $manifest.users) {
    $account = Get-LocalUser -Name $name -ErrorAction SilentlyContinue
    if ($account -and $account.Description -eq 'Blind Guardian laboratory only') {
        Remove-LocalUser -Name $name
    }
}
Write-Host 'Política e contas de laboratório restauradas. O diretório de evidências foi preservado.'
