# Governance Ops

A Helm chart for deploying operational monitoring resources for the EQTY Lab Governance Platform on Kubernetes.

## Description

Governance Ops provides Grafana dashboards and Prometheus alerts for monitoring Governance Platform deployments. It enables comprehensive observability of platform health, service availability, resource usage, and error rates.

Key capabilities:

- **Grafana Dashboards**: Pre-built dashboards for platform overview, request traffic, and resource utilization
- **Prometheus Alerts**: Tiered alerting (warning/critical) for service health and resource constraints
- **Blackbox Probes**: HTTP/HTTPS endpoint monitoring with automatic ingress discovery (optional, requires blackbox-exporter)
- **Auto-Discovery**: Dashboards automatically discovered by Grafana sidecar via ConfigMap labels
- **Independent Deployment**: Deploy monitoring resources separately from the platform for easier updates
- **Configurable Thresholds**: Customize alert thresholds for memory, CPU, error rates, and storage

## Prerequisites

**Required:**
- Kubernetes 1.21+
- Helm 3.8+
- kube-prometheus-stack deployed with:
  - Prometheus for metrics collection
  - Grafana with sidecar enabled for dashboard auto-discovery
  - AlertManager for alert routing (if using alerts)
- kube-state-metrics (included in kube-prometheus-stack)
- nginx-ingress-controller with metrics enabled (for request/error rate panels)

**Optional:**
- prometheus-blackbox-exporter (for HTTP/HTTPS endpoint probes and endpoint down alerts)

## Deployment

Deploy this chart alongside your governance-platform instance to enable comprehensive monitoring.

### Quick Start

Minimum configuration required:

```bash
helm install governance-ops ./charts/governance-ops \
  --namespace monitoring \
  --set targetRelease=governance-platform
```

This creates:
- Grafana dashboard ConfigMap (auto-discovered by Grafana sidecar)
- Prometheus alert rules (discovered by Prometheus Operator)
- Blackbox exporter probes (if prometheus-blackbox-exporter is installed)

Dashboards, alerts, and probes are **enabled by default**. Probes are only created if blackbox-exporter is available.

**Note on Endpoint Monitoring Panels**: The Grafana dashboard includes an "Endpoint Monitoring" section with panels that display HTTP/HTTPS endpoint availability. If prometheus-blackbox-exporter is not installed, these panels will show "No data". You can manually hide or delete the "Endpoint Monitoring" row in Grafana if you don't plan to use endpoint monitoring.

### Deploying to a Custom Namespace

```bash
helm install governance-ops ./charts/governance-ops \
  --namespace my-namespace \
  --set targetRelease=governance-platform
```

### Customizing Alerts and Probes

Create a values file to customize alert behavior:

```yaml
# custom-values.yaml
targetRelease: governance-platform

alerts:
  enabled: true
  interval: 30s
  rules:
    highMemoryUsage:
      enabled: true
      warningThreshold: 0.80   # Alert at 80% instead of 75%
      criticalThreshold: 0.95  # Critical at 95% instead of 90%

    highErrorRate:
      warningThreshold: 0.02   # 2% error rate
      criticalThreshold: 0.10  # 10% error rate

    # Disable specific alerts
    memorySpike:
      enabled: false

probes:
  enabled: true
  interval: 30s          # Probe frequency
  staticProbes:          # Add custom endpoints
    - name: external-api
      url: https://api.example.com/health
```

Deploy with custom values:

```bash
helm install governance-ops ./charts/governance-ops \
  -f custom-values.yaml \
  --namespace monitoring
```

### Disabling Dashboards or Alerts

```bash
# Disable dashboards
helm install governance-ops ./charts/governance-ops \
  --namespace monitoring \
  --set dashboards.enabled=false

# Disable alerts
helm install governance-ops ./charts/governance-ops \
  --namespace monitoring \
  --set alerts.enabled=false
```

### Uninstalling

```bash
helm uninstall governance-ops --namespace monitoring
```

This removes all monitoring resources (ConfigMaps and PrometheusRules) but does not affect your governance-platform deployment.

## Values

### Target Release Configuration

| Key           | Type   | Default                 | Description                                                    |
| ------------- | ------ | ----------------------- | -------------------------------------------------------------- |
| targetRelease | string | `"governance-platform"` | Helm release name of the governance-platform deployment to monitor |

### Dashboard Configuration

| Key                                | Type | Default | Description                                                      |
| ---------------------------------- | ---- | ------- | ---------------------------------------------------------------- |
| dashboards.enabled                 | bool | `true`  | Enable dashboard provisioning                                    |
| dashboards.labels                  | map  | `{}`    | Additional labels for dashboard ConfigMaps                       |
| dashboards.annotations             | map  | `{}`    | Additional annotations for dashboard ConfigMaps                  |
| dashboards.platformOverview.enabled | bool | `true`  | Enable Governance Platform Overview dashboard                    |

**Governance Platform Dashboard** includes:
- Platform Health: Service uptime gauges and replica counts
- Service Readiness Timeline: Real-time readiness status
- Request Traffic: Request rates per service from nginx ingress
- Server Error Rates (5xx): Error tracking for service health
- Resource Utilization: CPU and memory usage by pod

Requirements: kube-state-metrics, nginx-ingress-controller with metrics enabled

### Alert Configuration

| Key                | Type   | Default | Description                                   |
| ------------------ | ------ | ------- | --------------------------------------------- |
| alerts.enabled     | bool   | `true`  | Enable Prometheus alert provisioning          |
| alerts.interval    | string | `"30s"` | How often Prometheus evaluates alert rules    |
| alerts.labels      | map    | `{}`    | Additional labels for PrometheusRule resource |
| alerts.annotations | map    | `{}`    | Additional annotations for PrometheusRule     |
| alerts.customRules | list   | `[]`    | Additional custom alert rules                 |

