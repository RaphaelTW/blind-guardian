#requires -PSEdition Desktop
# Simulação somente leitura da execução; copia o binário para %TEMP%, sem iniciá-lo.
[CmdletBinding()]
param([string]$Executable = 'C:\Program Files (x86)\AnyDesk\AnyDesk.exe')

$ErrorActionPreference = 'Stop'
Import-Module AppLocker
if (-not (Test-Path -LiteralPath $Executable)) { throw "EXE não encontrado: $Executable" }
$currentSid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$otherAccount = Get-LocalUser | Where-Object { $_.Enabled -and $_.SID.Value -ne $currentSid } | Select-Object -First 1
if (-not $otherAccount) { throw 'É necessária outra conta local habilitada.' }
$otherSid = $otherAccount.SID.Value

$info = Get-AppLockerFileInformation -Path $Executable
[xml]$generated = New-AppLockerPolicy -FileInformation $info -RuleType Hash -User $currentSid -Xml
$hashCondition = $generated.AppLockerPolicy.RuleCollection.FileHashRule.Conditions.FileHashCondition.OuterXml
$policyText = @"
<AppLockerPolicy Version="1">
  <RuleCollection Type="Exe" EnforcementMode="Enabled">
    <FilePathRule Id="ac664d1e-8f6d-46bc-88b7-55542e36a99e" Name="Demais executáveis" Description="Teste" UserOrGroupSid="S-1-1-0" Action="Allow">
      <Conditions><FilePathCondition Path="*" /></Conditions>
      <Exceptions>$hashCondition</Exceptions>
    </FilePathRule>
    <FileHashRule Id="141cc78e-312b-47f1-8637-16aa386db892" Name="AnyDesk autorizado" Description="Teste" UserOrGroupSid="$currentSid" Action="Allow">
      <Conditions>$hashCondition</Conditions>
    </FileHashRule>
  </RuleCollection>
</AppLockerPolicy>
"@
$policyFile = Join-Path ([System.IO.Path]::GetTempPath()) ("blind-guardian-anydesk-{0}.xml" -f [guid]::NewGuid())
$copyPath = Join-Path ([System.IO.Path]::GetTempPath()) ("blind-guardian-renamed-{0}.exe" -f [guid]::NewGuid())
try {
    [System.IO.File]::WriteAllText($policyFile, $policyText, [System.Text.UTF8Encoding]::new($false))
    Copy-Item -LiteralPath $Executable -Destination $copyPath
    $authorized = @(Test-AppLockerPolicy -XmlPolicy $policyFile -Path @($Executable, $copyPath) -User $currentSid)
    $employee = @(Test-AppLockerPolicy -XmlPolicy $policyFile -Path @($Executable, $copyPath) -User $otherSid)
    $authorized | Select-Object @{n='Identity';e={$currentSid}},FilePath,PolicyDecision,MatchingRule | Format-Table -AutoSize
    $employee | Select-Object @{n='Identity';e={$otherSid}},FilePath,PolicyDecision,MatchingRule | Format-Table -AutoSize
    if ($authorized.Count -ne 2 -or $employee.Count -ne 2 -or
        @($authorized | Where-Object { $_.PolicyDecision -like 'Allowed*' }).Count -ne 2 -or
        @($employee | Where-Object { $_.PolicyDecision -like 'Denied*' }).Count -ne 2) {
        throw 'Decisões inesperadas para as duas identidades.'
    }
    Write-Host 'PASS: nesta versão do EXE, o hash diferencia as duas identidades inclusive para uma cópia renomeada.'
} finally {
    Remove-Item -LiteralPath $policyFile -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $copyPath -Force -ErrorAction SilentlyContinue
}
