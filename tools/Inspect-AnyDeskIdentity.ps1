#requires -PSEdition Desktop
# Somente leitura. Não inicia AnyDesk nem instala políticas.
[CmdletBinding()]
param([string]$Executable = 'C:\Program Files (x86)\AnyDesk\AnyDesk.exe')

$ErrorActionPreference = 'Stop'
Import-Module AppLocker
if (-not (Test-Path -LiteralPath $Executable)) { throw "EXE não encontrado: $Executable" }
$item = Get-Item -LiteralPath $Executable
$fileInfo = Get-AppLockerFileInformation -Path $item.FullName
$signature = Get-AuthenticodeSignature -LiteralPath $item.FullName
$sha256 = Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256
$publisherPolicy = $null
$publisherError = $null
try {
    $publisherPolicy = New-AppLockerPolicy -FileInformation $fileInfo -RuleType Publisher -User 'S-1-1-0' -Xml -ErrorAction Stop
} catch {
    $publisherError = $_.Exception.Message
}
$hashPolicy = New-AppLockerPolicy -FileInformation $fileInfo -RuleType Hash -User 'S-1-1-0' -Xml -ErrorAction Stop
[pscustomobject]@{
    Path = $item.FullName
    ProductVersion = $item.VersionInfo.ProductVersion
    SignatureStatus = $signature.Status
    Signer = $signature.SignerCertificate.Subject
    SHA256 = $sha256.Hash
    AppLockerPublisher = $fileInfo.Publisher
    OriginalFilename = $item.VersionInfo.OriginalFilename
    PublisherRuleError = $publisherError
}
Write-Output "Publisher policy: $publisherPolicy"
Write-Output "Hash policy: $hashPolicy"
