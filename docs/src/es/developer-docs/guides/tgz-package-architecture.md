# Arquitectura de Paquetes TGZ para Productive K3S

## Objetivo

Definir una arquitectura unificada y simétrica para:

- instalar add-ons en Core
- instalar profiles en Infra desde fuentes de scenario desacopladas
- distribuir paquetes `.tgz` desacoplados
- soportar catálogos públicos y privados
- ejecutar paquetes como artefactos autocontenidos
- mantener independiente la lógica del CLI y los runtimes

> Todo lo instalable en el ecosistema Productive K3S debe poder distribuirse y ejecutarse como un paquete autocontenido TGZ.

Esto aplica a:

- Add-ons (`productive-k3s-addons`)
- Profiles/Escenarios (`productive-k3s-profiles`)

## Conceptos clave

| Concepto | Significado |
|---|---|
| Scenario | motor de implementación reusable |
| Profile | preset/configuración lista para usar |
| Add-on | extensión instalable sobre Core |
| TGZ Package | unidad distribuible autocontenida |

## Intención arquitectónica

La arquitectura debe sentirse igual en todos los niveles.

### Ejemplo conceptual

| Capa | Recibe | Ejecuta |
|---|---|---|
| CLI | TGZ | delega |
| Core | Add-on TGZ | instala add-ons |
| Infra | Profile TGZ | ejecuta escenarios |
| Motor de scenario | definición YAML | corre la implementación |

## Filosofía

El CLI NO debe saber:

- lógica de instalación
- templates específicos
- motores cloud
- detalles internos
- charts de Helm particulares
- cómo instalar un add-on
- cómo ejecutar AWS/Azure/etc.

El CLI solamente:

1. descarga y resuelve paquetes
2. valida metadata
3. delega la ejecución al runtime adecuado

## Superficie pública y superficie de desarrollo

La arquitectura de Productive K3S expone dos superficies distintas de forma intencional:

- una superficie pública package-first para usuarios finales
- una superficie source-first de desarrollo para authoring, testing y CI

Estas dos superficies resuelven necesidades distintas y no son intercambiables.

### Superficie pública del CLI

`pk3s` es el CLI público.

Su contrato es package-oriented:

- los add-ons se consumen como `addon.tgz`
- los profiles se consumen como `profile.tgz`
- la resolución de catálogo debe terminar en un artefacto TGZ descargable

El CLI público no expone:

- archivos de profile `.env` crudos
- paths directos a scenarios
- atajos de desarrollo orientados al árbol fuente

### Superficie de desarrollo del runtime

`productive-k3s-core.sh` y `productive-k3s-infra.sh` son runtime tools.

Exponen:

- una superficie pública runtime orientada a paquetes
- una superficie explícita `dev` para flujos de desarrollo y testing

La superficie `dev` existe para que:

- autores de paquetes puedan iterar sobre source files sin generar un TGZ primero
- CI pueda validar contratos de authoring antes del empaquetado
- maintainers puedan testear profiles y add-ons directamente desde el árbol fuente

Esto significa que el contrato source-oriented de desarrollo sigue siendo válido, pero deja de ser el contrato principal expuesto al usuario.

## El paquete primero, el repositorio después

El repositorio es fuente de desarrollo, pero el runtime no debe depender del árbol de código fuente.

El runtime debe poder instalar o ejecutar desde un archivo `.tgz` local sin necesitar el repositorio completo.

Al mismo tiempo, el repositorio fuente sigue siendo el entorno de authoring.

Eso significa:

- el uso público es package-first
- el uso de desarrollo puede seguir siendo source-first bajo comandos `dev` explícitos
- el empaquetado es la frontera entre authoring y distribución

## Roles de los repositorios

- `productive-k3s-core`: runtime de instalación de add-ons
- `productive-k3s-addons`: catálogo público de add-ons
- `productive-k3s-addons-pro`: add-ons pagos/privados
- `productive-k3s-infra`: runtime/engine de empaquetado y ejecución de profiles
- `productive-k3s-profiles`: profiles y escenarios públicos
- `productive-k3s-profiles-pro`: profiles/escenarios pagos
- `productive-k3s-cli`: orquestador
- `productive-k3s-catalogs`: índices de paquetes publicados

## Formato TGZ de add-ons

Un paquete de add-on de Productive K3S es un archivo `.tgz` autocontenido con metadata y activos de instalación.

### Ejemplo de estructura

```text
addon.tgz
├── addon.yaml
├── charts/
├── scripts/
├── assets/
└── README.md
```

### Ejemplo mínimo de addon.yaml

```yaml
apiVersion: addons.productive-k3s.io/v1
kind: Addon
metadata:
  name: longhorn
  version: 1.0.0
  category: storage
spec:
  type: helm
  chart:
    path: charts/longhorn
  install:
    script: scripts/install.sh
  dependencies:
    - cert-manager
  compatibility:
    architectures:
      - amd64
      - arm64
    k3s:
      minVersion: "1.31"
```

