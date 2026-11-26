# Blind Guardian

Aplicação Windows de desenvolvimento **0.1.0-alpha.1** para inventário de programas e avaliação de proteção por aplicativo. Desenvolvido por Raphael Laurentino. Funciona offline e usa Tauri 2, Rust, React e TypeScript.

> **Estado de segurança:** nenhum aplicativo possui proteção validada nesta versão. “Aguardando validação” registra apenas uma solicitação; não bloqueia o EXE. O serviço incluído ainda não aplica políticas. Não utilizar como controle de acesso em produção.

**Por que o AnyDesk abre após solicitar proteção?** O cadastro registra uma solicitação para testes; esta versão não impede a abertura direta do EXE. O launcher gerenciado pode pedir senha no perfil Windows que cadastrou o programa, mas não substitui uma política de execução. O modo instalado do AnyDesk também possui um serviço em segundo plano, que precisa ser controlado separadamente.

## O que funciona hoje

- Login administrativo local com senha Argon2id e salt aleatório; username inicial `rakdos`; bloqueio após tentativas incorretas.
- Inventário real das chaves de desinstalação HKLM/HKCU e WOW6432Node; nomes, versão, fabricante e `DisplayIcon` quando disponível. Não usa `Win32_Product`.
- Extração dos ícones via Windows Shell, pesquisa, atualização da lista e inclusão manual de EXE.
- Registro de solicitações de proteção em estado **Aguardando validação**, com autenticação administrativa para adicionar ou remover. A janela de senha de execução recusa a abertura enquanto o mecanismo não estiver validado.
- Atalhos gerenciados experimentais: o botão **Criar atalho** tenta redirecionar atalhos existentes do Menu Iniciar e da Área de Trabalho que apontem para o EXE selecionado. Guarda cópias para restauração ao remover a solicitação. Atalhos compartilhados exigem permissão de escrita. O fluxo usa os dados do perfil Windows que criou a solicitação e ainda não atende funcionários de outras contas. A abertura direta do EXE continua livre; portanto os atalhos não constituem proteção.
- Identidade visual com os dois ícones de ciclope fornecidos: o primeiro no executável e na bandeja; o segundo na tela de acesso.
- Tema do sistema, interface com duas abas, ícone na bandeja, início oculto e encerramento autenticado pela interface. Em builds release, registra inicialização no HKCU Run do usuário atual.
- Serviço Rust independente com estado experimental, sem políticas de proteção. O instalador NSIS inclui a rotina de registro e inicialização do serviço; sua instalação elevada ainda não foi validada após a correção. A aplicação consulta o SCM e confirma o PID do servidor do pipe local. Logs locais em JSONL.
- Fonte do instalador NSIS de desenvolvimento, com WebView2 gerenciado pelo Tauri.

## Construir

Requer Windows 10/11 x64, Node.js, Rust MSVC, Microsoft C++ Build Tools e Windows SDK conforme os [pré-requisitos oficiais do Tauri](https://v2.tauri.app/start/prerequisites/). O script de build detecta o Visual Studio com `vswhere` e carrega o MSVC x64. O instalador alpha é gerado localmente em `artifacts/BlindGuardian_0.1.0-alpha.1_x64_Setup.exe`; binários não são publicados nesta release.

```powershell
npm ci
npm run build
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\Invoke-Msvc.ps1 powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\Build-Dev.ps1
```

O último comando compila o serviço, inclui o binário no bundle e gera `artifacts/BlindGuardian_0.1.0-alpha.1_x64_Setup.exe`. O instalador tenta registrar e iniciar o serviço experimental, mas **não aplica AppLocker nem bloqueia aplicativos**. A senha ainda é cadastrada na primeira abertura da interface e os dados ainda ficam no perfil desse usuário Windows. Essas lacunas precisam ser resolvidas antes de qualquer release de segurança.

Para desenvolvimento da interface: `npm run tauri dev`. A janela começa oculta; abra pelo ícone da bandeja. O app só mostra inventário do Windows dentro do runtime Tauri.

## Organização

- `src/`: React, UI e chamadas Tauri.
- `src-tauri/`: comandos Rust, autenticação, inventário, ícones, estados e NSIS.
- `service/`: esqueleto de Windows Service e canal local de estado experimental.
- `tools/`: provas de viabilidade, testes e scripts de VM.
- `docs/`: arquitetura, instruções de laboratório, relatórios e limites.

## Testes de viabilidade

O [relatório original](docs/RELATORIO-DE-VIABILIDADE.md) permanece preservado. A [arquitetura do Execution Broker](docs/EXECUTION-BROKER.md) compara AppLocker, tokens, serviço, ACLs, Job Objects, firewall e AnyDesk. O [manual de laboratório](docs/TESTES.md) explica como executar os scripts sem alterar a máquina de desenvolvimento.

`tools/New-GuardianPolicy.ps1` gera uma política AppLocker candidata por hash para todos os EXEs cadastrados e simula as decisões de uma conta comum e uma conta dedicada. Ele não aplica a política. A execução real ainda depende do broker no serviço e de testes isolados; o script não transforma registros pendentes em proteção ativa.

Copyright © 2026 Raphael Laurentino. Licença MIT.
