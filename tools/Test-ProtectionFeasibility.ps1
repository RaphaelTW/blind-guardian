# Executa somente uma simulação de política. Não instala nem altera o AppLocker.
#requires -PSEdition Desktop
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Import-Module AppLocker -ErrorAction Stop

$target = Join-Path $env:WINDIR 'System32\notepad.exe'
$other = Join-Path $env:WINDIR 'System32\calc.exe'
if (-not (Test-Path -LiteralPath $target) -or -not (Test-Path -LiteralPath $other)) {
    throw 'Arquivos de teste do Windows não encontrados.'
}

$targetXml = [System.Security.SecurityElement]::Escape($target)
$xml = @"
<AppLockerPolicy Version="1">
  <RuleCollection Type="Exe" EnforcementMode="Enabled">
    <FilePathRule Id="dbefcae3-f98f-4a4d-89dd-1efb31831af0" Name="Permitir outros" Description="Teste" UserOrGroupSid="S-1-1-0" Action="Allow">
      <Conditions><FilePathCondition Path="*" /></Conditions>
    </FilePathRule>
    <FilePathRule Id="820cf405-bca0-4ef2-9239-c88a2c24546f" Name="Bloquear alvo" Description="Teste" UserOrGroupSid="S-1-1-0" Action="Deny">
      <Conditions><FilePathCondition Path="$targetXml" /></Conditions>
    </FilePathRule>
    <FilePathRule Id="a3096747-a617-4c36-bf20-293f10ee8665" Name="Tentar liberar alvo" Description="Teste" UserOrGroupSid="S-1-1-0" Action="Allow">
      <Conditions><FilePathCondition Path="$targetXml" /></Conditions>
    </FilePathRule>
  </RuleCollection>
</AppLockerPolicy>
"@

$policyFile = Join-Path ([System.IO.Path]::GetTempPath()) ("blind-guardian-applocker-{0}.xml" -f [guid]::NewGuid())
try {
    [System.IO.File]::WriteAllText($policyFile, $xml, [System.Text.UTF8Encoding]::new($false))
    $results = @(Test-AppLockerPolicy -XmlPolicy $policyFile -Path @($target, $other) -User 'S-1-1-0')
    $results | Select-Object FilePath, PolicyDecision, MatchingRule | Format-Table -AutoSize

    $targetResult = $results | Where-Object { $_.FilePath -eq $target } | Select-Object -First 1
    $otherResult = $results | Where-Object { $_.FilePath -eq $other } | Select-Object -First 1
    if (-not $targetResult -or -not $otherResult) { throw 'Resultado incompleto do Test-AppLockerPolicy.' }
    if ($targetResult.PolicyDecision -notlike 'Denied*') { throw "O alvo não foi bloqueado: $($targetResult.PolicyDecision)" }
    if ($otherResult.PolicyDecision -notlike 'Allowed*') { throw "O programa de controle não foi liberado: $($otherResult.PolicyDecision)" }
    Write-Host 'PASS: a regra Deny prevalece sobre Allow para o mesmo EXE e usuário.'
} finally {
    Remove-Item -LiteralPath $policyFile -Force -ErrorAction SilentlyContinue
}
