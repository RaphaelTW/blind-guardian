param(
    [Parameter(Mandatory)][string]$ApplicationId,
    [Parameter(Mandatory)][string]$GuardianExe,
    [string]$BackupRoot
)
$ErrorActionPreference = 'Stop'
if (-not $BackupRoot) { $BackupRoot = Join-Path $env:APPDATA 'com.raphaeltw.blind-guardian\shortcut-backups' }
$idBytes = [Text.Encoding]::UTF8.GetBytes($ApplicationId)
$idHash = [BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash($idBytes)).Replace('-', '')
$manifestPath = Join-Path $BackupRoot "$idHash.json"
if (-not (Test-Path -LiteralPath $manifestPath)) { return }
$shell = New-Object -ComObject WScript.Shell
$entries = @(Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json)
foreach ($entry in $entries) {
    if (-not (Test-Path -LiteralPath $entry.Shortcut)) { continue }
    $current = $shell.CreateShortcut($entry.Shortcut)
    if ($current.TargetPath -ine $GuardianExe) { throw "Atalho alterado por outro programa: $($entry.Shortcut)" }
    if ($entry.Backup) {
        Copy-Item -LiteralPath $entry.Backup -Destination $entry.Shortcut -Force -ErrorAction Stop
    } else {
        Remove-Item -LiteralPath $entry.Shortcut -ErrorAction Stop
    }
}
Remove-Item -LiteralPath $manifestPath -ErrorAction Stop
foreach ($entry in $entries) { if ($entry.Backup) { Remove-Item -LiteralPath $entry.Backup -ErrorAction SilentlyContinue } }
