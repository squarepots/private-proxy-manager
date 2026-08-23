# Route Steward

[English](README.md) · [简体中文](README.zh-CN.md) · [日本語](README.ja.md) · [Español](README.es.md) · [Português (Brasil)](README.pt-BR.md)

[Quickstart](docs/QUICKSTART.md) · [FAQ](docs/FAQ.md) · [Compatibility](docs/COMPATIBILITY.md) · [Operating boundary](docs/OPERATING-BOUNDARY.md) · [Security](SECURITY.md) · [AGPL-3.0-only](LICENSE)

[![Validation](https://github.com/squarepots/route-steward/actions/workflows/ci.yml/badge.svg)](https://github.com/squarepots/route-steward/actions/workflows/ci.yml)

**Diga à sua IA como o caminho de rede deve operar. O Route Steward mantém tudo funcionando.**

Route Steward é um gerenciador local-first do ciclo de vida de caminhos de rede auto-hospedados. Um agente de IA com acesso a ferramentas transforma a conectividade desejada sobre infraestrutura controlada pelo operador em estado validado, implantação, configuração de clientes, auditoria, detecção de drift, migração e recuperação.

Route Steward parte da conectividade à Internet entre os endpoints escolhidos. A Internet fornece o transporte; você fornece os servidores, as contas e a autorização de uso dos recursos de rede; o Route Steward fornece uma camada operacional repetível.

## Comece com um agente de IA

Entregue a URL ao Codex ou a outro agente capaz de ler arquivos locais e executar PowerShell:

> Open <https://github.com/squarepots/route-steward> and operate Route Steward for me. Read AGENTS.md and the repository Skill, inspect capabilities, run quick local validation, explain the requirements for my first self-hosted network path, keep sensitive state in the private directory, run preflight before changes, and return sanitized results.

```powershell
pwsh -NoProfile -File .\agent\route-steward-agent.ps1 capabilities
pwsh -NoProfile -File .\scripts\Validate-Local.ps1 -Quick
```

## Recursos necessários

- um computador local com PowerShell 7 e um agente de IA com ferramentas;
- um ou dois servidores Ubuntu 24.04 amd64 dedicados e reconstruíveis;
- acesso SSH autorizado;
- software compatível com Mihomo/Clash Verge ou Shadowrocket.

## Ciclo de vida gerenciado

- caminhos Hysteria2 diretos e caminhos relay WireGuard de um salto;
- desired state de Server, Link, Route, Provider, Profile e ClientTarget;
- arquivos compatíveis com Mihomo/Clash e imports do Shadowrocket;
- entrega opcional e isolada de configuração por ClientTarget;
- auditoria remota, typed drift e migração overlap-first;
- arquivos de recuperação criptografados.

## Condições de operação

Route Steward foi criado para servidores, contas e recursos de rede que o operador possui ou está autorizado a administrar. Cada implantação segue a legislação aplicável, os requisitos da operadora, os termos do provedor de nuvem e as políticas da organização. Consulte [Operating boundary](docs/OPERATING-BOUNDARY.md).

A capacidade implementada está documentada em [Compatibility](docs/COMPATIBILITY.md) e em capability discovery. Os limites de privacidade e autoridade estão em [Privacy](docs/PRIVACY.md), [Security](SECURITY.md) e [Threat model](docs/THREAT-MODEL.md).

Route Steward é distribuído sob [AGPL-3.0-only](LICENSE).
