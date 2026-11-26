# Instalação de desenvolvimento

**0.1.0-alpha não fornece bloqueio de aplicativos.** Use somente em laboratório ou para avaliar a interface e o inventário.

## Pré-requisitos para compilar

Windows 10/11 x64, Node.js, Rust com alvo MSVC, Microsoft C++ Build Tools e Windows SDK. Consulte os [pré-requisitos Tauri](https://v2.tauri.app/start/prerequisites/). O build do NSIS inclui o instalador offline do WebView2.

```powershell
npm ci
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\Build-Dev.ps1
```

O script gera o serviço experimental como recurso e copia o NSIS final para `artifacts/BlindGuardian_0.1.0-alpha_x64_Setup.exe`. O instalador per-machine exige elevação e instala a interface em Program Files. O serviço é incluído, mas **não registrado nem iniciado automaticamente** na versão alpha. Não há alteração de AppLocker, firewall ou serviço AnyDesk.

Abra Blind Guardian pela bandeja e cadastre uma senha com pelo menos 12 caracteres. O username inicial é `rakdos`. Esse cadastro é feito na primeira abertura, ainda não em uma página segura do instalador. As credenciais e solicitações são mantidas no perfil Windows do usuário atual; não compartilhe o mesmo estado entre contas e não trate essa instalação como proteção corporativa.

Para remover, use a desinstalação normal do Windows. Arquivos de dados no perfil do usuário podem persistir; exporte evidências e remova-os manualmente somente após decidir que não precisa mais deles.
