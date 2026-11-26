# Changelog

## 0.1.0-alpha — 2026-11-25

- Estrutura Tauri 2, Rust, React e TypeScript.
- UI de login e inventário com tema do Windows.
- Hash Argon2id, limite de tentativas, sessão administrativa e logs locais.
- Estados explícitos de proteção; solicitações permanecem pendentes e não aplicam bloqueio.
- Esqueleto de serviço Windows e configuração NSIS de desenvolvimento.
- Provas AppLocker por identidade e hash; chamada real de `CreateProcessAsUserW` com token do usuário atual.
- Scripts para laboratório isolado e restauração.
