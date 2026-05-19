# Upgrade

Upgrade support for v0.1.0 is limited because this is the first customer
prerelease line.

Before upgrading a customer environment:

1. Back up Postgres.
2. Save the current Helm values.
3. Confirm the target release manifest.
4. Confirm all runtime images are available in the selected registry.
5. Run `helm diff` or an equivalent review.

Use the exact chart version from the release manifest when upgrading.
