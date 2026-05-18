# Rollback

Rollback depends on database migration behavior for the release being rolled
back. Always capture a Postgres backup before upgrade.

General rollback shape:

```bash
helm rollback governance-platform <REVISION> --namespace governance
```

If database migrations are not reversible, restore the database backup and then
roll back the Helm release.
