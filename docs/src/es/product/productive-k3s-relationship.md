# Relación Con Productive K3S Profiles Y Core

`productive-k3s-infra`, `productive-k3s-profiles` y `productive-k3s-core` tienen responsabilidades distintas.

## Qué hace Productive K3S Core

`productive-k3s-core` es el proyecto de bootstrap del clúster. Es responsable de:

- instalar `k3s`
- armar el modo de clúster seleccionado
- instalar componentes compartidos del stack
- validar el comportamiento del stack resultante

## Qué hace Productive K3S Infra

`productive-k3s-infra` es el engine de runtime. Es responsable de:

- ejecutar artefactos empaquetados `profile.tgz`
- mergear defaults del paquete con overrides locales
- persistir y restaurar state de runtime
- dispatch de comandos, manejo de errores y telemetría

## Qué hace Productive K3S Profiles

`productive-k3s-profiles` es dueño del contenido fuente público que define el contexto de infraestructura alrededor de esas fases:

- `profiles/` y `scenarios/` públicos
- expectativas de metadata generada y scripts auxiliares
- sidecars de metadata de paquete y defaults
- flujos source-based de validación y authoring

## Interfaz compartida de bootstrap

El engine de runtime trata a los modos de ejecución de `productive-k3s-core` como la interfaz pública de bootstrap:

- `single-node`
- `server`
- `agent`
- `stack`

Los profiles publicados consumen esos modos de forma distinta según su topología y comportamiento de scenario.

## Por qué importa la separación

Esta separación mantiene reemplazables ambos lados.

Podés cambiar:

- cómo evoluciona el engine de runtime
- dónde se authoring el contenido público de scenarios
- cómo se publican los paquetes

sin redefinir cada vez el contrato central de bootstrap del clúster.
