# Release Manifest

The release manifest records the exact customer release contents.

Required sections:

- `platform`
- `sources`
- `images`
- `charts`
- `validation`
- `docs`

Each runtime image entry must include:

- repository
- tag
- digest
- source SHA

Current release candidates include these runtime image entries:

- `authService`
- `governanceService`
- `governanceStudio`
- `integrityService`
- `eqtyPdfgen`

Each chart entry must include:

- chart name
- chart version
- OCI reference

The validation section records the manual customer-like validation gate. A
candidate starts with `validation.evidence.status: pending`. Customer
publication requires `validation.evidence.status: approved`.

The release package and GitHub Release must include the manifest used to publish
the customer artifacts.
