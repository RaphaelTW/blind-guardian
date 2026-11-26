# Segurança e estado experimental

Blind Guardian 0.1.0-alpha **não é um produto de segurança implantável**. Nenhum bloqueio real foi validado. O serviço não aplica AppLocker, não controla o serviço AnyDesk e não inicia processos sob identidade dedicada. Solicitações armazenadas como `pending_validation` não devem ser interpretadas como proteção.

## Implementado

- Hash Argon2id com salt aleatório para a senha administrativa local.
- Limite de cinco falhas e espera de cinco minutos, persistidos em `credentials.json`.
- Tokens de sessão em memória com expiração por inatividade e descarte ao fechar a janela.
- Confirmação de credenciais para solicitar/remover proteção e encerrar a interface.
- Logs locais sem senha, em `audit.jsonl`.
- Canal de estado experimental por named pipe com ACL explícita, rejeição de clientes remotos e sem comandos privilegiados. A interface compara o PID do servidor do pipe com o PID informado pelo SCM. A autenticação de clientes para futuras operações privilegiadas ainda não foi implementada.

## Lacunas que impedem produção

- A credencial é cadastrada no primeiro uso e armazenada no perfil do usuário atual, não em armazenamento de máquina com ACL controlada pelo serviço. Um administrador local pode alterar esses arquivos. Não há migração ou recuperação administrativa validada.
- O serviço pode ser instalado como binário de desenvolvimento, mas não gerencia políticas, identidades, firewall ou AnyDesk. O pipe de estado não deve receber senhas ou operações privilegiadas até que a identidade do cliente seja validada.
- O inventário por Registro não cobre todos os atalhos, aplicativos Store e aplicativos portáteis. `DisplayIcon` nem sempre identifica o EXE principal.
- A seleção de programas críticos é conservadora, mas ainda não foi testada contra todas as políticas corporativas. Não instalar regras AppLocker fora de VM isolada.
- O instalador NSIS ainda não instala o serviço nem captura a senha inicial. O processo da interface não é resistência contra encerramento por um administrador local.
- Não há proteção validada para AnyDesk instalado ou portátil, cópias, renomeações, versões alternativas ou conexões remotas.

Relate vulnerabilidades pelo canal privado do mantenedor no GitHub; não inclua senhas, chaves ou informações corporativas em issues públicas.
