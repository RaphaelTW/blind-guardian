# Execution Broker: arquitetura candidata e critérios de validação

Estado em 25/11/2026: **prova de política simulada aprovada; chamada básica de criação de processo executada; proteção real não validada**. Este documento complementa, sem substituir, o [relatório de viabilidade anterior](RELATORIO-DE-VIABILIDADE.md).

## Fluxo candidato

1. Uma política AppLocker efetiva permite os aplicativos normais, mas exclui a identidade dos binários protegidos das regras gerais de `Allow`. Uma regra separada permite esses binários somente ao SID da conta dedicada de execução. Não há regra `Deny` que se aplique à conta dedicada.
2. O funcionário inicia o launcher. O cliente na sessão interativa exibe a senha e envia o pedido ao broker por named pipe autenticado, sem colocar a senha em argumentos ou logs.
3. O broker verifica a senha Argon2id, limites de tentativas, identidade do cliente, sessão e binário aprovado. Precisa obter um token primário da conta dedicada, sem privilégios administrativos, e criar o processo na sessão interativa correta com `CreateProcessAsUserW`.
4. O processo é associado a um Job Object para detectar o fim da instância e limitar filhos, quando compatível. O Job Object não é o controle de execução direta. A regra AppLocker permanece ativa durante toda a sessão.
5. Ao terminar, o broker revoga o estado de autorização, encerra processos auxiliares somente se isso for seguro para o aplicativo e registra o resultado. Uma nova execução exige nova senha.

O processo da conta dedicada **não terá o mesmo token, perfil, HKCU, credenciais de rede nem permissões de arquivo do funcionário**. A exigência de preservar os privilégios originais só pode ser interpretada como não elevar privilégios; equivalência de acesso e usabilidade precisa ser medida por aplicativo. O serviço não deve simplesmente copiar o token do funcionário: isso faria a política bloqueá-lo também.

O broker precisará proteger a credencial da conta dedicada ou demonstrar outro modo suportado de obter seu token. Não se deve confundir a senha Argon2id do Blind Guardian com a credencial Windows dessa conta. O token de outro usuário não surge da senha do aplicativo. `CreateProcessAsUserW` exige token primário, privilégios no processo chamador, acesso do usuário ao EXE, sessão correta e preparação da estação de janelas/desktop. A API não carrega automaticamente o perfil do usuário.

## Comparação técnica

| Mecanismo | Segurança pretendida | Compatibilidade e custo | Papel proposto |
| --- | --- | --- | --- |
| AppLocker por `Allow` com exceção e SID dedicado | Bloqueia execução direta para funcionário; permite somente SID autorizado | Requer política efetiva, Application Identity ativo, análise de GPO e testes por versão | Controle principal candidato |
| AppLocker por caminho | Baixo custo | Cópia e renomeação escaparam no teste local; caminhos graváveis são problemáticos | Insuficiente isoladamente |
| AppLocker por hash | Cópia idêntica renomeada foi reconhecida no teste local | Atualizações e versões alternativas exigem novos hashes; hash AppLocker não é o SHA-256 plano | Candidato para binários conhecidos |
| AppLocker por publisher | Pode cobrir atualizações e cópias assinadas | A geração automática falhou no AnyDesk 9.8.4 local por metadados incompletos; política ampla pode atingir outros binários | Investigar em VM por versão |
| ACL NTFS | Bloqueia acesso aos arquivos instalados conforme SID | Não cobre cópias em locais do funcionário; alterações podem afetar atualização e serviço | Defesa adicional somente |
| Token Windows e conta dedicada | Separa a identidade autorizada da identidade bloqueada | Perfil, desktop, arquivos, rede e credencial da conta exigem validação | Execução mediada |
| Job Object | Acompanha ciclo de vida e alguns filhos | Processos podem escapar conforme configuração e arquitetura do aplicativo | Monitoramento, não bloqueio |
| SCM | Pode impedir serviço AnyDesk instalado de manter acesso remoto | Exige privilégios administrativos, coordenação com atualização e política corporativa | Adaptador AnyDesk instalado |
| Firewall Windows | Pode reduzir tráfego de uma instalação conhecida | Regras por caminho não cobrem cópias; bloqueio de saída pode afetar suporte legítimo e outras políticas | Camada complementar, nunca única |
| Launcher autenticado | Entrada de senha e roteamento para broker | Não impede execução direta | Interface de autorização |

## AnyDesk: dois modos diferentes

O modo instalado mantém o AnyDesk Global Service em segundo plano mesmo sem janela. Logo, bloquear só a interface não prova ausência de conexões. Antes de habilitar o adaptador, uma VM deve verificar o serviço, configuração de acesso não supervisionado, senhas e perfis, conexões a partir de outra máquina e comportamento de atualização. O estado de bloqueio exige serviço parado ou outro controle demonstrado que impeça conexões. Parar ou desabilitar o serviço em ambiente corporativo requer coordenação com a TI e não pode ocorrer às cegas.

