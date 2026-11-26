#requires -PSEdition Desktop
[CmdletBinding(SupportsShouldProcess)]
param([Parameter(Mandatory)][string]$LabPath)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Lab.Common.ps1')
Assert-LabVm -RequireAdmin
$LabPath = Assert-LabPath $LabPath
if (Test-Path -LiteralPath (Join-Path $LabPath 'manifest.json')) { throw 'Laboratório já preparado; restaure antes de repetir.' }
if (-not $PSCmdlet.ShouldProcess($LabPath, 'Criar usuários locais de teste e salvar estado anterior')) { return }

New-Item -ItemType Directory -Path $LabPath -Force | Out-Null
$policyPath = Join-Path $LabPath 'applocker-before.xml'
Get-AppLockerPolicy -Local -Xml | Set-Content -LiteralPath $policyPath -Encoding UTF8
$appId = Get-Service -Name AppIDSvc
$anydesk = Get-Service -Name AnyDesk -ErrorAction SilentlyContinue
$existing = @('BGEmployeeLab','BGBrokerLab') | Where-Object { Get-LocalUser -Name $_ -ErrorAction SilentlyContinue }
if ($existing.Count -gt 0) { throw "Contas de laboratório já existentes: $($existing -join ', ')" }

$created = @()
try {
    foreach ($name in @('BGEmployeeLab','BGBrokerLab')) {
        $bytes = New-Object byte[] 32
        [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
        $plain = [Convert]::ToBase64String($bytes) + '!aA9'
        $secure = ConvertTo-SecureString $plain -AsPlainText -Force
        New-LocalUser -Name $name -Password $secure -Description 'Blind Guardian laboratory only' | Out-Null
        $created += $name
        $secure | ConvertFrom-SecureString | Set-Content -LiteralPath (Join-Path $LabPath "$name.dpapi") -Encoding ASCII
        $plain = $null
    }
    $manifest = [pscustomobject]@{
        createdAt = (Get-Date).ToUniversalTime().ToString('o')
        machine = $env:COMPUTERNAME
        users = $created
        appIdStartType = [string]$appId.StartType
        appIdWasRunning = $appId.Status -eq 'Running'
        anyDeskStartType = if ($anydesk) { [string]$anydesk.StartType } else { $null }
        anyDeskWasRunning = if ($anydesk) { $anydesk.Status -eq 'Running' } else { $null }
        policyChanged = $false
    }
    $manifest | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $LabPath 'manifest.json') -Encoding UTF8
    Write-Host "Laboratório preparado: $LabPath"
} catch {
    foreach ($name in $created) { Remove-LocalUser -Name $name -ErrorAction SilentlyContinue }
    throw
}
