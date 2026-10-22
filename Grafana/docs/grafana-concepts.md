# Amazon Managed Grafana — Concept Reference (CloudOps Exam Prep)

> Reference for the Grafana objectives. This lab is **deployable** (`Grafana/terraform/`) —
> AMG + AMP workspaces. Pair with `grafana-walkthrough.md` for hands-on, and the
> `prometheus-*` docs for AMP/PromQL. Content rephrased from AWS docs for licensing
> compliance.

---

## 0. What Amazon Managed Grafana (AMG) is

AMG is **fully managed Grafana** — dashboards and visualization over many data sources, with
AWS handling scaling, patching, and HA. It **visualizes**; it doesn't store metrics (that's
CloudWatch / AMP / etc.).

> 📌 **Exam framing:** AMG = visualization/dashboards. Metric *stores* are CloudWatch, AMP,
> X-Ray (traces). AMG queries them and draws panels.

---

## 1. Workspace

The **workspace** is the Grafana instance. Key configuration:
- **Authentication providers:** **IAM Identity Center (AWS_SSO)** or **SAML**. **No local
  username/password** — this is the headline constraint.
- **Permission type:** **SERVICE_MANAGED** (AMG manages the data-source IAM policies for you)
  vs **CUSTOMER_MANAGED** (you own the role + policy — what our lab uses).
- **Account access type:** **CURRENT_ACCOUNT** vs **ORGANIZATION** (multi-account via
  delegated admin + OUs).
- **Data sources:** declared on the workspace (CLOUDWATCH, XRAY, PROMETHEUS, …).

> 📌 **Exam angle:** AMG login requires an **IdP (Identity Center/SAML)** — a frequent "why
> can't I log in with a Grafana password?" question. SERVICE_MANAGED vs CUSTOMER_MANAGED
> governs who owns the data-source permissions.

---

## 2. Authentication & secure access

- **IAM Identity Center (AWS_SSO):** users/groups from Identity Center sign in via SSO.
  Simplest within one AWS org. (Our lab.)
- **SAML:** federate an external IdP (Okta, Azure AD, etc.) directly to the workspace.
- **Data-source access** is via the workspace's **IAM role** (SigV4 to CloudWatch/AMP/X-Ray)
  — users never hold those AWS creds; Grafana queries on their behalf.
- **Network:** can be public or locked to a VPC; private data sources reached via VPC
  configuration/endpoints.

> 📌 **Exam angle:** two separate layers — **who can log in** (Identity Center/SAML) and
> **what Grafana can read** (the workspace IAM role). Don't conflate them.

---

## 3. Users & permissions

Three workspace roles: **Admin · Editor · Viewer**.
- **Admin** — manage data sources, users, and all dashboards.
- **Editor** — create/edit dashboards.
- **Viewer** — read-only.

Assignment is done via **Identity Center/SAML users & groups**, NOT inside the Grafana UI
(user management from the workspace UI is not supported in AMG). Our Terraform shows an
`aws_grafana_role_association` granting a group ADMIN.

> 📌 **Exam angle:** roles = Admin/Editor/Viewer, assigned to **Identity Center or SAML
> identities** (console/API/Terraform), not via Grafana-local accounts. Prefer **group**
> assignments over individual users for scale.

---

## 4. Data sources

Built-in AWS data sources: **CloudWatch** (metrics + Logs Insights), **X-Ray** (traces),
**Amazon Managed Prometheus** (PromQL), **Amazon OpenSearch**, **Athena/Redshift/Timestream**,
**IoT SiteWise**. Plus the whole Grafana ecosystem of **third-party** sources.

> 📌 **Exam angle:** AMG natively integrates the AWS observability trio **CloudWatch +
> X-Ray + AMP**. These three give you metrics, traces, and PromQL in one pane.

---

## 5. Third-party data sources

AMG supports many non-AWS sources — **Prometheus (self-hosted), Loki, Elasticsearch,
InfluxDB, Postgres/MySQL, Datadog, Splunk, GitHub,** etc. Some are built-in; others are
**plugins** (AMG supports a curated set of plugins, enabled per workspace).

