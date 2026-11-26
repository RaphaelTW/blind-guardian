#requires -PSEdition Desktop
[CmdletBinding()]
param([string]$LabPath)

$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'Test-CreateProcessAsUser.ps1')
if (-not $LabPath) {
    Write-Host 'INCONCLUSIVO: a execução acima usou o token do usuário atual. Forneça -LabPath para checar a VM.'
    return
}
. (Join-Path $PSScriptRoot 'Lab.Common.ps1')
Assert-LabVm
$manifest = Read-LabManifest (Assert-LabPath $LabPath)
if ($manifest.machine -ne $env:COMPUTERNAME) { throw 'Manifesto pertence a outra VM.' }
if (-not (Get-LocalUser -Name BGBrokerLab -ErrorAction SilentlyContinue)) { throw 'Conta do broker ausente.' }
Write-Host 'INCONCLUSIVO: falta broker Rust com token da conta dedicada, sessão interativa, IPC autenticado e Job Object. Não há teste de autorização completa.'
