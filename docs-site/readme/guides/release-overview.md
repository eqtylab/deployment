# Governance Platform v0.1.0

Governance Platform v0.1.0 is a customer prerelease. It is delivered as private
runtime images, public Helm charts, a release manifest, and a connected customer
package.

Use only the chart version and image tags recorded in the release manifest. Do
not install from floating image tags.

## Release Status

- Status: Beta prerelease
- Kubernetes: 1.29 or newer
- Architecture: linux/amd64
- Primary install path: `governance-platform` umbrella chart
- Runtime image access: private GHCR credentials or customer registry mirror
- Manual validation path: Keycloak with external Postgres

## Included Runtime Services

- Governance Studio
- Governance Service
- Auth Service
- Integrity Service

## Customer Artifacts

- `governance-platform-v0.1.0.tar.gz`
- `release-manifest.yaml`
- `chart-digests.yaml`
- chart packages and checksums
- install examples
