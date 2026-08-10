# Prometheus Metrics

Gateway Guardian exposes a native Prometheus metrics endpoint on a dedicated port (default `:10001`), separate from the main API port. No sidecar exporter is required.

## Metrics Reference

| Metric                              | Type    | Labels                    | Description            |
| ----------------------------------- | ------- | ------------------------- | ---------------------- |
| `gateway_http_requests_total`       | Counter | `agent_id`, `route`       | Total inbound requests |
| `gateway_http_request_errors_total` | Counter | `status_code`, `agent_id` | 4xx and 5xx responses  |

Standard Go runtime and process metrics (`go_*`, `process_*`) are also included.

For request-level observability beyond these counters — policy decisions, plugin invocation timings, and per-request lifecycle — use the OpenTelemetry exporter; see [`splunk-hec-log-forwarding.md`](./splunk-hec-log-forwarding.md) and the gateway's `observability.mdx` for lifecycle event names and OTLP wiring.

## 1. Enable the Metrics Port

The metrics listen address is configured via the `-metrics-listen` flag. Add it to `extraArgs` in your `values.yaml`:

```yaml
llmGateway:
  extraArgs:
    - -metrics-listen=:10001
```

To use a non-default port:

```yaml
llmGateway:
  extraArgs:
    - -metrics-listen=:9090
```

Alternatively, set the environment variable instead of a flag:

```yaml
llmGateway:
  extraEnv:
    - name: LLM_GATEWAY_METRICS_LISTEN
      value: ":10001"
```

## 2. Expose the Metrics Port

The default `llm-gateway` Service only exposes the API port. You need to make the metrics port reachable by Prometheus. There are two approaches.

### Option A - Pod Annotations (Prometheus Auto-Discovery)

This works with a Prometheus deployment that uses the standard annotation-based pod scrape config. No additional Service is required.

```yaml
llmGateway:
  extraArgs:
    - -metrics-listen=:10001
  podAnnotations:
    prometheus.io/scrape: "true"
    prometheus.io/port: "10001"
    prometheus.io/path: "/metrics"
```

### Option B - Dedicated Metrics Service and ServiceMonitor

Create a separate Service that targets the metrics port, then point a `ServiceMonitor` at it.

**Service** (apply alongside the chart, or add to a `templates/` override):

```yaml
apiVersion: v1
kind: Service
metadata:
  name: guardian-llm-gateway-metrics
  labels:
    app.kubernetes.io/component: llm-gateway
    app.kubernetes.io/part-of: gateway-stack
spec:
  selector:
    app.kubernetes.io/component: llm-gateway
  ports:
    - name: metrics
      port: 10001
      targetPort: 10001
      protocol: TCP
```

**ServiceMonitor:**

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: guardian-llm-gateway
  labels:
    release: prometheus # must match your Prometheus operator's serviceMonitorSelector
spec:
  selector:
    matchLabels:
      app.kubernetes.io/component: llm-gateway
  endpoints:
    - port: metrics
      path: /metrics
      interval: 15s
```

Adjust `release:` to match the label your Prometheus operator uses to discover `ServiceMonitor` resources (`kubectl get prometheus -o yaml | grep serviceMonitorSelector`).

## 3. Verify Scraping

After deploying, confirm the endpoint responds:

```bash
kubectl port-forward deploy/<release>-llm-gateway 10001:10001
curl -s http://localhost:10001/metrics | grep gateway_
```

Expected output includes lines like:

```
# HELP gateway_http_requests_total Total inbound gateway requests labeled by agent and route.
# TYPE gateway_http_requests_total counter
gateway_http_requests_total{agent_id="agent:did:key:z...",route="/v1/anthropic_api/*"} 42
```

In the Prometheus UI, check **Status → Targets** and confirm the `guardian-llm-gateway` job shows `UP`.

## 4. Example PromQL Queries

**Request rate by route (5m window):**

```promql
sum by (route) (rate(gateway_http_requests_total[5m]))
```

**Error rate by status code:**

```promql
sum by (status_code) (rate(gateway_http_request_errors_total[5m]))
```

**Per-agent error ratio:**

```promql
sum by (agent_id) (rate(gateway_http_request_errors_total[5m]))
  /
sum by (agent_id) (rate(gateway_http_requests_total[5m]))
```
