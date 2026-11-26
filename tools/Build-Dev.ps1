#requires -PSEdition Desktop
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
foreach ($command in @('cargo.exe','node.exe','npm.cmd')) {
    if (-not (Get-Command $command -ErrorAction SilentlyContinue)) { throw "Ferramenta ausente: $command" }
}
Push-Location $root
try {
    cargo build --manifest-path .\service\Cargo.toml --release
    if ($LASTEXITCODE -ne 0) { throw 'Falha ao compilar o serviço.' }
    $resources = Join-Path $root 'src-tauri\resources'
    New-Item -ItemType Directory -Path $resources -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $root 'service\target\release\blind-guardian-service.exe') -Destination (Join-Path $resources 'blind-guardian-service.exe') -Force
    npm.cmd ci
    if ($LASTEXITCODE -ne 0) { throw 'Falha ao instalar dependências JS.' }
    npm.cmd run tauri -- build --bundles nsis
    if ($LASTEXITCODE -ne 0) { throw 'Falha ao compilar o instalador Tauri NSIS.' }
    $setup = Get-ChildItem -LiteralPath (Join-Path $root 'src-tauri\target\release\bundle\nsis') -Filter '*.exe' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $setup) { throw 'Instalador NSIS não encontrado.' }
    $out = Join-Path $root 'artifacts'
    New-Item -ItemType Directory -Path $out -Force | Out-Null
    Copy-Item -LiteralPath $setup.FullName -Destination (Join-Path $out 'BlindGuardian_0.1.0-alpha_x64_Setup.exe') -Force
    Write-Host "Instalador: $(Join-Path $out 'BlindGuardian_0.1.0-alpha_x64_Setup.exe')"
} finally { Pop-Location }
