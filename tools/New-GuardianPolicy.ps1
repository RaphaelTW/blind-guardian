#requires -PSEdition Desktop
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ProtectionFile,
    [Parameter(Mandatory)][string]$BrokerSid,
    [Parameter(Mandatory)][string]$EmployeeSid,
    [Parameter(Mandatory)][string]$OutputPath
)
$ErrorActionPreference = 'Stop'
Import-Module AppLocker -ErrorAction Stop
if ($BrokerSid -notmatch '^S-1-\d+(?:-\d+)+$' -or $EmployeeSid -notmatch '^S-1-\d+(?:-\d+)+$') { throw 'SID inválido.' }
if ($BrokerSid -eq $EmployeeSid) { throw 'A conta de execução precisa ser diferente da conta do funcionário.' }
if ($BrokerSid -in @('S-1-5-18','S-1-5-32-544','S-1-1-0')) { throw 'Use uma conta dedicada sem privilégios administrativos para o broker.' }
if (Test-Path -LiteralPath $OutputPath) { throw 'O arquivo de saída já existe.' }
$records = @(Get-Content -LiteralPath $ProtectionFile -Raw | ConvertFrom-Json)
if (-not $records.Count) { throw 'Nenhum aplicativo selecionado.' }
$conditions = New-Object 'System.Collections.Generic.List[string]'
$paths = New-Object 'System.Collections.Generic.List[string]'
foreach ($record in $records) {
    if ($record.state -notin @('pending_validation','active')) { continue }
    $path = (Resolve-Path -LiteralPath $record.executable -ErrorAction Stop).Path
    if ([IO.Path]::GetExtension($path) -ine '.exe') { throw "O alvo não é EXE: $path" }
    if ($path -like "$env:WINDIR\*" -or $path -like '*\Blind Guardian\*') { throw "Alvo crítico recusado: $path" }
    $info = Get-AppLockerFileInformation -Path $path -ErrorAction Stop
    [xml]$generated = New-AppLockerPolicy -FileInformation $info -RuleType Hash -User $BrokerSid -Xml -ErrorAction Stop
    $condition = $generated.AppLockerPolicy.RuleCollection.FileHashRule.Conditions.FileHashCondition.OuterXml
    if (-not $condition) { throw "Não foi possível identificar o hash AppLocker: $path" }
    if (-not $conditions.Contains($condition)) { $conditions.Add($condition); $paths.Add($path) }
}
if (-not $conditions.Count) { throw 'Nenhum EXE elegível encontrado.' }
$exceptions = $conditions -join ''
$rules = foreach ($condition in $conditions) {
    '<FileHashRule Id="' + [guid]::NewGuid() + '" Name="Blind Guardian broker" Description="Executável selecionado" UserOrGroupSid="' + $BrokerSid + '" Action="Allow"><Conditions>' + $condition + '</Conditions></FileHashRule>'
}
$xml = '<AppLockerPolicy Version="1"><RuleCollection Type="Exe" EnforcementMode="Enabled">' +
    '<FilePathRule Id="' + [guid]::NewGuid() + '" Name="Outros EXEs" Description="Permite outros programas" UserOrGroupSid="S-1-1-0" Action="Allow"><Conditions><FilePathCondition Path="*" /></Conditions><Exceptions>' +
    $exceptions + '</Exceptions></FilePathRule>' + ($rules -join '') + '</RuleCollection></AppLockerPolicy>'
$candidate = Join-Path $env:TEMP ("blind-guardian-policy-$([guid]::NewGuid()).xml")
try {
    $xml | Set-Content -LiteralPath $candidate -Encoding UTF8
    foreach ($path in $paths) {
        $blocked = @(Test-AppLockerPolicy -XmlPolicy $candidate -Path $path -User $EmployeeSid -ErrorAction Stop)[0].PolicyDecision
        $allowed = @(Test-AppLockerPolicy -XmlPolicy $candidate -Path $path -User $BrokerSid -ErrorAction Stop)[0].PolicyDecision
        if ($blocked -notlike 'Denied*' -or $allowed -notlike 'Allowed*') { throw "Decisões incorretas para $path : funcionário=$blocked, broker=$allowed" }
    }
    $controlPath = Join-Path $env:WINDIR 'System32\notepad.exe'
    if (Test-Path -LiteralPath $controlPath) {
        $control = @(Test-AppLockerPolicy -XmlPolicy $candidate -Path $controlPath -User $EmployeeSid -ErrorAction Stop)[0].PolicyDecision
        if ($control -notlike 'Allowed*') { throw "Programa não selecionado seria bloqueado: $controlPath ($control)" }
    }
    Copy-Item -LiteralPath $candidate -Destination $OutputPath -ErrorAction Stop
    Write-Output "Política candidata gerada: $OutputPath ($($paths.Count) EXEs). Não foi aplicada."
} finally {
    Remove-Item -LiteralPath $candidate -ErrorAction SilentlyContinue
}
