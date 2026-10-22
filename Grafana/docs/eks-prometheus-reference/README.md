# EKS → AMP Reference Snippets (NOT deployed by this lab)

> These are **reference configurations** for the Kubernetes-centric AMP objectives
> (Prometheus server + exporters, remote write from containers, multi-cluster/hybrid). We do
> **not** provision an EKS cluster in this lab — but these are the real snippets you'd use.
> They tie directly to `prometheus-concepts.md`. Content rephrased from AWS docs for
> licensing compliance.

Replace `<region>`, `<ws-id>`, `<account>` as noted.

---

## 1. IRSA — the service account the collector uses

The collector pod authenticates to AMP with **SigV4** via an IAM role bound to its
Kubernetes service account (IRSA). The role needs `aps:RemoteWrite`.

```yaml
# ServiceAccount annotated with the IAM role ARN (role trusts the EKS OIDC provider)
apiVersion: v1
kind: ServiceAccount
metadata:
  name: amp-remote-write
  namespace: monitoring
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::<account>:role/amp-remote-write-role
```

The IAM role's policy:
```json
{ "Version": "2012-10-17",
  "Statement": [{ "Effect": "Allow", "Action": "aps:RemoteWrite",
    "Resource": "arn:aws:aps:<region>:<account>:workspace/<ws-id>" }] }
```

---

## 2. Prometheus server (Helm) → remote write to AMP

Values for the `prometheus-community/prometheus` chart. The server scrapes cluster targets
and remote-writes to AMP with SigV4.

```yaml
serviceAccounts:
  server:
    name: amp-remote-write          # the IRSA SA above
server:
  remoteWrite:
    - url: https://aps-workspaces.<region>.amazonaws.com/workspaces/<ws-id>/api/v1/remote_write
      sigv4:
        region: <region>
      queue_config:
        max_samples_per_send: 1000
        max_shards: 200
        capacity: 2500
```

Install:
```bash
helm install prometheus prometheus-community/prometheus \
  -n monitoring -f values.yaml
```

> This covers "run a Prometheus server + remote write" and (via the chart's default scrape
> configs) node-exporter / kube-state-metrics / cAdvisor collection.

---

## 3. Minimal scrape config (what the server collects)

```yaml
scrape_configs:
  - job_name: 'kubernetes-nodes'          # node-exporter (host metrics)
    kubernetes_sd_configs: [{ role: node }]
  - job_name: 'kube-state-metrics'        # K8s object state
    static_configs: [{ targets: ['kube-state-metrics.monitoring:8080'] }]
  - job_name: 'kubernetes-cadvisor'       # container metrics (kubelet/cAdvisor)
    kubernetes_sd_configs: [{ role: node }]
    metrics_path: /metrics/cadvisor
  - job_name: 'app-pods'                  # your instrumented apps
    kubernetes_sd_configs: [{ role: pod }]
```

---

## 4. ADOT collector alternative (OpenTelemetry)

Instead of a Prometheus server, run the **ADOT collector**: Prometheus **receiver** (scrape)
→ **prometheusremotewrite** exporter → AMP, with the **sigv4auth** extension.

```yaml
extensions:
  sigv4auth:
    region: <region>
receivers:
  prometheus:
    config:
      scrape_configs:
        - job_name: 'otel-collector'
          static_configs: [{ targets: ['0.0.0.0:8888'] }]
exporters:
  prometheusremotewrite:
    endpoint: https://aps-workspaces.<region>.amazonaws.com/workspaces/<ws-id>/api/v1/remote_write
    auth:
      authenticator: sigv4auth
service:
  extensions: [sigv4auth]
  pipelines:
    metrics:
      receivers: [prometheus]
      exporters: [prometheusremotewrite]
```

> ADOT is the choice when you want **one agent** for metrics (to AMP) **and** traces (to
> X-Ray) — the OpenTelemetry/ADOT direction noted in the X-Ray lab.

---

## 5. Multi-cluster & hybrid

Each cluster runs its own collector pointing at the **same AMP workspace**, tagged so series
are distinguishable:

```yaml
# Prometheus server values — identify the cluster
server:
  global:
    external_labels:
      cluster: prod-eu-central      # unique per cluster
```

Then in PromQL/Grafana:
```promql
sum by (cluster) (rate(http_requests_total[5m]))
```

**Hybrid / on-prem / other cloud:** the same Prometheus/ADOT collector runs anywhere with
network egress to the AMP endpoint and AWS credentials for SigV4 (IAM user/role, or a
sigv4 proxy). It remote-writes into the same workspace — so EKS, on-prem, and other-cloud
clusters all land in one store, one Grafana.

> 📌 **Exam angle:** multi-cluster = many collectors → one AMP, separated by
> **external_labels**. Hybrid works because remote write is authenticated HTTPS from
> anywhere; the only requirements are egress + SigV4 credentials.
