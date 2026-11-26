# Utilitários compartilhados. Alterações de segurança são permitidas apenas em VM isolada.
function Assert-LabVm {
    param([switch]$RequireAdmin)
    $system = Get-CimInstance Win32_ComputerSystem
    $identity = "$($system.Manufacturer) $($system.Model)"
    if ($identity -notmatch 'Virtual|VMware|QEMU|KVM|Parallels|Hyper-V|Xen') {
        throw "Máquina não identificada como VM ($identity). Nenhuma alteração foi feita."
    }
    if ((Get-CimInstance Win32_ComputerSystem).PartOfDomain) {
        throw 'VM associada a domínio. Use laboratório isolado, sem políticas corporativas.'
    }
    if ($RequireAdmin) {
        $principal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
        if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
            throw 'Abra o Windows PowerShell 5.1 como administrador dentro da VM.'
        }
    }
}

function Read-LabManifest {
    param([Parameter(Mandatory)][string]$LabPath)
    $manifestPath = Join-Path $LabPath 'manifest.json'
    if (-not (Test-Path -LiteralPath $manifestPath)) { throw "Manifesto de laboratório ausente: $manifestPath" }
    Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
}

function Assert-LabPath {
    param([Parameter(Mandatory)][string]$LabPath)
    $full = [IO.Path]::GetFullPath($LabPath)
    if ([IO.Path]::GetPathRoot($full) -eq $full -or $full.Length -lt 12) { throw 'Caminho de laboratório inseguro.' }
    return $full
}
