# Route Steward

[English](README.md) · [简体中文](README.zh-CN.md) · [日本語](README.ja.md) · [Español](README.es.md) · [Português (Brasil)](README.pt-BR.md)

[Quickstart](docs/QUICKSTART.md) · [FAQ](docs/FAQ.md) · [Compatibility](docs/COMPATIBILITY.md) · [Operating boundary](docs/OPERATING-BOUNDARY.md) · [Security](SECURITY.md) · [AGPL-3.0-only](LICENSE)

[![Validation](https://github.com/squarepots/route-steward/actions/workflows/ci.yml/badge.svg)](https://github.com/squarepots/route-steward/actions/workflows/ci.yml)

**Usa IA para gestionar la red de tus propios servidores.**

Route Steward te ayuda a desplegar, comprobar, migrar y recuperar conexiones de red en los servidores que administras. Tú proporcionas los servidores, las cuentas y la autorización; Route Steward ofrece a un agente de IA con herramientas una forma repetible y validada de operarlos desde tu equipo local.

![Diagrama sintético de Route Steward que separa el plano de control operado por IA de las rutas de tráfico directas y relay mediante Entry-A y el Relay-A opcional.](docs/assets/network-path-lifecycle.svg)

## Empieza con un agente de IA

Pega este prompt en Codex o en otro agente capaz de leer archivos y ejecutar PowerShell:

```text
Abre https://github.com/squarepots/route-steward y ayúdame a gestionar la red de mis propios servidores con IA. Clónalo si hace falta, lee AGENTS.md y el repository Skill, inspecciona capabilities y ejecuta la validación local rápida. Antes de pedirme datos de infraestructura, explica los requisitos del host dedicado, los efectos sobre todo el host y el operating boundary. Mantén el estado sensible en private, ejecuta preflight antes de los cambios y devuelve resultados sanitizados.
```

```powershell
pwsh -NoProfile -File .\agent\route-steward-agent.ps1 capabilities
pwsh -NoProfile -File .\scripts\Validate-Local.ps1 -Quick
```

## Qué necesitas

- un equipo local con PowerShell 7 y un agente de IA con herramientas;
- uno o dos servidores Ubuntu 24.04 amd64 dedicados y reconstruibles;
- acceso SSH autorizado con usuario Unix y ruta a la clave privada;
- software compatible con Mihomo/Clash Verge o Shadowrocket.

Route Steward prepara todo el servidor, por lo que cada host administrado debe dedicarse a esta configuración de red.

## Qué hace Route Steward

Crea y valida la configuración del servidor y del cliente, comprueba el estado activo, ayuda a sustituir infraestructura sin descartar primero la conexión existente y genera archivos de recuperación cifrados.

[Compatibility](docs/COMPATIBILITY.md) enumera los hosts, protocolos, clientes, topologías y la entrega opcional mediante Cloudflare que están soportados actualmente.

## Efectos en el host y privacidad

La instalación cambia la configuración global de firewall, swap, SSH, sistema, registros, actualizaciones y monitorización. El estado sensible y los archivos generados permanecen en el directorio private local elegido; cada cambio requiere un preflight listo. Lee [Operations](OPERATIONS.md), [Privacy](docs/PRIVACY.md) y [Security](SECURITY.md).

Usa únicamente servidores, cuentas y recursos de red propios o cuya administración tengas autorizada. Consulta [Operating boundary](docs/OPERATING-BOUNDARY.md).

Route Steward se distribuye bajo [AGPL-3.0-only](LICENSE). La atribución MIT del generador QR incluido permanece en [client/vendor/NOTICE.md](client/vendor/NOTICE.md).
