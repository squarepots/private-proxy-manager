# Route Steward

[English](README.md) · [简体中文](README.zh-CN.md) · [日本語](README.ja.md) · [Español](README.es.md) · [Português (Brasil)](README.pt-BR.md)

[Quickstart](docs/QUICKSTART.md) · [FAQ](docs/FAQ.md) · [Compatibility](docs/COMPATIBILITY.md) · [Operating boundary](docs/OPERATING-BOUNDARY.md) · [Security](SECURITY.md) · [AGPL-3.0-only](LICENSE)

[![Validation](https://github.com/squarepots/route-steward/actions/workflows/ci.yml/badge.svg)](https://github.com/squarepots/route-steward/actions/workflows/ci.yml)

**Dile a tu IA cómo debe funcionar tu ruta de red. Route Steward se encarga de mantenerla.**

Route Steward es un gestor local-first del ciclo de vida de rutas de red autoalojadas. Un agente de IA con acceso a herramientas convierte la conectividad deseada sobre infraestructura controlada por el operador en estado validado, despliegue, configuración de clientes, auditoría, detección de drift, migración y recuperación.

Route Steward parte de la conectividad a Internet entre los extremos seleccionados. Internet aporta el transporte; tú aportas los servidores, las cuentas y la autorización sobre los recursos de red; Route Steward aporta una capa operativa repetible.

![Diagrama sintético de Route Steward que separa el plano de control operado por IA de las rutas de tráfico directas y relay mediante Entry-A y el Relay-A opcional.](docs/assets/network-path-lifecycle.svg)

## Empieza con un agente de IA

Entrega la URL a Codex u otro agente capaz de leer archivos locales y ejecutar PowerShell:

```text
Abre https://github.com/squarepots/route-steward y opera Route Steward por mí. Clónalo si hace falta, lee AGENTS.md y el repository Skill, inspecciona capabilities y ejecuta la validación local rápida. Antes de pedirme datos de infraestructura, explica los requisitos del host dedicado, los efectos sobre todo el host y el operating boundary. Mantén el estado sensible en private, ejecuta preflight antes de los cambios y devuelve resultados sanitizados.
```

```powershell
pwsh -NoProfile -File .\agent\route-steward-agent.ps1 capabilities
pwsh -NoProfile -File .\scripts\Validate-Local.ps1 -Quick
```

## Recursos necesarios

- un equipo local con PowerShell 7 y un agente de IA con herramientas;
- uno o dos servidores Ubuntu 24.04 amd64 dedicados y reconstruibles;
- acceso SSH autorizado;
- software compatible con Mihomo/Clash Verge o Shadowrocket.

## Ciclo de vida administrado

- rutas directas Hysteria2 y rutas relay WireGuard de un salto;
- desired state para Server, Link, Route, Provider, Profile y ClientTarget;
- archivos compatibles con Mihomo/Clash e importaciones de Shadowrocket;
- entrega opcional y aislada de configuración por ClientTarget;
- auditoría remota, typed drift y migración overlap-first;
- archivos de recuperación cifrados.

## Condiciones de operación

Route Steward está diseñado para servidores, cuentas y recursos de red que el operador posee o está autorizado a administrar. Cada despliegue se configura de acuerdo con la legislación aplicable, los requisitos del operador de telecomunicaciones, las condiciones del proveedor cloud y las políticas de la organización. Consulta [Operating boundary](docs/OPERATING-BOUNDARY.md).

La capacidad implementada se documenta en [Compatibility](docs/COMPATIBILITY.md) y en capability discovery. Los límites de privacidad y autoridad se detallan en [Privacy](docs/PRIVACY.md), [Security](SECURITY.md) y [Threat model](docs/THREAT-MODEL.md).

Route Steward se distribuye bajo [AGPL-3.0-only](LICENSE).
