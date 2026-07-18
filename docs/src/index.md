---
title: "Productive K3S Infra"
template: "home.html"
hide:
  - navigation
  - toc
eyebrow: "Deploy complete solutions on different platforms"
eyebrow_es: "Desplegá soluciones completas sobre distintas plataformas"
hero_title: "Productive K3S Infra"
hero_title_es: "Productive K3S Infra"
lead: "Productive K3S Infra is the orchestration and deployment layer that turns Productive K3S Core into complete solution paths across platforms."
lead_es: "Productive K3S Infra es la capa de orquestación y despliegue que convierte a Productive K3S Core en caminos completos de solución sobre distintas plataformas."
sublead: "Use it to execute curated deployment solutions, keep runtime state coherent, and bridge platform orchestration with the base Kubernetes installation contract owned by Core."
sublead_es: "Usalo para ejecutar soluciones curadas de despliegue, mantener coherente el state de runtime y conectar la orquestación de plataforma con el contrato base de instalación Kubernetes que posee Core."
primary_label: "View on GitHub"
primary_label_es: "Ver en GitHub"
primary_url: "https://github.com/productive-k3s/productive-k3s-infra"
secondary_label: "Open README"
secondary_label_es: "Abrir README"
secondary_url: "https://github.com/productive-k3s/productive-k3s-infra/blob/main/README.md"
card_title: "What it does"
card_title_es: "Qué hace"
card_items:
  - Interprets curated deployment solutions over different target platforms
  - Coordinates runtime state, overrides, and execution flow
  - Delegates the base Kubernetes installation contract to Productive K3S Core
card_items_es:
  - Interpreta soluciones curadas de despliegue sobre distintas plataformas objetivo
  - Coordina state de runtime, overrides y flujo de ejecución
  - Delega el contrato base de instalación Kubernetes a Productive K3S Core
why_title: "Why it exists"
why_title_es: "Por qué existe"
why_options:
  - label: "COMPLETE DEPLOYMENTS"
    text: "Users need a coherent way to deploy complete solutions without assembling each platform path by hand."
  - label: "REUSABLE ORCHESTRATION"
    text: "The deployment layer should stay reusable while the curated solutions keep evolving in their own repository."
why_options_es:
  - label: "DESPLIEGUES COMPLETOS"
    text: "Los usuarios necesitan una forma coherente de desplegar soluciones completas sin ensamblar a mano cada camino de plataforma."
  - label: "ORQUESTACIÓN REUTILIZABLE"
    text: "La capa de despliegue debe seguir siendo reutilizable mientras las soluciones curadas evolucionan en su propio repositorio."
bridge_note: "Productive K3S Infra is the reusable orchestration layer above Core."
bridge_note_es: "Productive K3S Infra es la capa reutilizable de orquestación por encima de Core."
bridge_points:
  - Keep Core responsible for the base installation contract
  - Execute curated deployment solutions consistently
  - Keep solution definitions in Profiles instead of mixing them into the engine
bridge_points_es:
  - Mantener a Core como responsable del contrato base de instalación
  - Ejecutar soluciones curadas de despliegue de manera consistente
  - Mantener las definiciones de solución en Profiles en lugar de mezclarlas dentro del engine
scenarios_title: "How it fits"
scenarios_title_es: "Dónde encaja"
scenarios:
  - Use Infra directly when you want explicit control of the deployment layer
  - Use Profiles to choose the curated solution path you want to deploy
  - Use Productive K3S CLI when you want the simplest and recommended unified experience
  - Let Core keep ownership of the base Kubernetes installation underneath
scenarios_es:
  - Usá Infra directo cuando quieras control explícito de la capa de despliegue
  - Usá Profiles para elegir el camino curado de solución que querés desplegar
  - Usá Productive K3S CLI cuando quieras la experiencia unificada más simple y recomendada
  - Dejá que Core mantenga el ownership de la instalación base de Kubernetes por debajo
principles_title: "Design principles"
principles_title_es: "Principios de diseño"
principles:
  - title: "Solution-first"
    text: "lead with complete deployment paths, not with internal mechanics"
  - title: "Keep the layers separate"
    text: "Profiles owns curated solutions, Core owns base installation, Infra owns orchestration"
  - title: "Preserve one runtime view"
    text: "status, plan, destroy, and related flows should share coherent runtime state"
principles_es:
  - title: "Solución primero"
    text: "poné adelante los caminos completos de despliegue, no la mecánica interna"
  - title: "Separá las capas"
    text: "Profiles posee las soluciones curadas, Core la instalación base e Infra la orquestación"
  - title: "Preservá una sola vista de runtime"
    text: "status, plan, destroy y flujos relacionados deben compartir un state coherente"
environments_title: "What it works with"
environments_title_es: "Con qué trabaja"
environments:
  - Curated deployment solutions defined in Productive K3S Profiles
  - Local or remote Productive K3S Core bundle sources
  - Runtime state reused across repeated deployment commands
  - CLI-driven or direct operator usage depending on the workflow you want
environments_es:
  - Soluciones curadas de despliegue definidas en Productive K3S Profiles
  - Bundles de Productive K3S Core desde fuentes locales o remotas
  - State de runtime reutilizado entre comandos repetidos de despliegue
  - Uso directo por operadores o mediado por CLI según el flujo que quieras
not_title: "What it is not"
not_title_es: "Qué no es"
not_items:
  - Not the base Kubernetes installation layer
  - Not the source-of-truth catalog of curated deployment solutions
  - Not the only way to operate the ecosystem
not_items_es:
  - No es la capa base de instalación Kubernetes
  - No es el catálogo fuente de soluciones curadas de despliegue
  - No es la única manera de operar el ecosistema
not_note: "It is the deployment and orchestration layer in the Productive K3S path."
not_note_es: "Es la capa de despliegue y orquestación dentro del camino Productive K3S."
---
