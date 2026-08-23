# Route Steward

[English](README.md) · [简体中文](README.zh-CN.md) · [日本語](README.ja.md) · [Español](README.es.md) · [Português (Brasil)](README.pt-BR.md)

[Quickstart](docs/QUICKSTART.md) · [FAQ](docs/FAQ.md) · [Compatibility](docs/COMPATIBILITY.md) · [Operating boundary](docs/OPERATING-BOUNDARY.md) · [Security](SECURITY.md) · [AGPL-3.0-only](LICENSE)

[![Validation](https://github.com/squarepots/route-steward/actions/workflows/ci.yml/badge.svg)](https://github.com/squarepots/route-steward/actions/workflows/ci.yml)

**Use IA para gerenciar a rede dos seus próprios servidores.**

O Route Steward ajuda você a implantar, verificar, migrar e recuperar conexões de rede nos servidores que administra. Você fornece os servidores, as contas e a autorização; o Route Steward oferece a um agente de IA com ferramentas uma forma repetível e validada de operá-los a partir do seu computador local.

![Diagrama sintético do Route Steward que separa o plano de controle operado por IA dos caminhos de tráfego direct e relay por Entry-A e pelo Relay-A opcional.](docs/assets/network-path-lifecycle.svg)

## Comece com um agente de IA

Cole este prompt no Codex ou em outro agente capaz de ler arquivos e executar PowerShell:

```text
Abra https://github.com/squarepots/route-steward e me ajude a gerenciar a rede dos meus próprios servidores com IA. Faça o clone se necessário, leia AGENTS.md e o repository Skill, inspecione capabilities e execute a validação local rápida. Antes de pedir dados de infraestrutura, explique os requisitos do host dedicado, os efeitos em todo o host e o operating boundary. Mantenha o estado sensível em private, execute preflight antes das mudanças e retorne resultados sanitizados.
```

```powershell
pwsh -NoProfile -File .\agent\route-steward-agent.ps1 capabilities
pwsh -NoProfile -File .\scripts\Validate-Local.ps1 -Quick
```

## O que você precisa

- um computador local com PowerShell 7 e um agente de IA com ferramentas;
- um ou dois servidores Ubuntu 24.04 amd64 dedicados e reconstruíveis;
- acesso SSH autorizado com usuário Unix e caminho da chave privada;
- software compatível com Mihomo/Clash Verge ou Shadowrocket.

O Route Steward prepara todo o servidor, portanto cada host gerenciado deve ser dedicado a esta configuração de rede.

## O que o Route Steward faz

Ele cria e valida configurações de servidor e cliente, verifica o estado ativo, ajuda a substituir a infraestrutura sem descartar primeiro a conexão existente e gera arquivos de recuperação criptografados.

[Compatibility](docs/COMPATIBILITY.md) lista os hosts, protocolos, clientes, topologias e a entrega opcional pelo Cloudflare que são suportados atualmente.

## Efeitos no host e privacidade

A instalação altera configurações globais de firewall, swap, SSH, sistema, logs, atualizações e monitoramento. O estado sensível e os arquivos gerados ficam no diretório private local escolhido; cada mudança exige um preflight pronto. Leia [Operations](OPERATIONS.md), [Privacy](docs/PRIVACY.md) e [Security](SECURITY.md).

Use somente servidores, contas e recursos de rede próprios ou que você tenha autorização para administrar. Consulte [Operating boundary](docs/OPERATING-BOUNDARY.md).

O Route Steward é distribuído sob [AGPL-3.0-only](LICENSE). A atribuição MIT do gerador de QR incluído permanece em [client/vendor/NOTICE.md](client/vendor/NOTICE.md).
