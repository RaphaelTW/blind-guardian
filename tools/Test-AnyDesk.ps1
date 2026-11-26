#requires -PSEdition Desktop
[CmdletBinding()]
param([string]$LabPath)

$ErrorActionPreference = 'Stop'
$service = Get-CimInstance Win32_Service -Filter "Name='AnyDesk'" -ErrorAction SilentlyContinue
$paths = @('C:\Program Files (x86)\AnyDesk\AnyDesk.exe','C:\Program Files\AnyDesk\AnyDesk.exe')
$binary = $paths | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if ($service) { $service | Select-Object Name,State,StartMode,StartName,PathName | Format-List }
if ($binary) { Get-Item -LiteralPath $binary | Select-Object FullName,@{n='Version';e={$_.VersionInfo.FileVersion}} | Format-List; Get-AuthenticodeSignature -LiteralPath $binary | Select-Object Status | Format-List }
if (-not $LabPath) {
    Write-Host 'INCONCLUSIVO: inventário somente leitura. Testes de conexão exigem VM e máquina remota controlada.'
    return
}
. (Join-Path $PSScriptRoot 'Lab.Common.ps1')
Assert-LabVm
$manifest = Read-LabManifest (Assert-LabPath $LabPath)
if ($manifest.machine -ne $env:COMPUTERNAME) { throw 'Manifesto pertence a outra VM.' }
Write-Host 'Na VM, registre conexão remota nos estados: bloqueado, autorizado, janela fechada, reiniciado.'
Write-Host 'Repita em snapshot separado com AnyDesk instalado e portátil, cópia renomeada e outra versão.'
Write-Host 'INCONCLUSIVO até captura de eventos AppLocker, processo/serviço e resultado da conexão externa.'
