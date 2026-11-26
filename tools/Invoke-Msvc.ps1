#requires -PSEdition Desktop
[CmdletBinding()]
param(
    [Parameter(Mandatory, Position=0)][string]$Executable,
    [Parameter(ValueFromRemainingArguments=$true)][string[]]$Arguments
)
$ErrorActionPreference = 'Stop'
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
if (-not (Test-Path -LiteralPath $vswhere)) { throw 'vswhere.exe não encontrado.' }
$installation = & $vswhere -latest -prerelease -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (-not $installation) { throw 'Visual Studio com MSVC x64 não encontrado.' }
$vcvars = Join-Path $installation 'VC\Auxiliary\Build\vcvars64.bat'
if (-not (Test-Path -LiteralPath $vcvars)) { throw "vcvars64.bat não encontrado: $vcvars" }
$env:PATH = "$(Split-Path -Parent $vswhere);$env:PATH"
$variables = & cmd.exe /d /c "`"$vcvars`" >nul && set"
if ($LASTEXITCODE -ne 0) { throw 'Falha ao configurar MSVC x64.' }
foreach ($line in $variables) {
    $separator = $line.IndexOf('=', 1)
    if ($separator -gt 0) {
        [Environment]::SetEnvironmentVariable($line.Substring(0, $separator), $line.Substring($separator + 1), 'Process')
    }
}
$link = Get-Command link.exe -ErrorAction Stop
if ($link.Source -notlike "$installation*") { throw "link.exe incorreto: $($link.Source)" }
Write-Host "MSVC x64: $($link.Source)"
& $Executable @Arguments
exit $LASTEXITCODE
