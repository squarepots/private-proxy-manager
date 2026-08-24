# Route Steward

[English](README.md) · [简体中文](README.zh-CN.md) · [日本語](README.ja.md) · [Español](README.es.md) · [Português (Brasil)](README.pt-BR.md)

[Quickstart](docs/QUICKSTART.md) · [FAQ](docs/FAQ.md) · [Compatibility](docs/COMPATIBILITY.md) · [Operating boundary](docs/OPERATING-BOUNDARY.md) · [Security](SECURITY.md) · [Releases](https://github.com/squarepots/route-steward/releases)

[![Validation](https://github.com/squarepots/route-steward/actions/workflows/ci.yml/badge.svg)](https://github.com/squarepots/route-steward/actions/workflows/ci.yml)

**Configura y gestiona proxies privados en tus propios servidores con un agente de IA.**

Route Steward ayuda a un agente de IA a configurar, inspeccionar, cambiar y recuperar un proxy privado en servidores VPS que controlas. Dale esta URL de GitHub: el agente puede descubrir el flujo compatible, comprobar los requisitos antes de cada cambio, operar con el binario nativo `route-steward` y devolver resultados depurados sin exponer credenciales ni rutas locales.

![Route Steward convierte una petición de IA en un proxy privado mediante un servidor o un relay opcional de dos servidores, con auditoría de servidor y configuración privada para la aplicación cliente.](docs/assets/network-path-lifecycle.svg)

## Entrega la URL a un agente de IA

```text
Abre https://github.com/squarepots/route-steward y ayúdame a configurar y gestionar un proxy privado en mis propios servidores. Clona el repositorio si hace falta, lee AGENTS.md y .agents/skills/route-steward/SKILL.md, y usa el binario publicado o compila la CLI en Go. Ejecuta capabilities antes de pedir datos de infraestructura. Explica los requisitos de host dedicado y los efectos sobre el sistema, conserva el estado operativo en privado, ejecuta preflight antes de cada cambio y devuelve resultados depurados.
```

```text
route-steward capabilities
route-steward bootstrap --private-dir ./private
route-steward context --private-dir ./private
```

El uso normal no requiere PowerShell ni Node.js. Descarga el binario verificado para Linux, macOS o Windows desde [Releases](https://github.com/squarepots/route-steward/releases), o instálalo desde el código fuente con Go 1.27:

```text
go install github.com/squarepots/route-steward/cmd/route-steward@latest
```

Node.js solo se usa si eliges la entrega opcional de suscripciones mediante Cloudflare Worker.

## Qué obtienes

- un proxy Hysteria2 privado mediante un servidor o un relay WireGuard opcional mediante dos;
- configuración privada completa para una aplicación compatible con Mihomo/Clash Verge o Shadowrocket;
- auditoría de servidor de solo lectura, health real y bajo demanda del tráfico cliente, y drift de configuración tipado;
- reemplazo reanudable de servidores con solapamiento, cambio de clientes condicionado por health y sin retiro automático;
- un flujo de sustitución con solapamiento y recuperación local cifrada;
- una misma interfaz legible por máquinas para CLI y MCP stdio local.

La base actual es un VPS Ubuntu 24.04 amd64 dedicado y reconstruible con acceso SSH autorizado por clave. Consulta [Compatibility](docs/COMPATIBILITY.md) para conocer protocolos, clientes y topologías exactos.

## Efectos en el host y privacidad

La preparación inicial modifica firewall, swap, SSH, sysctl, registros, actualizaciones, paquetes y monitorización de todo el host. El estado operativo, las claves, los archivos generados y los archivos de recuperación permanecen en el directorio private elegido y fuera de Git. Un runtime de IA en la nube puede procesar la dirección del servidor, el usuario SSH, la ruta de la clave y los ID enviados como argumentos; usa un runtime offline si deben permanecer locales.

Usa únicamente servidores, cuentas y recursos de red propios o cuya administración tengas autorizada. Route Steward usa [AGPL-3.0-only](LICENSE); la atribución MIT del generador QR está en [client/vendor/NOTICE.md](client/vendor/NOTICE.md).
