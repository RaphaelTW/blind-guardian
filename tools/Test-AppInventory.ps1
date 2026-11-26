#requires -PSEdition Desktop
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$locations = @(
    @{Hive=[Microsoft.Win32.Registry]::LocalMachine; Path='SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'},
    @{Hive=[Microsoft.Win32.Registry]::LocalMachine; Path='SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'},
    @{Hive=[Microsoft.Win32.Registry]::CurrentUser; Path='SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'},
    @{Hive=[Microsoft.Win32.Registry]::CurrentUser; Path='SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'}
)
$entries = foreach ($location in $locations) {
    $key = $location.Hive.OpenSubKey($location.Path)
    if (-not $key) { continue }
    foreach ($name in $key.GetSubKeyNames()) {
        $sub = $key.OpenSubKey($name)
        if (-not $sub) { continue }
        $display = [string]$sub.GetValue('DisplayName','')
        if (-not $display.Trim() -or $sub.GetValue('SystemComponent',0) -eq 1) { continue }
        [pscustomobject]@{Name=$display;Version=[string]$sub.GetValue('DisplayVersion','');Publisher=[string]$sub.GetValue('Publisher','');DisplayIcon=[string]$sub.GetValue('DisplayIcon','')}
    }
}
$unique = @($entries | Sort-Object Name,Version,Publisher -Unique)
$withIcons = @($unique | Where-Object { $_.DisplayIcon })
Write-Host "Entradas reais no Registro: $($entries.Count); deduplicadas: $($unique.Count); com DisplayIcon: $($withIcons.Count)"
$unique | Select-Object -First 20 Name,Version,Publisher | Format-Table -AutoSize
Write-Host 'Compare manualmente esses nomes com a aba Programas instalados. Este script não usa Win32_Product.'
