# Amazon Managed Grafana + AMP — Hands-On Walkthrough

> Companion to `grafana-concepts.md` / `prometheus-concepts.md`. Work through it after
> `terraform apply`. Prereq: **IAM Identity Center enabled** (for AMG login).
>
> **Region:** `eu-central-1` · **Profile:** `dev` · **Prefix:** `cloudops-obs-dev`
>
> Content rephrased from AWS docs for licensing compliance.

---

## 0. Deploy

```bash
aws sso login --profile dev
cd Grafana/terraform
terraform init
terraform apply
terraform output
#   amp_workspace_id           = ws-...
#   amp_remote_write_url       = https://aps-workspaces.eu-central-1.amazonaws.com/workspaces/ws-.../api/v1/remote_write
#   grafana_workspace_endpoint = g-....grafana-workspace.eu-central-1.amazonaws.com
```

> 💲 **Cost:** AMG bills per active user/license; AMP per ingested samples + query. Modest
> for a short exploration. `terraform destroy` when done.

---

## 1. Grant yourself access + log in (Identity Center)

AMG has **no local login** — assign an Identity Center user/group to the workspace.

- Console: **Amazon Managed Grafana → workspace → Authentication → Assign new user or
  group** → pick your Identity Center user → set role **Admin**.
  (Or set `grafana_admin_group_id` in Terraform to auto-assign a group as Admin.)
- Then open the **workspace URL** (`grafana_workspace_endpoint`) and sign in via SSO.

> 📌 **Exam angle:** can't log in with a password → AMG uses **Identity Center/SAML**; you
> must **assign** the identity + a role (Admin/Editor/Viewer) first.

---

## 2. Confirm the data sources

In Grafana: **Connections → Data sources**. Because the workspace was created with
`data_sources = ["CLOUDWATCH","XRAY","PROMETHEUS"]` and a CUSTOMER_MANAGED role, you should
see CloudWatch and X-Ray ready. Add the **Prometheus** source pointing at AMP:

- **Add data source → Prometheus**
- **URL:** the AMP workspace endpoint (without the `/api/v1/remote_write` suffix)
- **SigV4 auth: on**, region `eu-central-1` (Grafana signs queries with the workspace role,
  which has `aps:QueryMetrics`).

> 📌 **Exam angle:** Grafana→AMP uses **SigV4** (the workspace IAM role), not a password. The
> role needs `aps:QueryMetrics`/`GetSeries`/`GetLabels` (granted in our module).

---

## 3. Get some metrics into AMP (so there's data to query)

No EKS in this lab, so push a bit of data from your Mac with a local Prometheus in agent
mode (optional), OR just explore CloudWatch/X-Ray panels which have data already.

If you want AMP data, the quickest path is a local Prometheus with the `remote_write` block
from `eks-prometheus-reference/` section 2 (pointing at `amp_remote_write_url`, SigV4 region
`eu-central-1`, using your `dev` credentials). Otherwise skip to §4 using CloudWatch.

> 📌 Reality check: AMP only has data once something **remote-writes** to it. A fresh
> workspace is empty — expected.

---

## 4. Query editor — extract & display metrics

### CloudWatch (has data immediately)
New dashboard → **Add panel** → data source **CloudWatch** → namespace e.g. `AWS/Lambda` →
metric `Invocations` → statistic `Sum`. Try **Metric math** to compute an error rate.

### X-Ray
Panel → data source **X-Ray** → query the service map / trace summaries (if you've run the
X-Ray lab, its traces appear).

### AMP (PromQL)
Panel → data source **Prometheus (AMP)** → enter PromQL, e.g.:
```promql
sum by (instance) (rate(node_cpu_seconds_total[5m]))
```
(See `prometheus-promql.md` for the full reference.)

> 📌 **Exam angle:** each source's editor matches its native model — CloudWatch
> namespace/metric/stat (+ metric math), PromQL for AMP, trace filters for X-Ray.

---

## 5. Dynamic dashboard — template variables

- Dashboard **Settings → Variables → New variable**.
- Type **Query**, data source CloudWatch (or AMP), e.g. a variable `instance` populated from
  a label/dimension query.
- Reference it in panels as `$instance`. Now one dashboard re-scopes to any instance via the
  dropdown — no editing.

> 📌 **Exam angle:** **query-based template variables** = dashboards that adapt to any
> resource automatically. The portable JSON can be shared/provisioned.

---

## 6. AMP alerting → SNS (already wired)

The AMP module created a recording rule, an alerting rule (`HighCPUUtilization`), an alert
manager routing to **SNS**, and (if you set `alert_email`) an email subscription.

- Confirm the SNS email subscription (check your inbox; click confirm) if you set it.
- When the alerting rule fires (needs CPU data > 80% for 5m), the alert manager publishes to
  SNS → your subscription. From SNS you'd fan out to **EventBridge → Lambda/SSM** for
  automatic remediation.

```bash
# Inspect the rule + alert manager definitions
aws amp describe-rule-groups-namespace --workspace-id $(terraform output -raw amp_workspace_id) \
  --name cloudops-obs-dev-rules 2>/dev/null || \
  aws amp list-rule-groups-namespaces --workspace-id $(terraform output -raw amp_workspace_id)
```

> 📌 **Exam angle:** AMP alert manager → **SNS** → EventBridge/Lambda/SSM = the alerting +
> notification + auto-remediation chain. Recording rule precomputes; alerting rule fires.

---

## 7. Users & permissions

Add an Identity Center group as **Editor** (dashboard authors) and another as **Viewer**:
**workspace → Authentication → Assign** → choose group → role. Prefer groups over individuals.

> 📌 **Exam angle:** Admin/Editor/Viewer via Identity Center/SAML; not manageable from the
> Grafana UI itself.

---

## 8. Clean up

```bash
cd Grafana/terraform
terraform destroy
```

---

## Deploy-and-explore checklist

- [ ] Assigned an Identity Center user as **Admin**; logged into the workspace via SSO.
- [ ] Saw CloudWatch + X-Ray data sources; added the **AMP (Prometheus, SigV4)** source.
- [ ] Built a panel from the **CloudWatch** query editor (+ metric math).
- [ ] (Optional) Remote-wrote metrics to AMP and queried with **PromQL**.
- [ ] Made a **template variable** → dynamic dashboard.
- [ ] Confirmed the **AMP alert → SNS** wiring (email sub / rule definitions).
- [ ] Assigned Editor/Viewer to groups.
- [ ] `terraform destroy`.