O modo portátil, segundo o fabricante, não inicia com o Windows e encerra as sessões quando sua janela fecha ou o usuário sai. É o primeiro candidato para suporte atendido. Isso ainda precisa ser provado na versão usada, com conexão externa, processo auxiliar, cópia renomeada e versões alternativas. Binários não conhecidos pelo hash não ficam protegidos por uma regra de hash específica. Uma política que bloqueie *qualquer* ferramenta portátil não pode ser inferida de uma lista de hashes do AnyDesk.

O AnyDesk instalado neste computador de desenvolvimento apresenta serviço com inicialização automática, atualmente parado, e EXE assinado. A versão de arquivo é 9.8.4. O arquivo não contém `OriginalFilename` e `New-AppLockerPolicy -RuleType Publisher` falhou com informação insuficiente. A política sintética por hash reconheceu o EXE original e uma cópia renomeada. Nenhuma tentativa de conexão ou execução do AnyDesk foi feita.

## Resultados locais reproduzidos

| Prova | Resultado | Limite |
| --- | --- | --- |
| `Test-ProtectionFeasibility.ps1` | `Deny` vence `Allow` para o mesmo arquivo/SID | Simulação AppLocker |
| `Test-IdentityPolicy.ps1` | SID autorizado `Allowed`; outra conta local `DeniedByDefault`; cópia renomeada `Allowed` | Mostra que caminho é insuficiente; política não aplicada |
| `Inspect-AnyDeskIdentity.ps1` | Assinatura válida; regra Publisher automática falhou; regra Hash gerada | Versão local 9.8.4 apenas |
| `Test-AnyDeskHashPolicy.ps1` | Original e cópia renomeada: `Allowed` para um SID, `DeniedByDefault` para outro | Simulação; não testou versões alternativas |
| `Test-CreateProcessAsUser.ps1` | `whoami.exe` foi realmente iniciado por `CreateProcessAsUserW`; código de saída 0 | Usou o token do usuário atual, sem política nem conta dedicada |

O último teste demonstra apenas a chamada básica da API. Não verifica acesso ao desktop, credenciais da conta dedicada, serviço, AppLocker efetivo ou AnyDesk. O computador de desenvolvimento não possui VM Windows disponível nem toolchain Rust/Node; a sessão não está elevada. Esses fatores impedem instalar uma política de prova isolada e testar o broker completo sem modificar a máquina de uso. Nenhum dos aplicativos está marcado como proteção validada.

## Portões para uma VM isolada

1. Criar snapshot e contas padrão separadas para funcionário e broker. Registrar SIDs, sessões, perfil e permissões. Instalar AnyDesk portátil e, em snapshot separado, o instalado. Providenciar máquina remota controlada para tentar conectar.
2. Construir política inicial em `AuditOnly`; comparar política local e efetiva, preservar regras corporativas e validar que Windows, Sophos, Tauri e ferramentas administrativas continuam operando. Aplicar somente na VM após snapshot.
3. Confirmar em modo `Enabled` por **execução real**: funcionário não consegue abrir EXE original, cópia renomeada nem outras versões dentro do escopo declarado; conta dedicada consegue abrir apenas após mediação. Capturar eventos AppLocker e identidades dos processos. Testar dois funcionários simultâneos e reinicialização.
4. Criar PoC Rust do broker com `CreateProcessAsUserW`, token da conta dedicada, ambiente/perfil, desktop e named pipe com ACL. Verificar GUI visível na sessão correta, arquivos, configurações, rede, processos filhos, UAC e encerramento por Job Object. Não incorporar credenciais em código ou repositório.
5. Para AnyDesk portátil, tentar conexão externa antes, durante e após autorização, inclusive com janela fechada. Para instalado, testar serviço e conexões mesmo sem janela. Repetir após atualização e falha do broker.
6. Somente com esses resultados passar a interface Tauri, serviço definitivo e NSIS. Marcar cada versão de aplicativo como `validada`, `parcial` ou `não suportada`; nunca chamar `protegida` uma combinação sem teste real.

## Fontes oficiais

- [AppLocker: exceções e identidade](https://learn.microsoft.com/en-us/windows/security/application-security/application-control/app-control-for-business/applocker/understanding-applocker-rule-exceptions)
- [AppLocker: regras e GPO](https://learn.microsoft.com/en-us/windows/security/application-security/application-control/app-control-for-business/applocker/understand-applocker-rules-and-enforcement-setting-inheritance-in-group-policy)
- [CreateProcessAsUserW](https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-createprocessasuserw)
- [Processos no contexto do cliente](https://learn.microsoft.com/en-us/windows/win32/secauthz/processes-in-the-client-security-context)
- [Serviços interativos](https://learn.microsoft.com/en-us/windows/win32/services/interactive-services)
- [LoadUserProfileW](https://learn.microsoft.com/en-us/windows/win32/api/userenv/nf-userenv-loaduserprofilew)
- [Job Objects](https://learn.microsoft.com/en-us/windows/win32/procthread/job-objects)
- [AnyDesk portátil e instalado](https://support.anydesk.com/docs/portable-vs-installed)
- [AnyDesk CLI](https://support.anydesk.com/docs/command-line-interface-for-windows)
