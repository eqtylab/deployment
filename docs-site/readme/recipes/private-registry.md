# Private Registry Recipe

Runtime images are private by default.

Connected customers can use GHCR pull credentials. Disconnected customers should
mirror the image digests recorded in the release manifest and set:

```yaml
global:
  imageRepositoryPrefixOverride: registry.customer.example/eqtylab
```
