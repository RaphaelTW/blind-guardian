#requires -PSEdition Desktop
[CmdletBinding()]
param([string]$CredentialFile = (Join-Path $env:APPDATA 'com.raphaeltw.blind-guardian\credentials.json'))

$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $CredentialFile)) {
    Write-Host "INCONCLUSIVO: execute o primeiro cadastro no aplicativo antes deste teste. Arquivo: $CredentialFile"
    return
}
$record = Get-Content -LiteralPath $CredentialFile -Raw | ConvertFrom-Json
if ($record.username -ne 'rakdos') { Write-Host 'Username inicial foi alterado ou está incorreto.' }
if ($record.password_hash -notmatch '^\$argon2id\$') { throw 'Hash Argon2id ausente.' }
if ($record.PSObject.Properties.Name -contains 'password') { throw 'Senha em claro encontrada no arquivo.' }
Write-Host 'PASS: credencial persistida como hash Argon2id, sem campo de senha em claro.'
Write-Host 'Teste manual pendente: senha errada 5 vezes, bloqueio por 5 minutos, login correto e autenticação no modal.'
