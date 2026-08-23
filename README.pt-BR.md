# Route Steward

[English](README.md) · [简体中文](README.zh-CN.md) · [日本語](README.ja.md) · [Español](README.es.md) · [Português (Brasil)](README.pt-BR.md)

[Quickstart](docs/QUICKSTART.md) · [FAQ](docs/FAQ.md) · [Compatibility](docs/COMPATIBILITY.md) · [Operating boundary](docs/OPERATING-BOUNDARY.md) · [Security](SECURITY.md) · [Releases](https://github.com/squarepots/route-steward/releases)

[![Validation](https://github.com/squarepots/route-steward/actions/workflows/ci.yml/badge.svg)](https://github.com/squarepots/route-steward/actions/workflows/ci.yml)

**Use IA para gerenciar a rede dos seus próprios servidores.**

O Route Steward ajuda você a implantar, verificar, migrar e recuperar conexões de rede nos servidores que administra. Entregue a URL do GitHub a um agente de IA com ferramentas: ele pode descobrir as operações suportadas, montar um plano, executar preflight, operar pelo binário nativo `route-steward` e retornar resultados sem expor credenciais ou caminhos locais.

![O Route Steward transforma um pedido à IA em estado validado, conexão direct ou relay, auditoria ativa e saída privada para Mihomo ou Shadowrocket.](docs/assets/network-path-lifecycle.svg)

## Entregue a URL a um agente de IA

```text
Abra https://github.com/squarepots/route-steward e ajude-me a gerenciar a rede dos meus próprios servidores. Clone o repositório se necessário, leia AGENTS.md e .agents/skills/route-steward/SKILL.md e depois use o binário publicado ou compile a CLI em Go. Execute capabilities antes de pedir dados de infraestrutura. Explique os requisitos de host dedicado e os efeitos no sistema, mantenha o estado operacional privado, execute preflight antes de cada mudança e devolva apenas resultados sanitizados.
```

```text
route-steward capabilities
route-steward bootstrap --private-dir ./private
route-steward context --private-dir ./private
```

O uso normal não exige PowerShell nem Node.js. Baixe o binário verificado para Linux, macOS ou Windows em [Releases](https://github.com/squarepots/route-steward/releases), ou instale pelo código-fonte com Go 1.27:

```text
go install github.com/squarepots/route-steward/cmd/route-steward@latest
```

Node.js só é usado quando você escolhe a entrega opcional de assinatura pelo Cloudflare Worker.

## O que você recebe

- uma route direct por um servidor ou um relay WireGuard de um salto por dois;
- estado de servidor Hysteria2 e arquivos privados para Mihomo ou Shadowrocket;
- auditoria somente leitura e drift tipado antes de sobrescrever;
- substituição de servidores com sobreposição e recuperação local criptografada;
- a mesma interface legível por máquinas para CLI e MCP stdio local.

A base atual é um VPS Ubuntu 24.04 amd64 dedicado e reconstruível, com acesso SSH autorizado por chave. Consulte [Compatibility](docs/COMPATIBILITY.md) para os protocolos, clientes e topologias exatos.

## Efeitos no host e privacidade

A preparação inicial altera firewall, swap, SSH, sysctl, logs, atualizações, pacotes e monitoramento de todo o host. Estado operacional, chaves, arquivos gerados e arquivos de recuperação ficam no diretório private escolhido e fora do Git. Um runtime de IA na nuvem pode processar endereço do servidor, usuário SSH, caminho da chave e IDs enviados como argumentos; use um runtime offline quando esses dados precisarem ficar locais.

Use somente servidores, contas e recursos de rede próprios ou que você tenha autorização para administrar. O Route Steward usa [AGPL-3.0-only](LICENSE); a atribuição MIT do gerador de QR está em [client/vendor/NOTICE.md](client/vendor/NOTICE.md).
