# Hook/Plugin Runtime Bootstrap

This guide covers the operational steps needed to enable the hook/plugin
foundation in a cluster deployed with `gateway-stack`.

## Prerequisites

1. `llm-gateway` and `control-plane` must share the plugin trust roots for the
   signer keys that will sign plugin artifacts and configuration manifests.
2. A baseline signed configuration must be created and activated before
   enabling `llmGateway.plugins.enabled=true`.
3. The active baseline configuration should include `builtin.authorization` in
   `proxy.pre` so the first-party authorization policy is enforced before
   upstream proxying.
4. `llm-gateway` and `control-plane` must be able to read/write the shared plugin
   artifact bucket, typically via workload identity-bound Kubernetes service
   accounts.

## Helm Values

Gateway values:

```yaml
llmGateway:
  deploymentEnvironment: production
  serviceAccount:
    annotations:
      iam.gke.io/gcp-service-account: guardian-llm-gateway@project-id.iam.gserviceaccount.com
  plugins:
    enabled: true
    pollInterval: 15s
    authorizerShadowEnabled: true
    endQueueDir: /var/lib/guardian/plugin-end-queue
    endQueueMaxBytes: 134217728
    artifactCacheDir: /var/lib/guardian/plugin-artifacts
    artifactStorage:
      provider: gcs
      bucket: guardian-plugin-artifacts
      prefix: production
      gcs:
        endpoint: ""
    trustedSignerKeys:
      signer-prod: did:key:z6Mk...
    secrets:
      resolutionOrder: ["store"]
      encryptionKey:
        existingSecret: guardian-plugin-secret-key
        secretKey: encryption-key
```

Control-plane values:

```yaml
controlPlane:
  serviceAccount:
    annotations:
      iam.gke.io/gcp-service-account: guardian-control-plane@project-id.iam.gserviceaccount.com
  plugins:
    artifactStorage:
      provider: gcs
      bucket: guardian-plugin-artifacts
      prefix: production
      maxUploadBytes: 536870912
      gcs:
        endpoint: ""
        kmsKeyName: ""
    trustedSignerKeys:
      signer-prod: did:key:z6Mk...
    secrets:
      encryptionKey:
        existingSecret: guardian-plugin-secret-key
        secretKey: encryption-key
```

Notes:

- `trustedSignerKeys` are public trust roots, so inline values are acceptable.
- `llmGateway.deploymentEnvironment` labels telemetry and dev-mode checks only;
  plugin configurations are no longer scoped by environment.
- `control-plane` proxies artifact uploads, computes the SHA-256 digest, verifies
  the signer signature, and stores only metadata in Postgres. Artifact bytes live
  in object storage under immutable digest-based keys.
- `llm-gateway` reads artifact objects directly from the configured bucket using
  its own workload identity or ADC credentials, then verifies digest and signature
  again before caching locally.
- Store-backed plugin secrets are encrypted with the generic
  `guardian-plugin-secret-key` value and scoped by plugin ID and secret name.
  The control-plane API accepts raw values only on write and returns
  metadata/fingerprints on reads.
- The chart mounts `emptyDir` volumes for the async `request.end` queue and the
  verified artifact cache. Move those paths to persistent storage if you need
  cache reuse across restarts.

Built-in plugin secret names:

- `builtin.vtscan` should use `{"kind":"secret_ref","name":"virustotal_api_key"}`
  for `vt_api_key`.
- `builtin.intent_monitor` should use `{"kind":"secret_ref","name":"openai_api_key"}`
  for `llm_api_key`.

Set or rotate store-backed values through the control-plane:

```bash
curl -X POST "$CONTROL_PLANE_URL/v1/plugins/secrets" \
  -H 'Content-Type: application/json' \
  -d '{"plugin_id":"builtin.intent_monitor","name":"openai_api_key","value":"replace-with-openai-key"}'
```

Local/dev fallback can still use Kubernetes env injection. Example Secret data
when using the default `plugins.secrets.env.prefix = "GUARDIAN_SECRET_"`:

```text
GUARDIAN_SECRET__BUILTIN__VTSCAN__VIRUSTOTAL_API_KEY=replace-with-virustotal-key
GUARDIAN_SECRET__BUILTIN__INTENT_MONITOR__OPENAI_API_KEY=replace-with-openai-key
```

## Baseline Configuration Checklist

1. Register the premade plugin definition for `builtin.authorization`.
2. Create a draft default-scope configuration.
3. Add a `proxy.pre` enforcement entry for `builtin.authorization`.
4. Add any observability plugins needed for rollout validation.
5. Sign the configuration manifest with a trusted signer key.
6. Activate the configuration through `POST /v1/plugin-configurations/{id}/activate`
   (empty request body).
7. Confirm `GET /v1/plugin-configurations/current` returns the expected version.
8. Enable `llmGateway.plugins.enabled=true` and roll the gateway deployment.

The gateway now starts cleanly when plugin runtime is enabled but no active
configuration exists yet. Even so, you should still bootstrap a signed baseline
configuration before rollout so the deployment comes up enforcing an intentional
policy instead of an empty plugin set.

Example `builtin.authorization` configuration entry config:

```json
{
  "default_effect": "deny",
  "default_message": "agent is not authorized for this provider route",
  "rules": [
    {
      "id": "allow-agent-openai-chat",
      "effect": "allow",
      "match": {
        "agent_id": { "operator": "exact", "value": "agent:test" },
        "provider": { "operator": "exact", "value": "openai" },
        "operation": { "operator": "exact", "value": "chat_completions" },
        "upstream_path": {
          "operator": "prefix",
          "value": "/v1/chat/completions"
        }
      }
    }
  ]
}
```

Recommended first rollout:

- set `llmGateway.plugins.authorizerShadowEnabled=true`
- compare hook decisions against the legacy authorizer in telemetry
- keep the legacy authorizer enabled only for shadow comparison until
  `builtin.authorization` has acceptable mismatch rates

## Signer Rotation

Use additive rotation:

1. Add the new signer public key to both `controlPlane.plugins.trustedSignerKeys`
   and `llmGateway.plugins.trustedSignerKeys`.
2. Roll both deployments so the new trust root is active everywhere.
3. Start signing new artifacts and configurations with the new signer key.
4. Activate at least one configuration signed by the new key in every deployment.
5. After the old signer is no longer needed for rollback, remove its trust root
   from both services and roll again.

Do not remove the old signer key before every deployment has a last-known-good
configuration signed by the replacement key.

## Operational Checks

- `llm-gateway` startup should log `plugin runtime enabled`.
- Audit rows should populate `plugin_configuration_version`, `plugin_denied_by`, and
  `plugin_decision_code` when a hook participates in the request.
- When `authorizerShadowEnabled=true`, shadow mismatches appear as
  `gateway.proxy.policy.shadow_mismatch` log events and `gateway.policy.shadow_compare`
  span events.
- The async end-hook queue path should stay below `endQueueMaxBytes`; investigate
  DLQ growth before increasing the limit.
