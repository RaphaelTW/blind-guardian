param(
    [Parameter(Mandatory)][string]$ApplicationId,
    [Parameter(Mandatory)][string]$ApplicationName,
    [Parameter(Mandatory)][string]$GuardianExe,
    [Parameter(Mandatory)][string]$AppExe,
    [string[]]$SearchRoots,
    [string]$BackupRoot
)
$ErrorActionPreference = 'Stop'
$shell = New-Object -ComObject WScript.Shell
$safeName = [regex]::Replace($ApplicationName, '[\/:*?"<>|]', '_').Trim()
if (-not $safeName) { throw 'Nome do aplicativo inválido.' }
if (-not $SearchRoots) {
    $SearchRoots = @(
        [Environment]::GetFolderPath('Desktop'),
        [Environment]::GetFolderPath('CommonDesktopDirectory'),
        [Environment]::GetFolderPath('Programs'),
        [Environment]::GetFolderPath('CommonPrograms')
    )
}
if (-not $BackupRoot) { $BackupRoot = Join-Path $env:APPDATA 'com.raphaeltw.blind-guardian\shortcut-backups' }
New-Item -ItemType Directory -Path $BackupRoot -Force | Out-Null
$idBytes = [Text.Encoding]::UTF8.GetBytes($ApplicationId)
$idHash = [BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash($idBytes)).Replace('-', '')
$manifestPath = Join-Path $BackupRoot "$idHash.json"
$entries = if (Test-Path -LiteralPath $manifestPath) { @(Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json) } else { @() }
$target = [IO.Path]::GetFullPath($AppExe)
$changed = New-Object 'System.Collections.Generic.List[object]'
try {
    foreach ($root in ($SearchRoots | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -Unique)) {
        foreach ($file in (Get-ChildItem -LiteralPath $root -Filter '*.lnk' -File -Recurse -ErrorAction Stop)) {
            if ($entries | Where-Object { $_.Shortcut -ieq $file.FullName }) { continue }
            $link = $shell.CreateShortcut($file.FullName)
            if (-not $link.TargetPath) { continue }
            try { $linkTarget = [IO.Path]::GetFullPath($link.TargetPath) } catch { continue }
            if ($linkTarget -ine $target) { continue }
            $backup = Join-Path $BackupRoot "$([guid]::NewGuid()).lnk.bak"
            Copy-Item -LiteralPath $file.FullName -Destination $backup -ErrorAction Stop
            try {
                $link.TargetPath = $GuardianExe
                $link.Arguments = '--launch-id "' + $ApplicationId.Replace('"', '') + '"'
                $link.IconLocation = "$AppExe,0"
                $link.Description = "Abrir $ApplicationName com autorização do Blind Guardian"
                $link.Save()
            } catch {
                Copy-Item -LiteralPath $backup -Destination $file.FullName -Force
                throw
            }
            $changed.Add([pscustomobject]@{ Shortcut = $file.FullName; Backup = $backup })
        }
    }
    $entries = @($entries) + @($changed.ToArray())
    if ($entries.Count -eq 0) {
        $directory = Join-Path ([Environment]::GetFolderPath('Programs')) 'Blind Guardian'
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
        $path = Join-Path $directory "$safeName.lnk"
        $link = $shell.CreateShortcut($path)
        $link.TargetPath = $GuardianExe
        $link.Arguments = '--launch-id "' + $ApplicationId.Replace('"', '') + '"'
        $link.IconLocation = "$AppExe,0"
        $link.Description = "Abrir $ApplicationName com autorização do Blind Guardian"
        $link.Save()
        $entries = @([pscustomobject]@{ Shortcut = $path; Backup = $null })
    }
    ConvertTo-Json -InputObject @($entries) -Depth 3 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
    Write-Output "Atalhos gerenciados: $($entries.Count)"
} catch {
    foreach ($entry in $changed) { Copy-Item -LiteralPath $entry.Backup -Destination $entry.Shortcut -Force -ErrorAction SilentlyContinue }
    throw
}
