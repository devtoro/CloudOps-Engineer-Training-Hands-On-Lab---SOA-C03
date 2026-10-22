# Amazon Managed Service for Prometheus (AMP) — Concept Reference

> Reference for the AMP objectives. The **AMP workspace + alerting** is deployable
> (`Grafana/terraform/modules/prometheus-workspace`). The **EKS/Kubernetes** pieces
> (Prometheus server, exporters, remote write, multi-cluster/hybrid) are **reference-only**
> — see `eks-prometheus-reference/`. PromQL has its own doc (`prometheus-promql.md`).
> Content rephrased from AWS docs for licensing compliance.

---

## 0. What AMP is

AMP is a **managed, Prometheus-compatible metrics store**: it ingests time-series via
**remote write**, stores them at scale (HA, long retention), and serves **PromQL** queries.
It does **not scrape** by itself — a collector (Prometheus server or ADOT) pushes metrics in.

```
exporters / instrumented apps
   │ (scraped by)
Prometheus server OR ADOT collector  (customer-managed collector)
   │ remote_write (SigV4)
   ▼
AMP workspace  ──query (PromQL, SigV4)──►  Amazon Managed Grafana
   │
   └─ alert manager → SNS → EventBridge/Lambda (remediation)
```

> 📌 **Exam framing:** AMP = **storage + query + alerting**, not collection. Something else
> scrapes and **remote-writes** to it. Grafana reads it via PromQL.

---

## 1. Ingestion — remote write (the only way in)

- Metrics enter AMP via the **remote-write endpoint**:
  `https://aps-workspaces.<region>.amazonaws.com/workspaces/<ws-id>/api/v1/remote_write`
- **Collectors** that remote-write:
  - **Prometheus server in agent mode** (or full server) with a `remote_write` block.
  - **ADOT collector** (AWS Distro for OpenTelemetry) with the Prometheus Remote Write
    Exporter + SigV4 auth extension.
- **Auth = SigV4 (IAM).** No username/password. The writer's IAM identity needs
  **`aps:RemoteWrite`**.

> 📌 **Exam angle:** "how do metrics get into AMP?" → **remote write** from a Prometheus
> server or **ADOT**, authenticated with **SigV4**. The write permission is `aps:RemoteWrite`.

---

## 2. Secure access (SigV4 + IAM)

- **Writers:** `aps:RemoteWrite` on the workspace.
- **Readers (Grafana, PromQL clients):** `aps:QueryMetrics`, `aps:GetSeries`, `aps:GetLabels`,
  `aps:GetMetricMetadata`.
- On **EKS**, the collector pod gets these via **IRSA** (IAM Roles for Service Accounts) — a
  service account annotated with an IAM role, so no static keys.
- Private connectivity via **VPC interface endpoints** (PrivateLink) if you don't want
  traffic over the public endpoint.

> 📌 **Exam angle:** AMP access is **IAM/SigV4**, split into write (`aps:RemoteWrite`) and
> read (`aps:QueryMetrics` …). On EKS use **IRSA**, not node creds or keys.

---

## 3. Rules — recording & alerting

AMP evaluates **rule groups** (standard Prometheus rules YAML) server-side:
- **Recording rule** — precompute an expensive PromQL expression into a new series
  (`record:`). Speeds up dashboards + cuts repeated compute. (Our lab records
  `instance:node_cpu_utilization:rate5m`.)
- **Alerting rule** — fire an alert when an expression is true for a `for:` duration
  (`alert:`). (Our lab: `HighCPUUtilization` > 80% for 5m.)

> 📌 **Exam angle:** **recording = performance/cost** (precompute); **alerting = fire on a
> condition**. Both are PromQL in rule-group YAML, evaluated by AMP.

---

## 4. Alerting, notifications & remediation

- AMP has a **managed alert manager** — define routing + receivers in alertmanager YAML.
- **Receiver = SNS** (our lab): firing alerts publish to an SNS topic (AMP publishes as the
  `aps.amazonaws.com` service principal; the topic policy allows it).
- From SNS you **fan out**: email/Slack, or **EventBridge/Lambda/SSM Automation** for
  **automatic remediation** (reusing the pattern from the EventBridge + SSM labs).

