#requires -PSEdition Desktop
# Simulação AppLocker. Não instala políticas nem altera contas.
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Import-Module AppLocker -ErrorAction Stop
$target = Join-Path $env:WINDIR 'System32\notepad.exe'
$control = Join-Path $env:WINDIR 'System32\calc.exe'
$currentSid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$otherAccount = Get-LocalUser | Where-Object { $_.Enabled -and $_.SID.Value -ne $currentSid } | Select-Object -First 1
if (-not $otherAccount) { throw 'É necessária outra conta local habilitada para comparar as identidades.' }
$otherSid = $otherAccount.SID.Value
$targetXml = [System.Security.SecurityElement]::Escape($target)
$xml = @"
<AppLockerPolicy Version="1">
  <RuleCollection Type="Exe" EnforcementMode="Enabled">
    <FilePathRule Id="06be9f3e-1180-4898-b902-b65a1f982d02" Name="Demais programas" Description="Teste" UserOrGroupSid="S-1-1-0" Action="Allow">
      <Conditions><FilePathCondition Path="*" /></Conditions>
      <Exceptions><FilePathCondition Path="$targetXml" /></Exceptions>
    </FilePathRule>
    <FilePathRule Id="ca453555-d53f-42de-a5b8-e4644318177b" Name="Somente identidade autorizada" Description="Teste" UserOrGroupSid="$currentSid" Action="Allow">
      <Conditions><FilePathCondition Path="$targetXml" /></Conditions>
    </FilePathRule>
  </RuleCollection>
</AppLockerPolicy>
"@
$policyFile = Join-Path ([System.IO.Path]::GetTempPath()) ("blind-guardian-identity-{0}.xml" -f [guid]::NewGuid())
$copyPath = Join-Path ([System.IO.Path]::GetTempPath()) ("blind-guardian-copy-{0}.exe" -f [guid]::NewGuid())
try {
    [System.IO.File]::WriteAllText($policyFile, $xml, [System.Text.UTF8Encoding]::new($false))
    Copy-Item -LiteralPath $target -Destination $copyPath
    $authorized = @(Test-AppLockerPolicy -XmlPolicy $policyFile -Path @($target, $control) -User $currentSid)
    $other = @(Test-AppLockerPolicy -XmlPolicy $policyFile -Path @($target, $control) -User $otherSid)
    $copy = @(Test-AppLockerPolicy -XmlPolicy $policyFile -Path $copyPath -User $otherSid)
    $authorized | Select-Object @{n='Identity';e={$currentSid}},FilePath,PolicyDecision,MatchingRule | Format-Table -AutoSize
    $other | Select-Object @{n='Identity';e={$otherSid}},FilePath,PolicyDecision,MatchingRule | Format-Table -AutoSize
    $copy | Select-Object @{n='Identity';e={$otherSid}},FilePath,PolicyDecision,MatchingRule | Format-Table -AutoSize
    $a = $authorized | Where-Object FilePath -eq $target | Select-Object -First 1
    $b = $other | Where-Object FilePath -eq $target | Select-Object -First 1
    $c = $other | Where-Object FilePath -eq $control | Select-Object -First 1
    $d = $copy | Where-Object FilePath -eq $copyPath | Select-Object -First 1
    if ($a.PolicyDecision -notlike 'Allowed*' -or $b.PolicyDecision -notlike 'Denied*' -or $c.PolicyDecision -notlike 'Allowed*') {
        throw 'A política de identidades não produziu os resultados esperados.'
    }
    Write-Host 'PASS: a política sintética distingue as identidades sem regra Deny.'
    if ($d.PolicyDecision -notlike 'Allowed*') { throw "Resultado inesperado para cópia renomeada: $($d.PolicyDecision)" }
    Write-Host 'PASS: a cópia renomeada escapa da exceção por caminho; esta política é insuficiente.'
} finally {
    Remove-Item -LiteralPath $policyFile -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $copyPath -Force -ErrorAction SilentlyContinue
}
