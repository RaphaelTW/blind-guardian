# Manual de testes — Blind Guardian 0.1.0-alpha

## Desenvolvimento sem alterar políticas

Use Windows PowerShell 5.1. Os scripts abaixo não aplicam política nem iniciam AnyDesk:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\Test-ProtectionFeasibility.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\Test-IdentityPolicy.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\Inspect-AnyDeskIdentity.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\Test-AnyDeskHashPolicy.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\Test-CreateProcessAsUser.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\Test-AppInventory.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\Test-Authentication.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\Test-ExecutionBroker.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\Test-AnyDesk.ps1
```

O teste de autenticação precisa ser repetido após cadastrar a senha na interface. Verifique login correto, cinco senhas erradas, espera de cinco minutos, modal de preparar/remover e encerramento autenticado. O script só verifica o formato persistido.

## Laboratório isolado

Use duas VMs Windows 10/11 x64 sem domínio nem Sophos corporativo: uma alvo e uma origem da conexão de suporte. Crie snapshot das duas antes de começar. Abra PowerShell 5.1 como administrador dentro da VM alvo. Os scripts de mutação recusam máquinas cujo modelo não pareça virtual e recusam VMs associadas a domínio.

```powershell
$lab = 'C:\BlindGuardianLab'
.\tools\Setup-TestEnvironment.ps1 -LabPath $lab -WhatIf
.\tools\Setup-TestEnvironment.ps1 -LabPath $lab
.\tools\Test-AppLocker.ps1 -LabPath $lab
.\tools\Test-AppLocker.ps1 -LabPath $lab -Apply
.\tools\Test-ExecutionBroker.ps1 -LabPath $lab
.\tools\Test-AnyDesk.ps1 -LabPath $lab
.\tools\Restore-TestEnvironment.ps1 -LabPath $lab -WhatIf
.\tools\Restore-TestEnvironment.ps1 -LabPath $lab
```

`Setup-TestEnvironment.ps1` salva a política AppLocker local, estado de AppIDSvc e AnyDesk e cria duas contas padrão locais com senhas aleatórias protegidas por DPAPI do administrador da VM. Não altera AnyDesk. `Test-AppLocker.ps1 -Apply` aplica temporariamente uma política local apenas para `whoami.exe`, inicia AppIDSvc e testa execução real com as duas identidades; restaura a política no bloco `finally`. Se o processo for interrompido antes do `finally`, use `Restore-TestEnvironment.ps1` na mesma VM. O diretório de evidências não é excluído automaticamente.

**Não execute `-Apply` no computador de desenvolvimento.** A política efetiva deve estar vazia; o teste recusa GPO preexistente. Uma conta dedicada que consegue executar `whoami.exe` não prova usabilidade do AnyDesk.

## Ensaio manual AnyDesk na VM

Faça snapshots separados para o modo portátil e o instalado. Para cada modo, registre: versão, assinatura, hash AppLocker, SID do processo, sessão, serviço AnyDesk, política efetiva, eventos AppLocker e resultado de conexão da segunda VM.

1. Antes da senha, tente iniciar o EXE original, uma cópia renomeada, uma versão portátil diferente e iniciar sob outro usuário. Tente conectar da VM de suporte mesmo com a janela fechada.
2. Após a autorização, confirme que o processo está na sessão correta e sob a identidade sem privilégios administrativos. Verifique que o funcionário consegue ver e aceitar a solicitação da ESL, com arquivos e configurações necessários.
3. Feche a janela e verifique processos auxiliares, serviço e conexões. Repita após reinício, atualização e falha do broker.
4. Se alguma conexão for aceita sem autorização, marque a versão como **não suportada** ou **falha na proteção**. Só marque **Proteção ativa** depois de bloquear também execução direta e conexões.

Os scripts atuais não concluem esse ensaio: o broker Rust ainda não obtém o token da conta dedicada nem lança o AnyDesk. A prova exige implementação posterior e verificação independente. Consulte [Execution Broker](EXECUTION-BROKER.md).
