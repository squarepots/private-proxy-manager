# Private Proxy Manager

[English](README.md) · [简体中文](README.zh-CN.md) · [日本語](README.ja.md) · [Español](README.es.md) · [Português (Brasil)](README.pt-BR.md)

[Início rápido](docs/QUICKSTART.md) · [Perguntas frequentes](docs/FAQ.md) · [Compatibilidade](docs/COMPATIBILITY.md) · [Segurança](SECURITY.md) · [AGPL-3.0-only](LICENSE)

[![Validation](https://github.com/squarepots/private-proxy-manager/actions/workflows/ci.yml/badge.svg)](https://github.com/squarepots/private-proxy-manager/actions/workflows/ci.yml)

Private Proxy Manager (PPM) ajuda um AI agent a criar e manter rotas de proxy privadas em servidores sob seu controle. Ele mantém o plano de rede desejado e as credenciais em um diretório local privado, implanta o stack de servidor compatível por SSH, cria configurações de cliente, audita as rotas ativas e orienta a substituição de servidores sem derrubar primeiro a rota que está funcionando.

Você fornece os servidores, o acesso SSH e um cliente de proxy compatível. O PPM fornece a camada operacional repetível entre eles.

## Comece com um AI agent

Entregue a URL deste repositório ao Codex ou a outro agent capaz de ler arquivos locais e executar PowerShell, e use este prompt:

> Abra <https://github.com/squarepots/private-proxy-manager> e opere o PPM para mim. Se ele não estiver local, faça o clone primeiro. Leia AGENTS.md e o repository Skill antes de agir. Inspecione o capability surface e execute a validação local rápida. Depois, explique o que preciso para minha primeira rota e os efeitos em todo o host antes de pedir dados reais dos servidores. Mantenha credenciais e arquivos de cliente gerados no diretório private ignorado pelo Git, execute preflight antes de cada mudança e mostre somente resultados sanitizados.

As primeiras verificações seguras do agent são:

```powershell
pwsh -NoProfile -File .\agent\ppm-agent.ps1 capabilities
pwsh -NoProfile -File .\scripts\Validate-Local.ps1 -Quick
```

Capability discovery é a fonte de verdade legível por máquina. O repository Skill orienta o agent a coletar contexto, inicializar um estado local neutro, criar os objetos necessários, validar cada mudança e relatar o resultado sem expor secrets.

## O que você precisa

- um computador local com um AI agent capaz de usar ferramentas e PowerShell 7;
- um ou dois VPS Ubuntu 24.04 amd64 dedicados e reconstruíveis;
- acesso SSH com um Unix username válido e uma private-key path;
- software compatível com Mihomo/Clash Verge ou Shadowrocket como cliente.

Node.js e Wrangler são necessários apenas para a entrega opcional de uma assinatura privada pelo Cloudflare. 7-Zip é necessário apenas para backup criptografado e recovery.

O PPM prepara o servidor inteiro; use um host dedicado, não um servidor compartilhado com uma carga de produção existente.

## O que o PPM faz por você

- cria uma direct Hysteria2 route ou uma rota relay WireGuard de um salto;
- mantém a intenção de Server, Route, Provider, Profile e ClientTarget em um inventory local validado;
- gera arquivos compatíveis com Mihomo/Clash e imports do Shadowrocket;
- publica opcionalmente uma private Shadowrocket subscription por ClientTarget isolado;
- compara o desired state com remote evidence limitada e informa drift tipado;
- substitui infraestrutura com estratégia overlap-first, mantendo a capacidade existente até validar a substituição;
- cria recovery archives criptografados que não dependem do histórico do chat.

Um bootstrap limpo não presume geografia, Provider, policy, client, subscription nem fornecedor de IA. O agent pergunta apenas pelos fatos necessários para a rota que você realmente quer.

## Efeitos no host

A implantação inicial prepara um host Ubuntu dedicado e pode:

- instalar `ufw`, `unattended-upgrades`, `vnstat`, `mtr`, `curl`, `jq`, `openssl` e pacotes relacionados;
- criar um `/swapfile` de 1 GiB e persistir a configuração em `/etc/fstab`;
- configurar e habilitar os padrões do UFW, proteger SSH e bloquear as portas SMTP de saída 25, 465 e 587;
- instalar configurações identificadas pelo PPM para SSH, sysctl, BBR, journald, unattended-upgrades e módulos;
- criar serviços, runtime users, interfaces WireGuard, configurações e credenciais do PPM.

Uninstall remove serviços, interfaces, arquivos e policy files nomeados que pertencem ao PPM. Pacotes, swap e configurações anteriores desconhecidas do host permanecem, pois não seria seguro reconstruir uma configuração anterior. Consulte [Operations](OPERATIONS.md) para conhecer o ownership boundary exato.

## Como é um resultado bem-sucedido

```text
route               direct / route-a
server              byo-ssh / Ubuntu 24.04 amd64 / dedicated
client target       mihomo / desktop-a
remote audit        healthy
drift               none
private artifact    <private>/delivery/desktop-a.yaml
```

Esse é um formato sintético. Os resultados do agent e do MCP retornam identidades de artifact relativas à raiz privada, e não letras de unidade do Windows, diretórios de usuário, chaves SSH, Provider URLs, tokens ou diagnósticos remotos brutos.

## Stack compatível

O stack testado atualmente é:

- hosts dedicados Ubuntu 24.04 amd64 acessados por BYO SSH;
- Hysteria2 ingress;
- topologia direta e relay WireGuard de um salto;
- Mihomo HTTP Providers genéricos opcionais;
- renderização compatível com Mihomo/Clash Verge e Shadowrocket;
- entrega opcional por Cloudflare Worker com escopo de ClientTarget.

Consulte [Compatibility](docs/COMPATIBILITY.md) para o capability contract completo. Se um protocolo, host, renderer ou tipo de Provider não estiver documentado ali nem aparecer em capability discovery, o PPM não o implementa.

## Privacidade e autoridade

O mecanismo determinístico do PPM não envia o private state, mas um AI runtime em nuvem pode receber operation arguments como endereço do servidor, SSH username, key path e IDs selecionados. Use IDs não identificadores e escolha um runtime offline quando esses argumentos precisarem permanecer no seu computador.

Private inventory, credenciais, arquivos de cliente gerados, observed evidence e recovery archives são dados locais sensíveis. Proteja o diretório private com permissões do sistema operacional e backups, e nunca cole seu conteúdo em issues ou chats.

Toda mutation passa por um preflight local. Contexto ausente ou conflitante bloqueia a execução. A rotação do subscription token exige aprovação atual explícita, as mudanças remotas permanecem dentro do ownership boundary do PPM e a migração de infraestrutura segue a estratégia overlap-first. Os limites de privacidade da rede e as respostas a comprometimento estão em [Privacy](docs/PRIVACY.md), [Security](SECURITY.md) e [Threat model](docs/THREAT-MODEL.md).

## Saiba mais

- [Quickstart](docs/QUICKSTART.md): entregue a URL a um agent e conclua o primeiro workflow seguro.
- [FAQ](docs/FAQ.md): respostas claras sobre hosts, visibilidade para IA, recovery, drift e clientes.
- [Architecture](ARCHITECTURE.md): object model e limites determinísticos.
- [Contributing](CONTRIBUTING.md): contrato de desenvolvimento e validação.
- [Releasing](docs/RELEASING.md): processo de versionamento e release.

O PPM é licenciado sob a [AGPL-3.0-only](LICENSE). O gerador de QR vendored mantém sua atribuição MIT em [client/vendor/NOTICE.md](client/vendor/NOTICE.md).
