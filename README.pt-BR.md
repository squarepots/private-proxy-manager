# Route Steward

[English](README.md) · [简体中文](README.zh-CN.md) · [日本語](README.ja.md) · [Español](README.es.md) · [Português (Brasil)](README.pt-BR.md)

[Quickstart](docs/QUICKSTART.md) · [FAQ](docs/FAQ.md) · [Compatibility](docs/COMPATIBILITY.md) · [Operating boundary](docs/OPERATING-BOUNDARY.md) · [Security](SECURITY.md) · [Releases](https://github.com/squarepots/route-steward/releases)

[![Validation](https://github.com/squarepots/route-steward/actions/workflows/ci.yml/badge.svg)](https://github.com/squarepots/route-steward/actions/workflows/ci.yml)

**Configure e gerencie proxies privados nos seus próprios servidores com um agente de IA.**

Entregue este repositório a um agente de IA e descreva o proxy desejado. O Route Steward fornece os comandos, verificações de segurança, configuração do servidor, arquivos de cliente, auditorias e recuperação.

## Entregue a URL a um agente de IA

```text
Abra https://github.com/squarepots/route-steward e ajude-me a configurar e gerenciar um proxy privado em servidores que controlo. Leia AGENTS.md e .agents/skills/route-steward/SKILL.md, use a versão publicada do Route Steward adequada para este computador e comece com route-steward capabilities.
```

Consulte o [guia de início](docs/QUICKSTART.md) para instalação e pré-requisitos.

## O que você recebe

- um proxy Hysteria2 privado por um servidor ou uma conexão WireGuard entre dois servidores;
- salto de portas opcional para redes que limitam ou filtram portas UDP específicas;
- arquivos privados para clientes compatíveis com Mihomo/Clash Verge, Karing, Shadowrocket e Hysteria2 sem interface gráfica;
- auditorias do servidor, relatórios de alterações de configuração e testes reais de tráfego sob demanda;
- substituição retomável do servidor que testa o novo caminho antes de trocar os clientes;
- backups locais criptografados e recuperação;
- comandos JSON pela linha de comando ou pelo MCP stdio local.

A base atual é um VPS Ubuntu 24.04 amd64 dedicado e reconstruível, com acesso SSH autorizado por chave. Consulte [Compatibility](docs/COMPATIBILITY.md) para os protocolos, clientes e topologias exatos.

## Efeitos no host e privacidade

A preparação inicial altera firewall, swap, SSH, parâmetros do sistema, logs, atualizações, pacotes e monitoramento de todo o host. Use um servidor dedicado que possa ser reconstruído.

Estado operacional, chaves, arquivos gerados e backups ficam no diretório privado escolhido e fora do Git. Um serviço de IA na nuvem pode receber os dados do servidor necessários para uma operação; use um ambiente offline quando eles precisarem ficar locais.

Use somente servidores, contas e recursos de rede próprios ou que você tenha autorização para administrar. O Route Steward usa [AGPL-3.0-only](LICENSE); a atribuição MIT do gerador de QR está em [client/vendor/NOTICE.md](client/vendor/NOTICE.md).
