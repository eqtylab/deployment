# Splunk HEC Log Forwarding

**Architecture:** `llm-gateway` emits structured OTLP logs → OpenTelemetry Collector → Splunk HEC.

The gateway is Splunk-unaware. All HEC transport is handled by the Collector, which means the gateway export path stays stable regardless of where logs are sent.

## 1. Enable OTLP Log Export

```yaml
llmGateway:
  extraEnv:
    - name: OTEL_LOGS_EXPORTER
      value: otlp
    - name: OTEL_EXPORTER_OTLP_ENDPOINT
      value: http://otel-collector.observability.svc.cluster.local:4318
    - name: OTEL_EXPORTER_OTLP_PROTOCOL
      value: http/protobuf
    - name: OTEL_RESOURCE_ATTRIBUTES
      value: service.name=guardian-llm-gateway,deployment.environment=production
```

Add `OTEL_TRACES_EXPORTER: otlp` alongside if trace export is also needed.

## 2. Collector Configuration

```yaml
receivers:
  otlp:
    protocols:
      grpc:
        endpoint: 0.0.0.0:4317
      http:
        endpoint: 0.0.0.0:4318

processors:
  memory_limiter:
    check_interval: 2s
    limit_mib: 512
  resource/gateway:
    attributes:
      - { action: upsert, key: splunk.index, value: guardian_gateway }
      - {
          action: upsert,
          key: splunk.sourcetype,
          value: "guardian:gateway:otel",
        }
      - { action: upsert, key: splunk.source, value: guardian-llm-gateway }
  batch: {}

exporters:
  splunk_hec/gateway_logs:
    token: "${SPLUNK_HEC_TOKEN}"
    endpoint: "https://splunk.example.com:8088/services/collector"
    sourcetype: "guardian:gateway:otel"
    index: "guardian_gateway"
    timeout: 10s

service:
  pipelines:
    logs/gateway:
      receivers: [otlp]
      processors: [memory_limiter, resource/gateway, batch]
      exporters: [splunk_hec/gateway_logs]
```

Use TLS validation in production. Only set `tls.insecure_skip_verify: true` in controlled test environments.

## 3. Log Schema

Gateway lifecycle fields are emitted as OTLP log record attributes by `guardian.gateway.lifecycle`. Existing proxy error records are emitted by `guardian.gateway.proxy`. No custom Splunk parser is required.

| Field                  | Description                                            |
| ---------------------- | ------------------------------------------------------ |
| `event.name`           | Stable lifecycle event name                            |
| `event.sequence`       | Monotonic request-local lifecycle log sequence         |
| `correlation_id`       | Unique ID linking request and response records         |
| `agent.id`             | DID of the calling agent                               |
| `policy.decision_code` | Policy outcome (e.g. `policy_denied`)                  |
| `gateway.route_type`   | Routing decision (e.g. `local_deny`, `upstream_proxy`) |
| `llm.provider`         | Target provider (`anthropic`, `openai`)                |
| `llm.operation`        | LLM operation type                                     |
| `http.method`          | HTTP method of the inbound request                     |
| `http.status_code`     | Response status code                                   |
| `gateway.duration_ms`  | End-to-end request duration                            |
| `gateway.uri`          | Inbound request URI                                    |
| `upstream.uri`         | URI forwarded to the LLM provider                      |
| `error`                | Error detail, present on failure records               |

Stable lifecycle event names emitted by the gateway:

- `gateway.request.start`
- `gateway.request.prepare.start`
- `gateway.request.prepare.end`
- `gateway.verification.start`
- `gateway.verification.end`
- `gateway.proxy.start`
- `gateway.plugin.invocation.start`
- `gateway.plugin.invocation.end`
- `gateway.plugin.invocation.queued`
- `gateway.upstream.start`
- `gateway.upstream.end`
- `gateway.proxy.end`
- `gateway.request.end`

Stable proxy error event names emitted by the gateway:

- `gateway.proxy.request.read_error`
- `gateway.proxy.provider_route.error`
- `gateway.proxy.policy.error`
- `gateway.proxy.policy.shadow_mismatch`
- `gateway.proxy.upstream.error`
- `gateway.proxy.agent_state.error`
- `gateway.proxy.audit.encode.error`
- `gateway.proxy.audit.enqueue.error`

## 4. Verify in Splunk

After deploying, generate a mix of allowed and denied gateway requests, then confirm records are arriving:

```spl
index=guardian_gateway sourcetype="guardian:gateway:otel" service.name="guardian-llm-gateway"
```

Detection-focused searches:

```spl
index=guardian_gateway policy.decision_code=policy_denied
index=guardian_gateway gateway.route_type=local_deny
index=guardian_gateway llm.provider=openai http.status_code>=500
```

## 5. Local Validation

To verify the HEC path locally without a Splunk license, run the mock HEC
server and the dedicated HEC Collector config:

```bash
# Start the mock HEC server and local HEC Collector (ports 5317/5318)
docker compose -f llm-gateway/docker-compose.yml up mock-hec otel-collector-hec

# Generate gateway OTEL traffic against the HEC collector
cd llm-gateway/service
OBS_OTEL_COLLECTOR_VALIDATE=1 \
OBS_OTEL_COLLECTOR_ENDPOINT=127.0.0.1:5318 \
GOWORK=off \
GOCACHE=/tmp/go-build-cache \
go test ./internal/gatewayhttp -count=1 -run '^TestProxyCollectorExportValidation$'
```

Artifacts are written to:

- `llm-gateway/observability/.artifacts/logs-hec.jsonl`
- `llm-gateway/observability/.artifacts/traces-hec.jsonl`

The `mock-hec` container should also print `POST /services/collector` requests
with the `Authorization: Splunk test-hec-token` header, which validates the
Collector's HEC export path in addition to the local file artifacts.

To validate the HEC request shape itself, point the Collector's `splunk_hec` exporter at a local HTTP server before wiring up a live Splunk instance. See Section 2 for the exporter config — replace the endpoint with `http://localhost:18088/services/collector` and use `token: "test-hec-token"`.
