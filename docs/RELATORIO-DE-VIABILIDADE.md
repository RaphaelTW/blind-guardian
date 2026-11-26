# Relatório de viabilidade — 25/11/2026

## Requisitos conflitantes

O pedido exige simultaneamente:

1. bloquear a execução direta de um EXE protegido para usuários comuns;
2. após a senha do Blind Guardian, executar esse mesmo EXE como o mesmo usuário, com os privilégios originais;
3. manter o bloqueio ativo para outros usuários e sessões durante toda a autorização;
4. não usar driver próprio, injeção ou hooks invasivos.

Uma regra explícita `Deny` do AppLocker impede a execução direta. A Microsoft documenta que ela prevalece sobre qualquer regra `Allow` correspondente. Logo, acrescentar uma regra de liberação após a senha não autoriza a execução daquele EXE pelo mesmo usuário. Remover temporariamente a regra `Deny` altera a política do computador, expõe uma janela de execução sem autenticação e afeta sessões concorrentes. Isso não satisfaz os requisitos 2 e 3 com segurança. Regras NTFS alteradas temporariamente apresentam o mesmo problema de escopo e concorrência.

Uma política AppLocker para bloquear um programa também precisa ser projetada junto com as regras que permitem os demais executáveis; uma coleção com regras se torna uma lista de permissões e pode bloquear programas inesperados. Políticas corporativas existentes podem determinar o resultado efetivo. A presença do AppLocker no Windows não equivale a uma solução de autorização por senha por execução.

## Verificação executada

Ambiente: Windows 10 Pro x64, versão 10.0.19045, sessão sem elevação. `Get-AppLockerPolicy -Local -Xml` e `-Effective -Xml` retornaram `<AppLockerPolicy Version="1" />`. `AppIDSvc` estava `Stopped`, inicialização `Manual`.

Executado `tools/Test-ProtectionFeasibility.ps1` com Windows PowerShell 5.1. Política sintética: permitir todos os EXEs, negar `notepad.exe` e também permitir explicitamente `notepad.exe`, tudo para `Everyone`.

| Arquivo | Resultado do `Test-AppLockerPolicy` | Regra correspondente |
| --- | --- | --- |
| `C:\Windows\System32\notepad.exe` | `Denied` | Bloquear alvo |
| `C:\Windows\System32\calc.exe` | `Allowed` | Permitir outros |

**Limite:** esse cmdlet simula a decisão da política. Não foi feita instalação de política, tentativa de execução real nem teste em VM Windows 11. Também não houve teste de AnyDesk, Sophos, instalador, serviço ou interface. O projeto não pode ser classificado como funcional.

## AnyDesk

O EXE não é todo o limite de segurança do AnyDesk instalado: há serviço em segundo plano e opções de acesso não supervisionado. A CLI oficial documenta `--stop-service` e `--remove-password`, mas o segundo comando não remove senhas predefinidas em clientes personalizados. Não há base para afirmar que um bloqueio de EXE revogue todas as autorizações antigas ou impeça conexões remotas. Qualquer integração exige laboratório isolado, inventário da versão e configuração concretas e testes com a política Sophos da organização.

## Decisão antes da implementação

É necessária uma especificação revisada para o mecanismo de autorização. Duas opções que podem ser avaliadas em VM:

- **Atalho gerenciado:** solicitar senha antes de lançar pelo atalho. A execução direta do EXE continua possível; o produto precisa declarar essa limitação de forma visível.
- **Bloqueio permanente por política:** impedir execução direta com AppLocker, sem promessa de abertura temporária pelo mesmo usuário após senha. O administrador pode alterar a política por um procedimento autorizado, sujeito à política corporativa.

Uma solução que prometa os quatro requisitos originais precisa primeiro demonstrar, em VM, um mecanismo suportado pelo Windows que permita autorização por processo e sessão sem abrir a execução para outras sessões. Não há tal demonstração neste repositório.

## Continuação solicitada em 25/11/2026

A análise acima tratou de executar como **o mesmo usuário**. A hipótese posterior de um broker com **identidade Windows diferente** altera essa premissa e está sendo avaliada em [Execution Broker](EXECUTION-BROKER.md). A política por `Allow` com exceção e SID dedicado separou identidades em simulação, inclusive por hash para uma cópia renomeada do AnyDesk instalado. Ainda não houve aplicação da política nem execução real do aplicativo sob a conta dedicada; a conclusão original sobre `Deny` permanece válida.

## Fontes oficiais

- [Regras Allow e Deny do AppLocker](https://learn.microsoft.com/en-us/windows/security/application-security/application-control/app-control-for-business/applocker/understanding-applocker-allow-and-deny-actions-on-rules)
- [Comportamento das regras AppLocker](https://learn.microsoft.com/en-us/windows/security/application-security/application-control/app-control-for-business/applocker/working-with-applocker-rules)
- [Requisitos do AppLocker](https://learn.microsoft.com/windows/security/threat-protection/windows-defender-application-control/applocker/requirements-to-use-applocker)
- [Test-AppLockerPolicy](https://learn.microsoft.com/en-us/powershell/module/applocker/test-applockerpolicy)
- [AnyDesk CLI para Windows](https://support.anydesk.com/docs/command-line-interface-for-windows)
