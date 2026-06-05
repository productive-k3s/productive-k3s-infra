# Cómo Usar Productive K3S Infra

`productive-k3s-infra` es el engine de runtime para la ejecución package-first de profiles. El árbol fuente público de profiles/scenarios vive en el repositorio hermano `productive-k3s-profiles`.

## Elegí el profile correcto

- `multipass-1-server-2-agents`: clúster local de tres nodos sobre VMs de Multipass
- `on-prem-basic` / `on-prem-arm`: bootstrap de hosts existentes por `SSH`
- `aws-single-node-basic`: provisioning de una instancia `EC2` con `OpenTofu` y bootstrap remoto

## Entendé el contrato de ejecución

Cada profile publicado encapsula el comportamiento de infraestructura alrededor del clúster, mientras que `productive-k3s-core` sigue siendo responsable del bootstrap del clúster en sí.

En la práctica eso significa que `productive-k3s-infra` maneja:

- extracción y dispatch del paquete
- merge de defaults de `profile.env` con overrides locales
- persistencia y restauración del state de runtime entre `install`, `status`, `plan` y `destroy`
- resolución de bundles de `productive-k3s-core`
- propagación de telemetría y correlación de comandos

## Engine opcional de instalación de K3S

El engine por default sigue siendo el camino nativo de bootstrap de Productive K3S.

Los usuarios avanzados también pueden optar por:

```bash
PRODUCTIVE_K3S_ENGINE=k3sup
```

Eso está documentado intencionalmente como experimental.

## Usá los entrypoints públicos

La interfaz pública para operadores es package-first:

```bash
./productive-k3s-infra.sh profile validate --tgz https://downloads.productive-k3s.io/infra/multipass-1-server-2-agents-0.9.62-0.9.4.tgz
./productive-k3s-infra.sh profile install --tgz https://downloads.productive-k3s.io/infra/aws-single-node-basic-0.9.62-0.9.4.tgz --env-file ./aws.env
pk3s profile validate multipass-1-server-2-agents
pk3s infra install aws-single-node-basic --env-file ./aws.env
```

El `profile.env` embebido en un `profile.tgz` público se trata como archivo base/default del paquete, no como la configuración final específica de la instalación. Para instalaciones reales, especialmente en cloud y on-prem, pasá overrides locales desde la máquina que invoca mediante `--env-file`.

## Usá los entrypoints de desarrollo

Los profiles `.env` fuente siguen siendo válidos para desarrollo del repositorio y CI. En el modelo separado, esos archivos provienen de un clon temporal o checkout explícito de `productive-k3s-profiles`, expuesto al engine mediante `PRODUCTIVE_K3S_PROFILES_REPO_DIR`.

Ejemplo de desarrollo:

```bash
export PRODUCTIVE_K3S_PROFILES_REPO_DIR=/tmp/productive-k3s-profiles
git clone https://github.com/jemacchi/productive-k3s-profiles.git "$PRODUCTIVE_K3S_PROFILES_REPO_DIR"
./productive-k3s-infra.sh dev profile validate --profile-env "$PRODUCTIVE_K3S_PROFILES_REPO_DIR/profiles/edge/on-prem/basic.env"
make infra-validate PROFILE="$PRODUCTIVE_K3S_PROFILES_REPO_DIR/profiles/edge/on-prem/basic.env"
```

Usá `dev profile validate` cuando sólo quieras chequear que el contrato del `.env` sea válido. El CI del engine debería clonar `productive-k3s-profiles` en un workspace temporal y correr los checks de integración existentes, para que cambios de runtime no rompan silenciosamente los profiles públicos.

## Notas

!!! note
    El comportamiento específico de cada scenario, las topologías y los flujos locales de `make` ahora viven en `profiles.productive-k3s.io`.

!!! note
    `productive-k3s-infra` está diseñado intencionalmente para no tener que versionar todos los profiles públicos. La compatibilidad se valida integrándolo contra un checkout separado de `productive-k3s-profiles`.
