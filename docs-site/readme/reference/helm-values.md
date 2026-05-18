# Helm Values

Helm values are generated from the chart source during release preparation.

Important customer-facing values:

- `global.imagePullSecrets`
- `global.secrets.imageRegistry`
- `global.imageRegistryOverride`
- `global.imageRepositoryPrefixOverride`
- service-level `image.repository`
- service-level `image.tag`

Prefer the global repository prefix override for air-gapped installs.
