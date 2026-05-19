# Keycloak Manual Validation Recipe

Keycloak is the first required identity provider path for release-candidate
validation. This check is performed by the release owner and recorded in the
release manifest before customer publication.

Use the Keycloak values examples in the Governance Platform chart, provide
external Postgres settings, and verify:

- Auth Service health
- Governance Service health
- Integrity Service health
- Studio load
- Login redirect and return flow
