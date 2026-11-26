# Changelog

## 0.1.0-alpha.1 — 2026-11-26

- Interface de primeira abertura, inventário de EXEs por `InstallLocation` e identidade visual atualizada.
- Launcher experimental com senha e scripts para redirecionar/restaurar atalhos no perfil atual.
- Registro e inicialização do Windows Service pelo instalador NSIS, com rotina própria de instalação do serviço.
- Script de geração e simulação de política AppLocker candidata; nenhuma política é aplicada automaticamente.
- Build MSVC x64 via `vswhere` e Visual Studio Insiders.
- Limite: o serviço ainda não bloqueia a execução direta, o armazenamento continua por usuário e o instalador não foi validado em VM. Esta versão não é um controle de acesso.

## 0.1.0-alpha — 2026-11-25

- Estrutura Tauri 2, Rust, React e TypeScript.
- UI de login e inventário com tema do Windows.
- Hash Argon2id, limite de tentativas, sessão administrativa e logs locais.
- Estados explícitos de proteção; solicitações permanecem pendentes e não aplicam bloqueio.
- Esqueleto de serviço Windows e configuração NSIS de desenvolvimento.
- Provas AppLocker por identidade e hash; chamada real de `CreateProcessAsUserW` com token do usuário atual.
- Scripts para laboratório isolado e restauração.
