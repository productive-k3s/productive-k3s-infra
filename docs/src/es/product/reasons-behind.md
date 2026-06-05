# Razones Del Diseño De `productive-k3s-infra`

`productive-k3s-infra` existe porque la ejecución de profiles empaquetados y el authoring de contenido fuente resuelven problemas distintos.

## Por qué no alcanza con `productive-k3s-core`

`productive-k3s-core` es el contrato de bootstrap para instalar y validar un stack basado en K3S.

Eso alcanza cuando:

- ya existe un host
- el operador puede trabajar directamente sobre esa máquina
- la topología del clúster es lo bastante simple como para armarla a mano

No alcanza cuando además necesitás un contrato reutilizable de runtime para:

- extracción de paquetes
- merge de env y validación de inputs
- persistencia y restauración del state de runtime
- propagación de telemetría
- dispatch de comandos entre operaciones repetidas sobre profiles

## Por qué separar el engine del contenido público de profiles

Este repositorio está centrado intencionalmente en el engine de runtime, no en ser dueño del árbol público `profiles/` y `scenarios/`.

La separación existe para que:

- cambiar un profile público no fuerce un nuevo bundle de Infra
- `productive-k3s-infra` pueda validar compatibilidad contra `productive-k3s-profiles` sin ser dueño del contenido
- `productive-k3s-ops` pueda empaquetar artefactos públicos `profile.tgz` desde un repositorio fuente limpio

## Por qué sigue existiendo el engine

Incluso después del split fuente, los profiles publicados siguen necesitando una capa compartida de ejecución en la que todos puedan apoyarse:

- extracción de `profile.tgz`
- merge de env y validación de inputs
- persistencia y restauración de state de runtime
- propagación de telemetría
- dispatch de comandos y comportamiento de recuperación

Sin esa capa, el engine volvería a volverse específico por scenario o cada profile empaquetado tendría que reimplementar la misma lógica de runtime.

## Por qué sigue importando la separación explícita por modos

Los modos `server`, `agent`, `stack` y `single-node` expuestos por `productive-k3s-core` siguen siendo lo que vuelve realista la ejecución de profiles.

Le permiten a Infra:

1. entregar el state de runtime correcto al profile empaquetado
2. delegar el bootstrap del clúster a Core en fases estables
3. preservar un modelo reutilizable de ejecución entre distintos artefactos de profile

## Racional general

Tomado como conjunto, el repositorio busca ofrecer:

- un contrato reutilizable de runtime para todos los profiles publicados
- puntos de integración explícitos con `productive-k3s-profiles`
- un puente estable de ejecución hacia entornos K3S reales, remotos o multinodo

## Ver también

- [Resumen del producto](index.md)
- [Cómo usar Productive K3S Infra](how-to-use.md)
- [Relación con Productive K3S Profiles y Core](productive-k3s-relationship.md)
