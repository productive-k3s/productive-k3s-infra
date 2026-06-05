# Resumen Del Producto

`Productive K3S Infra` es el engine de runtime para los profiles empaquetados de Productive K3S.

No reemplaza:

- `productive-k3s-core`, que sigue siendo dueño del bootstrap del clúster
- `productive-k3s-profiles`, que sigue siendo dueño del árbol fuente público de profiles y scenarios

En cambio, ejecuta artefactos autocontenidos `profile.tgz` encargándose de:

- extracción y dispatch del paquete
- merge entre defaults del paquete y overrides locales
- persistencia y restauración del state de runtime
- telemetría, correlación de comandos y comportamiento operator-facing del runtime

## Páginas

- [Cómo usar Productive K3S Infra](how-to-use.md)
- [Razones del diseño](reasons-behind.md)
- [Open vs Pro](open-vs-pro.md)
- [Relación con Productive K3S Profiles y Core](productive-k3s-relationship.md)
