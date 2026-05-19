# Air-Gapped Install

Air-gapped installs mirror the runtime images listed in the release manifest to
a customer registry and install the platform with registry override values.

## Registry Override

Use `global.imageRepositoryPrefixOverride` when all EQTY images are mirrored
under the same customer registry prefix:

```yaml
global:
  imageRepositoryPrefixOverride: registry.customer.example/eqtylab
```

For v0.1.0, air-gap package generation is package-ready optional. The connected
package includes the chart and manifest information needed to prepare a mirrored
install path.