### Alert Rules

All alert rules can be individually enabled/disabled and have configurable thresholds:

**Service Availability Alerts:**

| Alert              | Default Enabled | Default Threshold | Description                     |
| ------------------ | --------------- | ----------------- | ------------------------------- |
| serviceDown        | `true`          | 5m                | Service has no available replicas |
| podNotReady        | `true`          | 10m               | Pods not ready for extended period |
| podCrashLooping    | `true`          | 5m                | Pods crash looping              |

**Resource Usage Alerts (Tiered):**

| Alert           | Warning Threshold | Warning Duration | Critical Threshold | Critical Duration |
| --------------- | ----------------- | ---------------- | ------------------ | ----------------- |
| highMemoryUsage | 75%               | 10m              | 90%                | 5m                |
| highCpuUsage    | 75%               | 10m              | 90%                | 5m                |
| highErrorRate   | 1%                | 5m               | 5%                 | 2m                |
| persistentVolumeUsage | 75%         | 15m              | 90%                | 5m                |

**Memory Leak Detection:**

| Alert       | Default Threshold | Description                              |
| ----------- | ----------------- | ---------------------------------------- |
| memorySpike | 30% in 5min       | Detects rapid memory growth (potential leak) |

All thresholds can be customized via values. See [Customizing Alert Thresholds](#customizing-alert-thresholds) above.

## Verifying Deployment

### Check Dashboard Discovery

```bash
# Verify dashboard ConfigMap was created
kubectl get configmaps -n monitoring -l grafana_dashboard=1 | grep governance

# Check Grafana sidecar logs
kubectl logs -n monitoring deployment/kube-prometheus-stack-grafana -c grafana-sc-dashboard --tail=20
```

### Access Grafana Dashboard

1. Access your Grafana instance
2. Navigate to **Dashboards** → **Browse**
3. Look for **Governance Platform** dashboard
4. Use the **Namespace** dropdown to select your deployment namespace

### Check Prometheus Alerts

```bash
# Verify PrometheusRule was created
kubectl get prometheusrule -n monitoring | grep governance

# View alert rules in Prometheus
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090
# Open: http://localhost:9090/alerts
```

### Check Probes (if blackbox-exporter installed)

```bash
# Verify Probe resources were created
kubectl get probe -n monitoring -l app.kubernetes.io/instance=governance-ops

# View probe metrics in Prometheus
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090
# Open: http://localhost:9090/graph?g0.expr=probe_success
```

### Check AlertManager

```bash
# View active alerts
kubectl port-forward -n monitoring svc/kube-prometheus-stack-alertmanager 9093:9093
# Open: http://localhost:9093
```

## Troubleshooting

### Dashboards Not Appearing in Grafana

**Check if ConfigMap exists:**

```bash
kubectl get configmaps -n monitoring -l grafana_dashboard=1
```

**Check Grafana sidecar logs:**

```bash
kubectl logs -n monitoring deployment/kube-prometheus-stack-grafana -c grafana-sc-dashboard -f
```

**Force Grafana to reload dashboards:**

```bash
kubectl rollout restart deployment/kube-prometheus-stack-grafana -n monitoring
```

**Verify sidecar configuration:**

```bash
helm get values kube-prometheus-stack -n monitoring | grep -A 10 sidecar
```

### Alerts Not Firing

**Check if PrometheusRule was created:**

```bash
kubectl get prometheusrule -n monitoring
kubectl describe prometheusrule governance-platform-alerts -n monitoring
```

**Verify Prometheus discovered the rules:**

```bash
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090
# Open: http://localhost:9090/rules
# Look for "governance-platform" rules
```

**Check Prometheus Operator logs:**

```bash
kubectl logs -n monitoring deployment/kube-prometheus-stack-prometheus-operator
```

**Verify label selectors match:**

The PrometheusRule must have labels that match your Prometheus `ruleSelector`. Check:

```bash
kubectl get prometheus -n monitoring -o yaml | grep -A 5 ruleSelector
```

If needed, add matching labels:

```yaml
alerts:
  labels:
    release: kube-prometheus-stack  # Match your Prometheus ruleSelector
```

### Metrics Not Showing in Dashboard

**Verify Prometheus is scraping targets:**

```bash
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090
# Open: http://localhost:9090/targets
# Verify governance-platform services are listed and UP
```

**Check if nginx ingress metrics are available:**

```bash
# Port-forward to Prometheus
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090

# Query nginx metrics
# Open: http://localhost:9090/graph
# Query: nginx_ingress_controller_requests
```

**Generate traffic to populate panels:**

Request/Error rate panels require active traffic. Access your governance platform to generate initial metrics.

### AlertManager Not Sending Notifications

**Check AlertManager configuration:**

```bash
kubectl get secret -n monitoring alertmanager-kube-prometheus-stack-prometheus-alertmanager -o yaml
```

**View AlertManager logs:**

```bash
kubectl logs -n monitoring alertmanager-kube-prometheus-stack-prometheus-alertmanager-0
```

**Test alert routing:**

Create a test alert to verify AlertManager routing is working. See the kube-prometheus-stack documentation for details.

## Integration with kube-prometheus-stack

This chart is designed to work with the kube-prometheus-stack. For full monitoring setup including Grafana OAuth, AlertManager notifications, and more, see:

- [Monitoring Setup Guide](../../docs/monitoring-setup.md)
- [kube-prometheus-stack Documentation](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack)

## Support

For issues and questions:

- Email: support@eqtylab.io
- Documentation: https://docs.eqtylab.io
- GitHub: https://github.com/eqtylab/governance-studio-infrastructure
