# Private Proxy Manager

[English](README.md) · [简体中文](README.zh-CN.md) · [日本語](README.ja.md) · [Español](README.es.md) · [Português (Brasil)](README.pt-BR.md)

[Inicio rápido](docs/QUICKSTART.md) · [Preguntas frecuentes](docs/FAQ.md) · [Compatibilidad](docs/COMPATIBILITY.md) · [Seguridad](SECURITY.md) · [AGPL-3.0-only](LICENSE)

[![Validation](https://github.com/squarepots/private-proxy-manager/actions/workflows/ci.yml/badge.svg)](https://github.com/squarepots/private-proxy-manager/actions/workflows/ci.yml)

Private Proxy Manager (PPM) ayuda a un AI agent a construir y mantener rutas proxy privadas en servidores bajo tu control. Conserva el plan de red deseado y las credenciales en un directorio local privado, despliega el stack de servidor compatible mediante SSH, crea configuraciones de cliente, audita las rutas activas y guía la sustitución de servidores sin desactivar primero la ruta que funciona.

Tú proporcionas los servidores, el acceso SSH y un cliente proxy compatible. PPM aporta la capa operativa repetible que los conecta.

## Empieza con un AI agent

Entrega la URL de este repositorio a Codex o a otro agent que pueda leer archivos locales y ejecutar PowerShell, y usa este prompt:

> Abre <https://github.com/squarepots/private-proxy-manager> y opera PPM por mí. Si no está en local, clónalo primero. Lee AGENTS.md y el repository Skill antes de actuar. Inspecciona el capability surface y ejecuta la validación local rápida. Después explícame qué necesito para mi primera ruta y cuáles son los efectos sobre todo el host antes de pedirme datos reales del servidor. Mantén las credenciales y los archivos de cliente generados en el directorio private ignorado por Git, ejecuta preflight antes de cada cambio y muéstrame únicamente resultados sanitizados.

Las primeras comprobaciones seguras del agent son:

```powershell
pwsh -NoProfile -File .\agent\ppm-agent.ps1 capabilities
pwsh -NoProfile -File .\scripts\Validate-Local.ps1 -Quick
```

Capability discovery es la fuente de verdad legible por máquinas. El repository Skill explica cómo recopilar contexto, iniciar un estado local neutro, crear los objetos necesarios, validar cada cambio e informar del resultado sin exponer secrets.

## Qué necesitas

- un equipo local con un AI agent capaz de usar herramientas y PowerShell 7;
- uno o dos VPS Ubuntu 24.04 amd64 dedicados y reconstruibles;
- acceso SSH con un Unix username válido y una private-key path;
- software compatible con Mihomo/Clash Verge o Shadowrocket como cliente.

Node.js y Wrangler solo son necesarios para la entrega opcional de suscripciones privadas con Cloudflare. 7-Zip solo es necesario para copias de seguridad cifradas y recovery.

PPM prepara el servidor completo; utiliza un host dedicado y no uno compartido con una carga de producción existente.

## Qué hace PPM por ti

- construye una direct Hysteria2 route o una ruta relay WireGuard de un salto;
- mantiene la intención de Server, Route, Provider, Profile y ClientTarget en un inventory local validado;
- genera archivos compatibles con Mihomo/Clash e imports de Shadowrocket;
- publica opcionalmente una private Shadowrocket subscription por cada ClientTarget aislado;
- compara el desired state con remote evidence acotada e informa de drift tipado;
- sustituye infraestructura con un enfoque overlap-first, conservando la capacidad existente hasta validar el reemplazo;
- crea recovery archives cifrados que no dependen del historial del chat.

Un bootstrap limpio no presupone geografía, Provider, policy, client, subscription ni proveedor de IA. El agent solo pregunta por los hechos que requiere la ruta que realmente quieres.

## Efectos sobre el host

El primer despliegue prepara un host Ubuntu dedicado y puede:

- instalar `ufw`, `unattended-upgrades`, `vnstat`, `mtr`, `curl`, `jq`, `openssl` y paquetes relacionados;
- crear un `/swapfile` de 1 GiB y hacerlo persistente en `/etc/fstab`;
- establecer y activar los valores predeterminados de UFW, proteger SSH y bloquear los puertos SMTP salientes 25, 465 y 587;
- instalar configuración con nombres de PPM para SSH, sysctl, BBR, journald, unattended-upgrades y módulos;
- crear servicios, runtime users, interfaces WireGuard, configuración y credenciales de PPM.

Uninstall elimina los servicios, interfaces, archivos y policy files con nombre que pertenecen a PPM. Conserva los paquetes, swap y configuraciones previas desconocidas del host porque no sería seguro reconstruir una configuración anterior. Consulta [Operations](OPERATIONS.md) para conocer el ownership boundary exacto.

## Cómo es un resultado correcto

```text
route               direct / route-a
server              byo-ssh / Ubuntu 24.04 amd64 / dedicated
client target       mihomo / desktop-a
remote audit        healthy
drift               none
private artifact    <private>/delivery/desktop-a.yaml
```

Es una forma sintética de ejemplo. Los resultados del agent y de MCP devuelven identidades de artifact relativas a la raíz privada, no letras de unidad de Windows, directorios de usuario, claves SSH, Provider URLs, tokens ni diagnósticos remotos sin procesar.

## Stack compatible

El stack probado actualmente es:

- hosts dedicados Ubuntu 24.04 amd64 a los que se accede mediante BYO SSH;
- Hysteria2 ingress;
- topología directa y relay WireGuard de un salto;
- Mihomo HTTP Providers genéricos opcionales;
- renderizado compatible con Mihomo/Clash Verge y Shadowrocket;
- entrega opcional mediante Cloudflare Worker con alcance de ClientTarget.

Consulta [Compatibility](docs/COMPATIBILITY.md) para ver el capability contract completo. Si un protocolo, host, renderer o tipo de Provider no aparece allí ni en capability discovery, PPM no lo implementa.

## Privacidad y autoridad

El motor determinista de PPM no sube el private state, pero un AI runtime en la nube puede recibir operation arguments como la dirección del servidor, el SSH username, la key path y los ID seleccionados. Usa ID no identificativos y elige un runtime offline cuando esos argumentos deban permanecer en tu equipo.

El private inventory, las credenciales, los archivos de cliente generados, la observed evidence y los recovery archives son datos locales sensibles. Protege el directorio private con permisos del sistema operativo y copias de seguridad, y nunca pegues su contenido en issues ni chats.

Cada mutation se comprueba mediante preflight local. Si falta contexto o hay conflictos, la ejecución se bloquea. La rotación del subscription token exige aprobación actual explícita, los cambios remotos permanecen dentro del ownership boundary de PPM y la migración de infraestructura es overlap-first. Los límites de privacidad de red y la respuesta ante compromisos se documentan en [Privacy](docs/PRIVACY.md), [Security](SECURITY.md) y [Threat model](docs/THREAT-MODEL.md).

## Más información

- [Quickstart](docs/QUICKSTART.md): entrega la URL a un agent y completa el primer workflow seguro.
- [FAQ](docs/FAQ.md): respuestas claras sobre hosts, visibilidad para la IA, recovery, drift y clientes.
- [Architecture](ARCHITECTURE.md): object model y límites deterministas.
- [Contributing](CONTRIBUTING.md): contrato de desarrollo y validación.
- [Releasing](docs/RELEASING.md): proceso de versionado y release.

PPM se distribuye bajo la licencia [AGPL-3.0-only](LICENSE). El generador QR vendored conserva su atribución MIT en [client/vendor/NOTICE.md](client/vendor/NOTICE.md).