> 📌 **Exam angle:** "visualize AWS + non-AWS telemetry in one place" → AMG with mixed data
> sources. Plugin availability is per-workspace and AMG-curated (not arbitrary like
> self-managed Grafana).

---

## 6. Query editor — extracting metrics

Each data source has a **query editor**:
- **CloudWatch:** pick namespace → metric → dimensions → statistic/period; or **Metric
  Insights** (SQL-like) and **metric math** for computed series.
- **X-Ray:** query traces/service map by group, error/fault filters.
- **Prometheus/AMP:** write **PromQL** (see `prometheus-promql.md`).

> 📌 **Exam angle:** the query editor maps to each source's native model (CloudWatch
> namespace/dimension/statistic; PromQL for AMP). Metric math / Metric Insights compute
> derived series without a separate pipeline.

---

## 7. Dynamic dashboards

- **Panels** visualize one or more queries (time series, gauge, table, heatmap, …).
- **Template variables** make dashboards **dynamic** — e.g. a `$region`, `$instance`, or
  `$namespace` dropdown that re-scopes every panel. Variables can be **query-based** (populated
  from the data source) so they auto-update as resources change.
- **Annotations** overlay events (deploys, alarms) on graphs.
- Dashboards are **JSON** — exportable/importable, provisionable via the Grafana HTTP API.

> 📌 **Exam angle:** "one dashboard that works for any instance/region without editing" →
> **template variables** (ideally query-based). Dashboards are portable JSON.

---

## 8. Query optimization (performance & cost)

- **Right-size time range + interval** — don't pull 1s resolution over 30 days.
- **Use recording rules (AMP)** to precompute expensive PromQL once, then graph the cheap
  recorded series (also cuts CloudWatch `GetMetricData` cost on the AMG side).
- **Minimize high-cardinality queries** — many label combinations are slow/expensive.
- **Caching** — AMG can cache data-source query results to cut repeated backend calls.
- **CloudWatch cost:** each panel refresh issues API calls (`GetMetricData`) — fewer/narrower
  queries + sensible refresh intervals reduce spend.

> 📌 **Exam angle:** optimize by **narrowing time/resolution**, **recording rules** for
> repeated heavy queries, **avoiding high cardinality**, and **caching**. CloudWatch billing
> is per API call, so dashboard refresh rate matters.

---

## 9. Alerts & notifications

- **Grafana alerting** evaluates alert rules on dashboard queries and routes via **contact
  points** (SNS, Slack, PagerDuty, email, webhook) with **notification policies**.
- Complementary to **AMP alert manager** (server-side alerting on PromQL) and **CloudWatch
  alarms**. You can visualize all three in AMG.

> 📌 **Exam angle:** alerting can live in **Grafana** (on panel queries), in **AMP** (alert
> manager on PromQL rules), or in **CloudWatch** (alarms). AMG unifies the *view*; choose the
> alerting engine by where the data + logic belong.

---

## Quick-recall cheat sheet

| Question | One-line answer |
|---|---|
| AMG login method? | **IAM Identity Center or SAML** — no local passwords |
| Who manages data-source IAM? | SERVICE_MANAGED (AMG) vs CUSTOMER_MANAGED (you) |
| Roles? | **Admin / Editor / Viewer**, assigned via Identity Center/SAML (not Grafana UI) |
| Native AWS data sources? | **CloudWatch, X-Ray, AMP** (+ OpenSearch, Athena, …) |
| Dashboard that adapts to any resource? | **template variables** (query-based) |
| Make heavy PromQL cheaper to graph? | **recording rules** in AMP |
| Reduce CloudWatch dashboard cost? | fewer/narrower queries + refresh interval (per-API-call billing) |
| Visualize AWS + non-AWS together? | mixed **data sources / plugins** |
| Where does alerting run? | Grafana alerting / AMP alert manager / CloudWatch alarms |
