# Blind Guardian

Aplicação Windows de desenvolvimento **0.1.0-alpha** para inventário de programas e avaliação de proteção por aplicativo. Desenvolvido por Raphael Laurentino. Funciona offline e usa Tauri 2, Rust, React e TypeScript.

> **Estado de segurança:** nenhum aplicativo possui proteção validada nesta versão. “Aguardando validação” registra apenas uma solicitação; não bloqueia o EXE. O serviço incluído ainda não aplica políticas. Não utilizar como controle de acesso em produção.

**Por que o AnyDesk abriu mesmo após clicar em “Preparar bloqueio”?** Esse comando grava uma solicitação para testes; a versão publicada não intercepta a abertura direta do EXE. A janela de senha do Blind Guardian só poderá liberar um aplicativo depois que uma política de execução real estiver instalada e validada. No código em desenvolvimento, o botão “Senha” fica desabilitado enquanto o estado for pendente. O modo instalado do AnyDesk também possui um serviço em segundo plano, que precisa ser controlado separadamente.

## O que funciona hoje

- Login administrativo local com senha Argon2id e salt aleatório; username inicial `rakdos`; bloqueio após tentativas incorretas.
- Inventário real das chaves de desinstalação HKLM/HKCU e WOW6432Node; nomes, versão, fabricante e `DisplayIcon` quando disponível. Não usa `Win32_Product`.
- Extração dos ícones via Windows Shell, pesquisa, atualização da lista e inclusão manual de EXE.
- Registro de solicitações de proteção em estado **Aguardando validação**, com autenticação administrativa para adicionar ou remover. A janela de senha de execução recusa a abertura enquanto o mecanismo não estiver validado.
- Tema do sistema, interface com duas abas, ícone na bandeja, início oculto e encerramento autenticado pela interface. Em builds release, registra inicialização no HKCU Run do usuário atual.
- Serviço Rust independente com estado experimental, sem políticas de proteção. A aplicação consulta o SCM e confirma o PID do servidor do pipe local. Logs locais em JSONL.
- Fonte do instalador NSIS de desenvolvimento, com WebView2 gerenciado pelo Tauri.

## Construir

Requer Windows 10/11 x64, Node.js, Rust MSVC, Microsoft C++ Build Tools e Windows SDK conforme os [pré-requisitos oficiais do Tauri](https://v2.tauri.app/start/prerequisites/). Nesta máquina a compilação usou uma toolchain MSVC/SDK portátil no perfil do usuário. O instalador alpha foi gerado em [artifacts/BlindGuardian_0.1.0-alpha_x64_Setup.exe](artifacts/BlindGuardian_0.1.0-alpha_x64_Setup.exe), mas **não foi instalado nem testado em VM**.

```powershell
npm ci
npm run build
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\Build-Dev.ps1
```

O último comando compila o serviço, inclui o binário no bundle e tenta gerar `artifacts/BlindGuardian_0.1.0-alpha_x64_Setup.exe`. O instalador é para avaliação: ele **não instala nem inicia o serviço**, não aplica AppLocker e não configura a senha durante a instalação. O cadastro de senha ocorre na primeira abertura da interface. Essas lacunas precisam ser resolvidas antes de qualquer release de segurança.

Para desenvolvimento da interface: `npm run tauri dev`. A janela começa oculta; abra pelo ícone da bandeja. O app só mostra inventário do Windows dentro do runtime Tauri.

## Organização

- `src/`: React, UI e chamadas Tauri.
- `src-tauri/`: comandos Rust, autenticação, inventário, ícones, estados e NSIS.
- `service/`: esqueleto de Windows Service e canal local de estado experimental.
- `tools/`: provas de viabilidade, testes e scripts de VM.
- `docs/`: arquitetura, instruções de laboratório, relatórios e limites.

## Testes de viabilidade

O [relatório original](docs/RELATORIO-DE-VIABILIDADE.md) permanece preservado. A [arquitetura do Execution Broker](docs/EXECUTION-BROKER.md) compara AppLocker, tokens, serviço, ACLs, Job Objects, firewall e AnyDesk. O [manual de laboratório](docs/TESTES.md) explica como executar os scripts sem alterar a máquina de desenvolvimento.

Copyright © 2026 Raphael Laurentino. Licença MIT.
