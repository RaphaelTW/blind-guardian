## Blind Guardian 0.1.0-alpha.1

Pré-release de código-fonte. Esta release não inclui executáveis nem instalador.

### Alterações

- Inventário de aplicativos com busca adicional no diretório de instalação.
- Identidade visual atualizada e launcher experimental com senha para atalhos gerenciados no perfil atual.
- Rotina de registro/inicialização do Windows Service no instalador NSIS.
- Geração e simulação de política AppLocker candidata, sem aplicá-la.
- Build MSVC x64 por meio de `vswhere` e Visual Studio Insiders.

### Validação e limites

O frontend e os dois projetos Rust passaram em `cargo check --locked`; o serviço passou no autoteste do canal local. A instalação elevada da rotina corrigida ainda não foi validada. O serviço não bloqueia a execução direta, não há broker para contas Windows diferentes e o AnyDesk instalado pode continuar operando por seu serviço próprio. **Não usar como controle de acesso em produção.**

Para gerar o instalador localmente:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\Invoke-Msvc.ps1 powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\Build-Dev.ps1
```
