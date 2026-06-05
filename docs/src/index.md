---
title: "Productive K3S Infra"
template: "home.html"
hide:
  - navigation
  - toc
eyebrow: "Runtime engine for packaged Productive K3S profiles"
eyebrow_es: "Engine de runtime para profiles empaquetados de Productive K3S"
hero_title: "Productive K3S Infra"
hero_title_es: "Productive K3S Infra"
lead: "Productive K3S Infra is the runtime engine that executes packaged profile artifacts and bridges them with Productive K3S Core."
lead_es: "Productive K3S Infra es el engine de runtime que ejecuta artefactos de profiles empaquetados y los conecta con Productive K3S Core."
sublead: "It owns package execution, env merge, runtime state, telemetry, and command dispatch, while public scenario source content lives in Productive K3S Profiles."
sublead_es: "Es dueño de la ejecución de paquetes, merge de env, state de runtime, telemetría y dispatch de comandos, mientras que el contenido fuente de scenarios públicos vive en Productive K3S Profiles."
primary_label: "View on GitHub"
primary_label_es: "Ver en GitHub"
primary_url: "https://github.com/jemacchi/productive-k3s-infra"
secondary_label: "Open README"
secondary_label_es: "Abrir README"
secondary_url: "https://github.com/jemacchi/productive-k3s-infra/blob/main/README.md"
card_title: "What it does"
card_title_es: "Qué hace"
card_items:
  - Executes packaged `profile.tgz` artifacts
  - Merges package defaults with local overrides
  - Persists runtime state and delegates bootstrap to Productive K3S Core
card_items_es:
  - Ejecuta artefactos empaquetados `profile.tgz`
  - Mergea defaults del paquete con overrides locales
  - Persiste state de runtime y delega el bootstrap a Productive K3S Core
why_title: "Why it exists"
why_title_es: "Por qué existe"
why_options:
  - label: "PACKAGE-FIRST RUNTIME"
    text: "Published profiles need one reusable execution layer instead of reimplementing runtime behavior inside every package."
  - label: "SOURCE SPLIT"
    text: "Public scenario source content should evolve independently from the Infra engine bundle."
why_options_es:
  - label: "RUNTIME PACKAGE-FIRST"
    text: "Los profiles publicados necesitan una capa reutilizable de ejecución en lugar de reimplementar el runtime dentro de cada paquete."
  - label: "SPLIT DE CÓDIGO FUENTE"
    text: "El contenido fuente de scenarios públicos debe poder evolucionar por separado del bundle del engine de Infra."
bridge_note: "Productive K3S Infra provides the execution layer: package-first runtime around Productive K3S Core."
bridge_note_es: "Productive K3S Infra aporta la capa de ejecución: runtime package-first alrededor de Productive K3S Core."
bridge_points:
  - Keep Productive K3S Core as the bootstrap contract
  - Execute self-contained profile artifacts instead of source trees
  - Keep source-content ownership outside the engine
bridge_points_es:
  - Mantener Productive K3S Core como contrato de bootstrap
  - Ejecutar artefactos autocontenidos en lugar de árboles fuente
  - Mantener fuera del engine el ownership del contenido fuente
scenarios_title: "Runtime coverage"
scenarios_title_es: "Cobertura del runtime"
scenarios:
  - Published profile artifacts from catalog or direct TGZ
  - Local overrides passed by the invoking machine
  - Runtime state restored across install, status, plan, and destroy
  - Productive K3S Core bundles from a local checkout or a published release
scenarios_es:
  - Artefactos de profiles publicados desde catálogo o TGZ directo
  - Overrides locales pasados por la máquina que invoca
  - State de runtime restaurado entre install, status, plan y destroy
  - Bundles de Productive K3S Core desde un checkout local o un release publicado
principles_title: "Design principles"
principles_title_es: "Principios de diseño"
principles:
  - title: "Package-first"
    text: "the public runtime interface operates on profile artifacts, not source trees"
  - title: "Keep source ownership separate"
    text: "public scenarios live in Productive K3S Profiles, not inside the engine"
  - title: "Preserve state"
    text: "status, plan, destroy, and addon flows should share one runtime view"
principles_es:
  - title: "Package-first"
    text: "la interfaz pública de runtime opera sobre artefactos de profile, no sobre árboles fuente"
  - title: "Separar ownership del código fuente"
    text: "los scenarios públicos viven en Productive K3S Profiles, no dentro del engine"
  - title: "Preservar state"
    text: "status, plan, destroy y los flujos de addons deben compartir una única vista de runtime"
environments_title: "Supported runtime inputs"
environments_title_es: "Inputs de runtime soportados"
environments:
  - Published profile artifacts from catalog or direct TGZ
  - Local override env files supplied by the invoking machine
  - Runtime state restored across repeated profile commands
  - Productive K3S Core bundles from local or remote releases
environments_es:
  - Artefactos de profiles publicados desde catálogo o TGZ directo
  - Archivos de override local provistos por la máquina que invoca
  - State de runtime restaurado entre comandos repetidos sobre profiles
  - Bundles de Productive K3S Core desde releases locales o remotos
not_title: "What it is not"
not_title_es: "Qué no es"
not_items:
  - Not a replacement for Productive K3S Core
  - Not the source-of-truth repo for public scenarios
  - Not a promise that a packaged profile removes the need for local install-specific inputs
not_items_es:
  - No reemplaza a Productive K3S Core
  - No es el repo fuente de scenarios públicos
  - No promete que un profile empaquetado elimine la necesidad de inputs locales específicos de instalación
not_note: "It is the package execution layer around Productive K3S profiles and Productive K3S Core."
not_note_es: "Es la capa de ejecución de paquetes alrededor de los profiles de Productive K3S y Productive K3S Core."
---