> 📌 **Exam angle:** AMP alert manager → **SNS** → (notification + **EventBridge→SSM
> remediation**). This is the "alerts, notifications, automatic remediation" chain.

---

## 5. Collecting Kubernetes metrics — exporters (reference)

In a cluster, metrics come from **exporters** that expose `/metrics`:
- **node-exporter** — per-node CPU/mem/disk/network (host metrics).
- **kube-state-metrics** — cluster object state (deployments, pods, replicas).
- **cAdvisor / kubelet** — container resource usage (built into the kubelet).
- **app exporters** — your apps instrumented with a Prometheus client library.

A **Prometheus server** (or ADOT) **scrapes** these endpoints, then **remote-writes** to AMP.
See `eks-prometheus-reference/` for Helm values + scrape config.

> 📌 **Exam angle:** know the big exporters — **node-exporter** (host), **kube-state-metrics**
> (K8s object state), **cAdvisor/kubelet** (containers). The server scrapes; AMP stores.

---

## 6. Containers → AMP via remote write (reference)

Two common patterns on EKS:
1. **Prometheus (agent mode) + remote_write** — lightweight; scrapes locally, forwards to AMP.
2. **ADOT collector** — OpenTelemetry collector with the Prometheus receiver + remote-write
   exporter + SigV4 extension.

Both authenticate with **SigV4 via IRSA**. Config snippets in `eks-prometheus-reference/`.

> 📌 **Exam angle:** "send container metrics to AMP" → Prometheus agent **or** ADOT, both
> **remote_write + SigV4 + IRSA**. Agent mode is the slim option; ADOT unifies with traces/logs.

---

## 7. Multi-cluster & hybrid (reference / concept)

- **Multi-cluster:** each cluster runs its own collector and **remote-writes to the same AMP
  workspace**. Use **`external_labels`** (e.g. `cluster="prod-eu"`) so series are
  distinguishable; query/aggregate across clusters in PromQL/Grafana.
- **Hybrid / on-prem / other clouds:** any Prometheus/ADOT collector with network egress +
  AWS credentials (or SigV4 proxy) can remote-write to AMP — so non-EKS and on-prem clusters
  land in the same store.
- One AMP workspace + one Grafana = a **single pane** across all clusters/environments.

> 📌 **Exam angle:** many clusters → **one AMP** via remote write, distinguished by
> **external_labels**. Hybrid works because remote write is just authenticated HTTPS — the
> source can be anywhere with egress + SigV4.

---

## 8. AMP vs CloudWatch metrics (disambiguation)

| | **AMP** | **CloudWatch metrics** |
|---|---|---|
| Model | Prometheus (labels + PromQL) | namespace/dimension + CloudWatch stats |
| Best for | Kubernetes/container + app metrics, PromQL ecosystems | AWS service metrics, native integrations |
| Ingest | remote write (pull-then-push) | AWS services publish automatically; PutMetricData |
| Query | **PromQL** | Metric math / Metric Insights |

> 📌 **Exam angle:** container/K8s + PromQL world → **AMP**. Native AWS service metrics →
> **CloudWatch**. Grafana can show both side by side.

---

## Quick-recall cheat sheet

| Question | One-line answer |
|---|---|
| How do metrics enter AMP? | **remote write** (Prometheus agent / ADOT), **SigV4** |
| Write vs read permission? | `aps:RemoteWrite` vs `aps:QueryMetrics` (+ GetSeries/Labels) |
| Auth on EKS? | **IRSA** (service account → IAM role), no static keys |
| Precompute heavy query? | **recording rule** (`record:`) |
| Fire on a condition? | **alerting rule** (`alert:` + `for:`) → alert manager → SNS |
| Auto-remediate from an alert? | SNS → **EventBridge → Lambda/SSM** |
| Key K8s exporters? | node-exporter, kube-state-metrics, cAdvisor/kubelet |
| Many clusters into AMP? | all **remote-write to one workspace**, tag with `external_labels` |
| Hybrid/on-prem? | any collector with egress + SigV4 remote-writes to AMP |
| AMP vs CloudWatch? | PromQL/K8s vs native AWS service metrics |