## Flujo de instalación de add-ons

1. El CLI resuelve el paquete y descarga TGZ
2. Core recibe `addon.tgz`
3. Core extrae el archivo
4. Core lee `addon.yaml`
5. Core ejecuta el instalador
6. Helm/scripts/hooks realizan la instalación

El CLI no debe implementar la lógica de instalación de Helm.

## Formato TGZ de profiles/infra

Un profile debe ser portable, ejecutable, autocontenido y desacoplado del repositorio fuente.

### Ejemplo de estructura

```text
profile.tgz
├── profile.yaml
├── profile.env
├── scenario/
├── assets/
├── templates/
└── README.md
```

### Ejemplo mínimo de profile.yaml

```yaml
apiVersion: infra.productive-k3s.io/v1
kind: Profile
metadata:
  name: aws-single-node-basic
  version: 1.0.0
  category: cloud
spec:
  scenario:
    type: aws-single-node
  engine:
    type: opentofu
  runtime:
    os:
      - ubuntu-24.04
    architectures:
      - amd64
  inputs:
    - name: AWS_REGION
      required: true
      sensitive: false
      source: package-default
      description: Región AWS por defecto usada para aprovisionar
    - name: AWS_KEY_PAIR_NAME
      required: true
      sensitive: false
      source: local-override
      description: Nombre de un key pair existente en AWS EC2
    - name: AWS_SSH_KEY_PATH
      required: true
      sensitive: false
      source: local-override
      description: Ruta absoluta local a la clave privada correspondiente
  execution:
    installScript: scenario/install.sh
```

`profile.env` sigue formando parte del paquete, pero se trata como el contrato base/default del package, no como la configuración final específica de la instalación. `spec.inputs` define qué valores pueden venir de los defaults del paquete y cuáles deben ser provistos desde la máquina que invoca mediante `--env-file`.

## Flujo Infra

1. El CLI resuelve el paquete y descarga TGZ
2. El runtime de Infra recibe `profile.tgz`
3. Infra extrae el archivo
4. Infra lee `profile.yaml`
5. Infra ejecuta el scenario referenciado
6. OpenTofu/Ansible/scripts realizan la implementación

## Modelo orientado a profile

Productive K3S Infra sigue siendo profile-oriented.

El profile es la unidad ejecutable de intención y configuración.
El scenario es el engine genérico reusable que implementa ese profile.

Esto es cierto tanto en desarrollo como en distribución:

- en desarrollo, el profile puede existir como `.env` fuente junto con un scenario en el árbol fuente
- en distribución, ese mismo profile se distribuye como un `profile.tgz` autocontenido

El scenario no es el contrato primario user-facing.
Es el backend reusable de implementación seleccionado por la metadata del profile.

## Semántica de carpetas

### `profiles/`

Contiene presets, variables `.env` y configuraciones listas para ejecutar.

No contiene:

- lógica compleja
- implementación cloud
- templates internos reutilizables

### `scenarios/`

Contiene activos de implementación reutilizables:

- Terraform/OpenTofu
- Ansible
- scripts
- templates
- lógica cloud
- lógica de motor

Un scenario es el motor reutilizable.

### `shared/`

Contiene helpers, librerías bash, templates comunes y utilidades reutilizables.

## Composición del paquete y encapsulamiento

Los profiles se distribuyen como unidades empaquetadas `profile + scenario`.

Ese encapsulamiento es intencional.

Un `profile.tgz` distribuible contiene:

- metadata del profile
- variables y defaults a nivel profile
- los activos de implementación del scenario requeridos para ejecutar ese profile
- cualquier template, script y archivo auxiliar necesario en runtime

En otras palabras, distribución no publica solamente un puntero fino al profile.
Publica un paquete ejecutable autocontenido que embebe el contrato del profile junto con los activos del scenario requeridos para ese camino de instalación.

Esto es especialmente importante para:

- paquetes privados o comerciales, donde el source code no es visible públicamente
- ejecución estable en runtime, donde el artefacto instalado no debe depender de un source checkout vivo
- testing reproducible del payload exacto distribuido

## Modelo de catálogo

El CLI consume índices publicados.

### Ejemplo de entrada de catálogo

```yaml
apiVersion: catalog.productive-k3s.io/v1
entries:
  - name: longhorn
    version: 1.0.0
    type: addon
    url: https://...
  - name: aws-single-node-basic
    version: 1.0.0
    type: profile
    url: https://...
```

Tipos de catálogo:

- Público: GitHub Pages, OSS
- Privado: S3/Auth
- Enterprise: pago o protegido
- Local filesystem

