# Route Steward

[English](README.md) · [简体中文](README.zh-CN.md) · [日本語](README.ja.md) · [Español](README.es.md) · [Português (Brasil)](README.pt-BR.md)

[Quickstart](docs/QUICKSTART.md) · [FAQ](docs/FAQ.md) · [Compatibility](docs/COMPATIBILITY.md) · [Operating boundary](docs/OPERATING-BOUNDARY.md) · [Security](SECURITY.md) · [Releases](https://github.com/squarepots/route-steward/releases)

[![Validation](https://github.com/squarepots/route-steward/actions/workflows/ci.yml/badge.svg)](https://github.com/squarepots/route-steward/actions/workflows/ci.yml)

**Configura y gestiona proxies privados en tus propios servidores con un agente de IA.**

Entrega este repositorio a un agente de IA y describe el proxy que necesitas. Route Steward aporta los comandos, controles de seguridad, configuración del servidor, archivos de cliente, auditorías y recuperación.

## Entrega la URL a un agente de IA

```text
Abre https://github.com/squarepots/route-steward y ayúdame a configurar y gestionar un proxy privado en servidores que controlo. Lee AGENTS.md y .agents/skills/route-steward/SKILL.md, usa la versión publicada de Route Steward adecuada para este equipo y empieza con route-steward capabilities.
```

Consulta la [guía de inicio](docs/QUICKSTART.md) para instalarlo y preparar los requisitos.

## Qué obtienes

- un proxy Hysteria2 privado mediante un servidor o un enlace WireGuard entre dos servidores;
- salto de puertos opcional para redes que limitan o filtran puertos UDP concretos;
- archivos privados para clientes Mihomo/Clash Verge compatibles, Karing, Shadowrocket y Hysteria2 sin interfaz gráfica;
- auditorías del servidor, informes de cambios de configuración y comprobaciones reales de tráfico bajo demanda;
- sustitución reanudable del servidor que prueba la nueva ruta antes de cambiar los clientes;
- copias de seguridad locales cifradas y recuperación;
- comandos JSON mediante la línea de órdenes o MCP stdio local.

La base actual es un VPS Ubuntu 24.04 amd64 dedicado y reconstruible con acceso SSH autorizado por clave. Consulta [Compatibility](docs/COMPATIBILITY.md) para conocer protocolos, clientes y topologías exactos.

## Efectos en el host y privacidad

La preparación inicial modifica el cortafuegos, el espacio de intercambio, SSH, los parámetros del sistema, los registros, las actualizaciones, los paquetes y la monitorización del host. Usa un servidor dedicado que puedas reconstruir.

El estado, las claves, los archivos generados y las copias de recuperación permanecen en el directorio privado elegido y fuera de Git. Un servicio de IA en la nube puede recibir los datos del servidor necesarios para una operación; usa un entorno sin conexión cuando deban permanecer locales.

Usa únicamente servidores, cuentas y recursos de red propios o cuya administración tengas autorizada. Route Steward usa [AGPL-3.0-only](LICENSE); la atribución MIT del generador QR está en [client/vendor/NOTICE.md](client/vendor/NOTICE.md).
