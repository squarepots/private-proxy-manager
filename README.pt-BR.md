# Route Steward

[English](README.md) · [简体中文](README.zh-CN.md) · [日本語](README.ja.md) · [Español](README.es.md) · [Português (Brasil)](README.pt-BR.md)

[Quickstart](docs/QUICKSTART.md) · [FAQ](docs/FAQ.md) · [Compatibility](docs/COMPATIBILITY.md) · [Operating boundary](docs/OPERATING-BOUNDARY.md) · [Security](SECURITY.md) · [Releases](https://github.com/squarepots/route-steward/releases)

[![Validation](https://github.com/squarepots/route-steward/actions/workflows/ci.yml/badge.svg)](https://github.com/squarepots/route-steward/actions/workflows/ci.yml)

**Configure e gerencie proxies privados nos seus próprios servidores com um agente de IA.**

O Route Steward ajuda um agente de IA a configurar, inspecionar, trocar e recuperar um proxy privado em servidores VPS que você controla. Entregue esta URL do GitHub: o agente pode descobrir o fluxo suportado, verificar os requisitos antes de cada mudança, operar pelo binário nativo `route-steward` e retornar resultados sanitizados sem expor credenciais ou caminhos locais.

## Entregue a URL a um agente de IA

```text
Abra https://github.com/squarepots/route-steward e ajude-me a configurar e gerenciar um proxy privado nos meus próprios servidores. Clone o repositório se necessário, leia AGENTS.md e .agents/skills/route-steward/SKILL.md e depois use um binário Release do Route Steward já instalado ou baixe o arquivo Release correto e verifique-o com SHA256SUMS. Não me peça para instalar Go no uso normal. Execute capabilities antes de pedir dados de infraestrutura. Explique os requisitos de host dedicado e os efeitos no sistema, mantenha o estado operacional privado, execute preflight antes de cada mudança e devolva apenas resultados sanitizados.
```

```text
route-steward capabilities
route-steward bootstrap --private-dir ./private
route-steward context --private-dir ./private
```

O uso normal não exige PowerShell, Node.js nem a ferramenta Go. Baixe o binário verificado para Linux, macOS ou Windows em [Releases](https://github.com/squarepots/route-steward/releases). O desenvolvimento a partir do código-fonte exige Go 1.27:

```text
go run ./cmd/route-steward capabilities
go test ./...
```

Node.js só é usado quando você escolhe a entrega opcional de assinatura pelo Cloudflare Worker.

## O que você recebe

- um proxy Hysteria2 privado por um servidor ou um relay WireGuard opcional por dois;
- configuração privada completa para um app compatível com Mihomo/Clash Verge, incluindo regras opcionais por processo, Karing, Shadowrocket ou um proxy sem GUI para Linux/aplicações;
- auditoria de servidor somente leitura, health real e sob demanda do tráfego cliente e drift de configuração tipado;
- substituição retomável de servidor com sobreposição, troca de clientes condicionada por health e sem aposentadoria automática;
- recuperação local criptografada com estado privado verificado e realocável;
- a mesma interface legível por máquinas para CLI e MCP stdio local.

A base atual é um VPS Ubuntu 24.04 amd64 dedicado e reconstruível, com acesso SSH autorizado por chave. Consulte [Compatibility](docs/COMPATIBILITY.md) para os protocolos, clientes e topologias exatos.

## Efeitos no host e privacidade

A preparação inicial altera firewall, swap, SSH, sysctl, logs, atualizações, pacotes e monitoramento de todo o host. Estado operacional, chaves, arquivos gerados e arquivos de recuperação ficam no diretório private escolhido e fora do Git. Um runtime de IA na nuvem pode processar endereço do servidor, usuário SSH, caminho da chave e IDs enviados como argumentos; use um runtime offline quando esses dados precisarem ficar locais.

Use somente servidores, contas e recursos de rede próprios ou que você tenha autorização para administrar. O Route Steward usa [AGPL-3.0-only](LICENSE); a atribuição MIT do gerador de QR está em [client/vendor/NOTICE.md](client/vendor/NOTICE.md).