Los paquetes públicos/open pueden seguir respaldados por repositorios donde el source code sea visible.
Los paquetes privados/comerciales pueden exponer solamente la URL del artefacto o una URL protegida/comercial de acceso.

En ambos casos, el contrato del catálogo es el mismo para el consumidor: la unidad instalable es el artefacto TGZ.

## Empaquetado y artefactos de release

Los paquetes TGZ son artefactos de distribución.

Eso implica que los repositorios que authoran profiles o add-ons necesitan un paso de empaquetado que:

- ensamble la estructura final del paquete
- valide la metadata del paquete
- produzca el `.tgz`
- publique el artefacto resultante como parte de la distribución

Ese paso de empaquetado pertenece a la automatización, por ejemplo:

- targets de `make`
- scripts de release
- jobs de release en CI/CD

El ciclo exacto de publicación puede variar por repositorio, pero el requerimiento arquitectónico no cambia:

- los source trees son para authoring
- los artefactos TGZ son para distribución e instalación

Que una versión de paquete se publique:

- como parte del release del repositorio correspondiente, o
- a través de un ciclo separado de artefactos

es una decisión de release management, no una decisión del contrato de runtime.

El modelo de runtime y de catálogo soporta ambos enfoques siempre que cada entrada instalable resuelva a una URL estable de artefacto TGZ.

## Uso recomendado del CLI

### Instalar add-on

```bash
pk3s addon install longhorn
```

Flujo interno:

- resolver catálogo
- descargar TGZ
- delegar a Core

### Instalar profile

```bash
pk3s infra install aws-single-node/basic
```

Flujo interno:

- resolver profile
- descargar TGZ
- delegar a Infra runtime

## Separación de UX en runtime

Los contratos runtime user-facing y development-facing son intencionalmente distintos.

### Ejemplos públicos orientados a paquetes

```bash
./productive-k3s-core.sh addon install --tgz ./longhorn-addon.tgz
./productive-k3s-core.sh addon validate --tgz ./longhorn-addon.tgz

./productive-k3s-infra.sh profile install --tgz ./aws-single-node-basic.tgz
./productive-k3s-infra.sh profile validate --tgz ./aws-single-node-basic.tgz
./productive-k3s-infra.sh profile plan --tgz ./aws-single-node-basic.tgz
./productive-k3s-infra.sh profile status --tgz ./aws-single-node-basic.tgz
./productive-k3s-infra.sh profile destroy --tgz ./aws-single-node-basic.tgz
```

### Ejemplos de desarrollo orientados a source

```bash
./productive-k3s-core.sh dev addon validate --source ./addons/longhorn

./productive-k3s-infra.sh dev profile validate --profile-env ./profiles/cloud/aws-single-node/basic.env
./productive-k3s-infra.sh dev profile plan --profile-env ./profiles/cloud/aws-single-node/basic.env
./productive-k3s-infra.sh dev profile apply --profile-env ./profiles/cloud/aws-single-node/basic.env
```

El prefijo `dev` es la frontera explícita que mantiene disponibles los workflows source-oriented sin convertirlos en parte del contrato público de instalación.

## Modelo de testing

La arquitectura requiere tanto testing a nivel source como testing a nivel package.

### Testing a nivel source

El testing a nivel source valida flujos de authoring antes del empaquetado:

- validación del contrato del profile desde `.env` fuente
- ejecución del scenario desde el árbol del repositorio
- ciclos de CI orientados a desarrollo sin requerir un TGZ en cada iteración local

### Testing a nivel package

El testing a nivel package valida el comportamiento real distribuido:

- descomprimir TGZ
- validar metadata del paquete
- ejecutar el runtime contra el paquete extraído
- verificar que la instalación funciona sin depender del repositorio fuente

Por eso, la suite de tests debe incluir paquetes TGZ mock o fixture tanto para:

- add-ons
- profiles

Esos artefactos de test deben imitar suficientemente la estructura real del paquete para ejercitar:

- validación de empaquetado
- extracción
- delegación de comandos
- caminos de ejecución del runtime

## Reglas arquitectónicas

### El CLI NO debe:

- tener templates
- tener charts de Helm
- conocer proveedores cloud
- conocer lógica OpenTofu
- conocer escenarios
- saber cómo instalar add-ons

### Core debe:

- conocer el formato de add-ons
- gestionar el lifecycle y hooks
- ejecutar Helm
- validar dependencias y compatibilidad

### Infra debe:

- conocer escenarios y runtimes
- ejecutar OpenTofu/Ansible
- validar variables de runtime
- validar la compatibilidad del target

## Modelo mental final

Productive K3S = Runtime + Packages

- `scenario` = motor reusable
- `profile` = preset ejecutable
- `addon` = extensión instalable
- `tgz` = unidad distribuible
- `catalog` = índice de descubrimiento
- `cli` = orquestador mínimo
- `core/infra` = runtimes
