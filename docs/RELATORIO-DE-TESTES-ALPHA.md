# Relatório de testes — 25/11/2026

## Resultados executados

| Componente | Resultado |
| --- | --- |
| `npm install` | Concluído, sem vulnerabilidades reportadas pelo npm. |
| `npm run build` | TypeScript e Vite concluídos; frontend gerado em `dist/`. |
| Ícone | Gerado de `assets/shield.svg` pela CLI do Tauri. |
| `Test-ProtectionFeasibility.ps1` | PASS: `Deny` vence `Allow` em simulação. |
| `Test-IdentityPolicy.ps1` | PASS: regras por identidade; cópia renomeada escapa de exceção por caminho. |
| `Inspect-AnyDeskIdentity.ps1` | EXE local assinado; geração automática de regra Publisher falhou; regra Hash gerada. |
| `Test-AnyDeskHashPolicy.ps1` | PASS: hash da versão local diferenciou dois SIDs para original e cópia renomeada em simulação. |
| `Test-CreateProcessAsUser.ps1` | Processo `whoami.exe` criado de verdade com token do usuário atual, saída 0. |
| `cargo fmt` | Sintaxe Rust aceita pelo formatador. |
| `cargo check` | PASS após provisionar MSVC/Windows SDK portátil no perfil do usuário. |
| `cargo test --lib` | 3 testes passaram: hash/lockout persistente, troca de credenciais com invalidação de sessão e inventário real sem duplicatas. |
| Serviço Rust | `cargo build` e `cargo check` passaram; `--self-test` abriu o named pipe local e recebeu estado experimental. |
| NSIS alpha | Build final concluído, 286,86 MiB com WebView2 offline, em `artifacts/BlindGuardian_0.1.0-alpha_x64_Setup.exe`. Não instalado. |
| `Test-AppInventory.ps1` | 40 entradas reais no Registro local; 33 com `DisplayIcon`. Comparação com a UI ainda pendente. |
| `Test-Authentication.ps1` | Inconclusivo: cadastro inicial no executável ainda não realizado. |
| `Test-ExecutionBroker.ps1` | Chamada real `CreateProcessAsUserW` novamente concluída com token atual; broker dedicado inconclusivo. |
| `Test-AnyDesk.ps1` | Inspeção somente leitura: serviço instalado, parado, inicialização automática, EXE assinado. Conexões não testadas. |
| Parsers PowerShell | Os 14 scripts em `tools/` foram analisados sem erro de sintaxe. |

## Não executados ou inconclusivos

- Interação visual com a interface Tauri, execução do serviço como serviço SCM e instalação/desinstalação do NSIS.
- O executável release iniciou e permaneceu em execução. A inspeção visual foi tentada, mas a ponte de controle da interface Windows deste ambiente estava indisponível. O processo foi encerrado após a tentativa; nenhum cadastro de senha foi realizado.
- Autenticação Argon2id na interface, extração de ícones no runtime Tauri e inventário na UI. O backend foi testado isoladamente.
- Política AppLocker aplicada e execução real sob identidade dedicada.
- Serviço AnyDesk, modo portátil, conexões remotas, Sophos, Windows 11 e reinstalação.

Nenhum programa está validado como protegido. Os scripts de VM foram preparados, mas **não executados em VM**. Eles devem ser revisados e testados com snapshot antes de uso operacional.

SHA-256 do instalador final: `808C474098A8135FFD5A92338EC3F9C14567CC3640C769AF7E16CD2C9C183663`.
