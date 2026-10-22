# AWS CloudOps Engineer Training — Hands-On Lab

## Purpose

Practical, hands-on training for the **AWS Certified SysOps Administrator (CloudOps)** exam.
The learner already holds the **AWS Solutions Architect Associate** certificate.

The approach: build a small AWS application, deliberately break it, and observe everything
through CloudWatch. Every phase adds a new observability layer.

---

## Architecture — Order Processing Platform

```
                ┌─────────────────┐
                │   API Gateway   │  (REST API)
                └────────┬────────┘
                         │
                         ▼
                ┌─────────────────┐
                │ Lambda: Orders  │
                └───────┬─────────┘
                        │
             ┌──────────┴──────────┐
             ▼                     ▼
      ┌─────────────┐       ┌─────────────┐
      │  DynamoDB   │       │ EventBridge │
      │  (orders)   │       │   (bus)     │
      └─────────────┘       └──────┬──────┘
                                   │
                                   ▼
                            ┌─────────────┐
                            │ Lambda:      │
                            │ Processor    │
                            └──────┬──────┘
                                   │
                                   ▼
                              CloudWatch
                       ┌──────────┼──────────┐
                       │          │          │
                    Metrics      Logs     Alarms
                       │          │          │
                       └──────────┼──────────┘
                                  ▼
                              Dashboard
```

The application exists primarily to **generate observability data**, not to be a
production-quality system. Keep everything minimal and cheap.

---

## Key Decisions

| Decision             | Choice                          | Rationale                                                                 |
|----------------------|---------------------------------|---------------------------------------------------------------------------|
| IaC tool             | **Terraform** (modular)         | Matches learner workflow; extensible for future phases                     |
| API Gateway type     | **REST API**                    | Richer CloudWatch metrics (IntegrationLatency, stage throttling, etc.)     |
| DynamoDB capacity    | **Provisioned (very low RCU/WCU)** | Deliberately small to trigger throttling and observe capacity metrics  |
| AWS region           | **eu-central-1**                | Learner's AWS SSO region                                                  |
| AWS credentials      | **AWS SSO profile `dev`**       | `aws sso login --profile dev`; pinned in each lab's `providers.tf`         |
| Terraform state      | **Local**                       | Simplest for a lab; can migrate to S3 later                               |
| Lambda runtime       | **Python 3.12**                 | Lightweight, fast iteration, easy to read                                 |

---

## Repository Structure

```
AWS/
├── README.md                       ← this file (project context + resumption state)
├── Cloudwatch/
│   ├── terraform/
│   │   ├── main.tf                 # root module: wires all child modules together
│   │   ├── variables.tf            # project-wide inputs (region, project name, env)
│   │   ├── outputs.tf              # API URL, table name, function ARNs
│   │   ├── providers.tf            # AWS provider config + version pins
│   │   ├── backend.tf              # state backend (local)
│   │   └── modules/
│   │       ├── dynamodb/           # orders table (provisioned, low capacity)
│   │       ├── lambda-orders/      # API-facing Lambda
│   │       ├── lambda-processor/   # EventBridge-triggered Lambda
│   │       ├── api-gateway/        # REST API fronting orders Lambda
│   │       └── eventbridge/        # custom bus + rule: orders → processor
│   ├── src/
│   │   ├── orders/                 # orders Lambda handler (Python)
│   │   │   └── handler.py
│   │   └── processor/              # processor Lambda handler (Python)
│   │       └── handler.py
│   ├── scripts/
│   │   └── generate-traffic.sh     # fires happy/4XX/5XX/slow/processor-fail/no-key traffic
│   └── docs/
│       ├── phase-1-notes.md        # learner's written answers (metrics concepts)
│       ├── phase-1-checkpoint-7-metrics-exploration.md   # guided CloudWatch metrics tour
│       ├── xray-concepts.md        # X-Ray concept reference (traces/segments, sampling, service map, ADOT)
│       └── xray-walkthrough.md     # X-Ray hands-on (trace map, bottleneck, fault vs error, async propagation)
│   # NOTE: Lambda handlers + api-gateway/lambda modules now X-Ray-instrumented
│   #       (active tracing, aws-xray-sdk subsegments, manual trace propagation)
│
└── Cloudtrail/                     # CloudTrail lab — own Terraform state, independent
    ├── terraform/
    │   ├── main.tf                 # root: wires trail-s3, cloudtrail, cloudtrail-cwlogs
    │   ├── variables.tf            # region/profile, multi-region, insights, retention, data-event ARNs
    │   ├── outputs.tf              # bucket name, kms arn, trail name, cwl group
    │   ├── providers.tf            # AWS provider (profile=dev, eu-central-1)
    │   ├── backend.tf              # state backend (local)
    │   └── modules/
    │       ├── trail-s3/           # S3 bucket + KMS key/policy + bucket policy + lifecycle
    │       ├── cloudtrail/         # the trail: multi-region, validation, event selectors, Insights
    │       └── cloudtrail-cwlogs/  # CWL group + IAM role CloudTrail assumes + root-usage metric filter/alarm
    └── docs/
        ├── cloudtrail-concepts.md      # concept reference (mgmt/data events, global/regional, integrity, Insights)
        └── cloudtrail-walkthrough.md   # hands-on deploy/explore/validate tutorial (console + CLI)
│
└── Config/                         # AWS Config lab — own Terraform state, independent
    ├── terraform/
    │   ├── main.tf                 # root: wires config-recorder, config-rules, config-remediation
    │   ├── variables.tf            # region/profile, record-all toggle, required_tag_keys
    │   ├── outputs.tf              # bucket, recorder name, rule names
    │   ├── providers.tf            # AWS provider (profile=dev, eu-central-1)
    │   ├── backend.tf              # state backend (local)
    │   └── modules/
    │       ├── config-recorder/    # S3 bucket + policy + IAM role + recorder + delivery channel + status
    │       ├── config-rules/       # managed rules (SSE, required-tags) + custom Lambda rule
    │       └── config-remediation/ # SSM Automation remediation + assume-role on the SSE rule
    ├── src/
    │   └── s3_naming_rule/         # custom Config rule Lambda (dummy S3 naming check)
    │       └── handler.py
    └── docs/
        ├── config-concepts.md      # concept reference (recorder/CI/rules, remediation, aggregators, Config vs CloudTrail)
        └── config-walkthrough.md   # hands-on deploy/explore/remediate tutorial (console + CLI)
│
└── Eventbridge/                    # EventBridge lab — own state; dual-region (eu-central-1 + eu-west-1)
    ├── terraform/
    │   ├── main.tf, variables.tf, outputs.tf, providers.tf (2 provider aliases), backend.tf
    │   └── modules/
    │       ├── demo-target/        # EC2 instance to auto-heal + SNS + log-target Lambda
    │       ├── rules-patterns/     # custom bus + 5 pattern rules + 1 AWS-service-event rule
    │       ├── autoheal-ssm/       # EC2 state-change → SSM AWS-RestartEC2Instance (2 roles, DLQ, retry)
    │       ├── alarm-to-eventbridge/ # CloudWatch alarm state change → SSM auto-heal (reuses autoheal roles)
    │       └── cross-region/       # source bus (eu-central-1) → destination bus (eu-west-1) + policies
    ├── src/
    │   └── log_target/             # trivial Lambda that logs received events (rule-match visibility)
    │       └── handler.py
    └── docs/
        ├── eventbridge-concepts.md     # concept reference (buses, patterns, auto-heal, cross-acct, API destinations)
        └── eventbridge-walkthrough.md  # hands-on (patterns, auto-heal ×2, cross-Region, troubleshooting)
│
└── Securityhub/                    # Security Hub lab — REFERENCE CODE (validated, not deployed)
    ├── terraform/
    │   ├── main.tf, variables.tf, outputs.tf, providers.tf, backend.tf
    │   └── modules/
    │       ├── securityhub-core/   # enable hub + FSBP/CIS standards + GuardDuty + aggregator; org (commented)
    │       ├── findings-export/    # EventBridge → Firehose → S3 (Lambda alternative commented)
    │       └── finding-response/   # EventBridge HIGH/CRITICAL findings → Lambda (SSM commented)
    ├── src/
    │   └── finding_response/       # responder Lambda (parses ASFF finding, logs, placeholder for action)
    │       └── handler.py
    └── docs/
        ├── securityhub-concepts.md     # concept reference (ASFF, standards, severity, Insights, org, Audit Manager)
        └── securityhub-walkthrough.md  # reference / "if deployed" console + CLI tour
│
└── Systemsmanager/                 # Systems Manager lab — own state; DEPLOYABLE (1 t3.micro node)
    ├── terraform/
    │   ├── main.tf, variables.tf, outputs.tf, providers.tf, backend.tf
    │   └── modules/
    │       ├── managed-instance/   # EC2 + SSM agent + instance profile; hybrid activation (commented)
    │       ├── session-manager/    # session logging S3 + CWL via SSM-SessionManagerRunShell doc
    │       ├── patch-manager/      # custom baseline + patch group + maintenance window (Scan)
    │       ├── run-and-inventory/  # Run Command association + Inventory (AWS-GatherSoftwareInventory)
    │       └── automation-eventbridge/ # custom Automation doc (0.3) + scheduled EventBridge trigger
    └── docs/
        ├── ssm-concepts.md         # concept reference (agents, Session Mgr, Patch, Run, hybrid, Inventory, Automation)
        └── ssm-walkthrough.md      # hands-on (Session Manager, Run Command, patch scan, Inventory, Automation)
│
└── Grafana/                        # Managed Grafana + Managed Prometheus lab — own state; DEPLOYABLE
    ├── terraform/
    │   ├── main.tf, variables.tf, outputs.tf, providers.tf, backend.tf
    │   └── modules/
    │       ├── prometheus-workspace/ # AMP workspace + recording/alert rules + alert manager → SNS
    │       └── grafana-workspace/    # AMG workspace + IAM role + CloudWatch/X-Ray/AMP sources + SSO
    └── docs/
        ├── grafana-concepts.md       # AMG concepts (workspace, auth, users, data sources, query opt, dashboards)
        ├── grafana-walkthrough.md    # hands-on AMG (SSO assign, data sources, query editor, dynamic dashboard, alert)
        ├── prometheus-concepts.md    # AMP concepts (remote write, SigV4, rules, alerting, K8s, multi-cluster)
        ├── prometheus-promql.md      # PromQL reference (data model, selectors, functions, aggregation, examples)
        └── eks-prometheus-reference/ # NON-deployed K8s snippets (IRSA, Prometheus Helm, scrape, ADOT, multi-cluster)
│
└── Sns/                            # Amazon SNS lab — own state; DEPLOYABLE (near-zero cost)
    ├── terraform/
    │   ├── main.tf, variables.tf, outputs.tf, providers.tf, backend.tf
    │   └── modules/
    │       ├── topics/           # standard + FIFO topics, KMS encryption, topic policy (+ TLS deny)
    │       ├── subscriptions/    # SQS subscribers w/ filter policies + DLQ redrive; Lambda subscriber
    │       └── delivery-policy/  # HTTP/S subscription retry/backoff policy + DLQ-depth CloudWatch alarm
    ├── src/
    │   └── subscriber/           # Lambda that logs received SNS messages + attributes
    │       └── handler.py
    └── docs/
        ├── sns-concepts.md       # concepts (topics, FIFO, security, filtering, DLQ, retries, metrics)
        └── sns-walkthrough.md    # hands-on (publish/filter routing, DLQ, retry policy, metrics)
```

Future phases add new sibling folders or new modules under an existing lab's
`terraform/modules/` (e.g., `cloudwatch-alarms/`, `cloudwatch-dashboard/`). Each lab keeps
its own Terraform state so labs can be deployed/destroyed independently.

---

## Training Phases

### Phase 1 — Understand AWS Metrics ✅ COMPLETE

**Goal:** answer *"What is happening to my system right now?"* using built-in AWS metrics.

**Steps (checkpoints):**

| # | Checkpoint                                    | Status      |
|---|-----------------------------------------------|-------------|
| 1 | Terraform scaffold (providers, variables, backend) | ✅ Done        |
| 2 | DynamoDB module (provisioned, low capacity)    | ✅ Done        |
| 3 | Orders Lambda module + handler code            | ✅ Done        |
| 4 | API Gateway REST API module                    | ✅ Done        |
| 5 | EventBridge + Processor Lambda module          | ✅ Done        |
| 6 | Deploy + traffic generation script             | ✅ Done        |
| 7 | Guided CloudWatch metrics exploration          | ✅ Done        |
| 8 | Concept checkpoint (metric / namespace / dimension / statistic) | ✅ Done        |

**Metrics to explore:**

- **Lambda:** Invocations, Errors, Duration, Throttles, ConcurrentExecutions
- **API Gateway:** Count, 4XXError, 5XXError, Latency, IntegrationLatency
- **DynamoDB:** ConsumedReadCapacityUnits, ConsumedWriteCapacityUnits, ThrottledRequests

**Traffic scenarios to generate:**

- ✅ Successful requests (happy path)
- ❌ Invalid requests → 4XX (bad payloads, missing fields)
- 💥 Application errors → 5XX (forced failures in Lambda)
- 🐌 Slow requests (artificial delays)

### CloudTrail — Governance, Audit & API Activity Logging ✅ BUILT (deploy pending)

**Goal:** create and manage trails; understand what CloudTrail records, how it
proves log integrity, where it stores logs, and how to analyze activity in
near-real-time.

**Location:** `Cloudtrail/` (own Terraform state, independent from the Cloudwatch lab).

**Decisions:** single account via `dev` SSO profile · `eu-central-1` · multi-region
trail · SSE-KMS · log file validation on · Insights on · data events scoped by ARN
(default to Phase 1 DynamoDB table + Lambda functions, empty until provided).

**Steps (checkpoints):**

| # | Checkpoint                                               | Status      |
|---|----------------------------------------------------------|-------------|
| 1 | Terraform scaffold (providers, variables, backend)        | ✅ Done        |
| 2 | `trail-s3` module (bucket + KMS + policies + lifecycle)    | ✅ Done        |
| 3 | `cloudtrail` module (multi-region, validation, selectors, Insights) | ✅ Done |
| 4 | `cloudtrail-cwlogs` module (log group + role + metric filter/alarm) | ✅ Done |
| 5 | Wire modules + `terraform validate`                       | ✅ Done        |
| 6 | `docs/cloudtrail-concepts.md` (concept reference)         | ✅ Done        |
| 7 | `docs/cloudtrail-walkthrough.md` (hands-on console + CLI) | ✅ Done        |
| 8 | Deploy + explore (validate-logs, Event History, Insights, CWL) | ⬜ Not started |

**Learning objectives covered:**

- Create trails + verify log files unmodified → `enable_log_file_validation`, digest files, `aws cloudtrail validate-logs`
- Monitor API calls / user activity across accounts → management events; org trails (concept doc)
- Management vs data events → advanced event selectors (data events ARN-scoped)
- Global vs regional trails → `is_multi_region_trail` + `include_global_service_events`
- S3 storage, retention, encryption → `trail-s3` module (SSE-KMS, lifecycle)
- CloudWatch Logs integration → `cloudtrail-cwlogs` module (near-real-time + alarm)
- Insights + event history → `insight_selector`, Event History console

### AWS Config — Configuration Tracking & Compliance ✅ BUILT (deploy pending)

**Goal:** record resource configuration over time, evaluate it against rules for
compliance, and integrate services for automated evaluation and remediation.

**Location:** `Config/` (own Terraform state, independent from the other labs).

**Decisions:** single account via `dev` SSO profile · `eu-central-1` · record **all**
supported resource types (+ global) · recorder left **on** (cleanup note in walkthrough) ·
managed rules `S3_BUCKET_SERVER_SIDE_ENCRYPTION_ENABLED` + `REQUIRED_TAGS` · one **custom
Lambda** rule (dummy S3 naming check) · **automatic remediation** on the SSE rule via SSM
Automation `AWS-EnableS3BucketEncryption`.

**Steps (checkpoints):**

| # | Checkpoint                                               | Status      |
|---|----------------------------------------------------------|-------------|
| 1 | Terraform scaffold (providers, variables, backend)        | ✅ Done        |
| 2 | `config-recorder` module (S3 + IAM role + recorder + delivery channel + status) | ✅ Done |
| 3 | `config-rules` module (SSE + required-tags managed, custom Lambda rule) | ✅ Done |
| 4 | `config-remediation` module (SSM Automation on the SSE rule) | ✅ Done |
| 5 | Wire modules + `terraform validate`                       | ✅ Done        |
| 6 | `docs/config-concepts.md` (concept reference)             | ✅ Done        |
| 7 | `docs/config-walkthrough.md` (hands-on console + CLI)     | ✅ Done        |
| 8 | Deploy + explore (timeline, compliance, trigger rules, watch remediation) | ⬜ Not started |

**Learning objectives covered:**

- Recorder, configuration items, rules, change history → `config-recorder` + `config-rules` modules; resource timeline in walkthrough
- Track config changes + historical resource config → configuration items, `get-resource-config-history`, resource timeline
- Integrate for compliance / evaluations / automation / remediation → custom Lambda rule (`PutEvaluations`), SSM Automation remediation, EventBridge pattern (concept)

### AWS X-Ray — Distributed Tracing ✅ BUILT (deploy pending)

**Goal:** trace requests across the distributed app, read service maps, find
bottlenecks, distinguish errors/faults, and understand async trace propagation.

**Location:** extends the **Cloudwatch** lab (instruments the Phase 1 app) — no separate
Terraform state. Changes live in the `api-gateway`, `lambda-orders`, `lambda-processor`
modules + both handlers.

**Decisions:** Option A (instrument Phase 1 app) · both tracing levels (active tracing +
`aws-xray-sdk` subsegments) · manual trace propagation across the EventBridge hop ·
`aws-xray-sdk` for code (ADOT covered in concepts doc) · deps vendored via `null_resource`.

**Steps (checkpoints):**

| # | Checkpoint                                               | Status      |
|---|----------------------------------------------------------|-------------|
| 1 | Infra + packaging (active tracing, X-Ray IAM, dep vendoring) | ✅ Done    |
| 2 | Handler instrumentation (`patch_all`, subsegments, trace propagation) | ✅ Done |
| 3 | `docs/xray-concepts.md` (concept reference)              | ✅ Done        |
| 4 | `docs/xray-walkthrough.md` (hands-on console + CLI)      | ✅ Done        |
| 5 | Deploy + explore (trace map, bottleneck, fault/error, Insights) | ⬜ Not started |

**Learning objectives covered:**

- Monitor/debug distributed apps → end-to-end traces across API GW → Lambda → DynamoDB → EventBridge → Lambda
- Request tracing → active tracing + SDK instrumentation; trace header propagation
- Identify bottlenecks → trace timeline + subsegment durations (the `slow` path as worked example)
- Service maps, error/fault tracking, anomaly detection → trace map, 4xx/5xx/429 distinction, X-Ray Insights
- Integrate with other AWS services → API GW active tracing, Lambda active tracing, boto3 auto-instrumentation; ADOT (concept)

### Amazon EventBridge — Event Routing & Auto-Healing ✅ BUILT (deploy pending)

**Goal:** route/filter events with patterns, respond to AWS service changes, integrate
CloudWatch alarms, auto-heal via SSM Automation, forward events across Regions, and
troubleshoot workflows.

**Location:** `Eventbridge/` (own Terraform state; uses a second provider alias for
`eu-west-1`).

**Decisions:** single account via `dev` SSO profile · primary `eu-central-1` + secondary
`eu-west-1` · auto-heal target = EC2 `t3.micro` restarted via SSM `AWS-RestartEC2Instance`
· API destinations covered **concept-only** · cross-Region hands-on, cross-account conceptual.

**Steps (checkpoints):**

| # | Checkpoint                                               | Status      |
|---|----------------------------------------------------------|-------------|
| 1 | Terraform scaffold (dual-region providers, variables, backend) | ✅ Done |
| 2 | `demo-target` module (EC2 + SNS + log-target Lambda)      | ✅ Done        |
| 3 | `rules-patterns` module (exact/prefix/anything-but/numeric/exists + AWS-event rule) | ✅ Done |
| 4 | `autoheal-ssm` module (EC2 state-change → SSM restart, two roles, DLQ, retry) | ✅ Done |
| 5 | `alarm-to-eventbridge` module (CloudWatch alarm state change → SSM) | ✅ Done |
| 6 | `cross-region` module (eu-central-1 bus → eu-west-1 bus) | ✅ Done        |
| 7 | Wire modules + `terraform validate`                      | ✅ Done        |
| 8 | `docs/eventbridge-concepts.md` (concept reference)       | ✅ Done        |
| 9 | `docs/eventbridge-walkthrough.md` (hands-on console + CLI) | ✅ Done        |
| 10 | Deploy + explore (patterns, auto-heal ×2, cross-Region)  | ⬜ Not started |

**Learning objectives covered:**

- Rules for AWS service changes + CloudWatch alarm integration → direct `aws.ec2` rule + alarm-state-change rule, both → SSM
- Trigger SSM Automation for auto-healing → `autoheal-ssm` (EventBridge-invoke role + AutomationAssumeRole + DLQ)
- Pattern matching to filter events → `rules-patterns` (exact/prefix/anything-but/numeric/exists)
- Route to targets + API destinations to external systems → multiple target types; API destinations concept-only (concepts §8)
- Event buses forwarding across accounts/Regions → `cross-region` (hands-on cross-Region; cross-account in concepts §7)
- Troubleshoot + monitor workflows → DLQ, retry policy, `AWS/Events` metrics, EventBridge Sandbox (concepts/walkthrough §6/§9)

### AWS Security Hub — Posture Management & Finding Aggregation ✅ BUILT (reference, not deployed)

**Goal:** understand Security Hub as the aggregation + compliance-standards layer; how to
configure it (account + org), export findings, automate response, prioritize by severity,
and spot trends with Insights.

**Location:** `Securityhub/` (own Terraform state). **This lab is REFERENCE CODE —
validated, intentionally NOT deployed by default** (Security Hub + GuardDuty incur cost and
change account posture). Priority is concepts + how pieces fit; TF is for study/future use.

**Decisions:** single account `dev` · `eu-central-1` · FSBP + CIS standards · GuardDuty as a
finding source (reference) · findings export via EventBridge → **Firehose** → S3 (Lambda
alternative commented) · incident response via EventBridge → **Lambda** (SSM commented) ·
org-level shown as code + conceptual.

**Steps (checkpoints):**

| # | Checkpoint                                               | Status      |
|---|----------------------------------------------------------|-------------|
| 1 | Terraform scaffold (providers, variables, backend)        | ✅ Done        |
| 2 | `securityhub-core` (enable + FSBP/CIS + GuardDuty + aggregator; org commented) | ✅ Done |
| 3 | `findings-export` (EventBridge → Firehose → S3; Lambda commented) | ✅ Done |
| 4 | `finding-response` (EventBridge HIGH/CRITICAL → Lambda; SSM commented) | ✅ Done |
| 5 | Wire modules + `terraform validate`                      | ✅ Done        |
| 6 | `docs/securityhub-concepts.md` (concept reference)       | ✅ Done        |
| 7 | `docs/securityhub-walkthrough.md` (reference / "if deployed") | ✅ Done   |

(No deploy checkpoint — reference lab by design. The walkthrough doubles as a study aid.)

**Learning objectives covered:**

- Configure/integrate at account + org level → `securityhub-core`; org via delegated admin + central configuration (concepts §5)
- Standards, automated checks, export to S3, Audit Manager → FSBP/CIS; `findings-export` to S3; Audit Manager (concepts §6)
- Integrate with AWS + third-party services → GuardDuty source + product subscriptions (concepts §6)
- Automate incident response → `finding-response` (EventBridge → Lambda/SSM; automation rules, custom actions)
- Severity, prioritization, Insights → Severity.Label/Normalized + Criticality; Insights for trends (concepts §3/§4)

### AWS Systems Manager — Node Management & Operations ✅ BUILT (deploy pending)

**Goal:** manage nodes with SSM — agents, Session Manager, Patch Manager, Run Command,
hybrid activation, Inventory, and Automation documents triggered by EventBridge.

**Location:** `Systemsmanager/` (own Terraform state). **Deployable lab** — one `t3.micro`
managed node + the SSM features. Hybrid activation is reference-only (needs an external box).

**Decisions:** single account `dev` · `eu-central-1` · fresh `t3.micro` node · Session
Manager logging to **both S3 + CloudWatch** · Patch Manager **scan-only** (install
commented) · custom Automation doc + EventBridge trigger · hybrid activation reference-only.

**Steps (checkpoints):**

| # | Checkpoint                                               | Status      |
|---|----------------------------------------------------------|-------------|
| 1 | Terraform scaffold (providers, variables, backend)        | ✅ Done        |
| 2 | `managed-instance` (EC2 + agent + profile; hybrid activation commented) | ✅ Done |
| 3 | `session-manager` (logging to S3 + CloudWatch via SSM-SessionManagerRunShell) | ✅ Done |
| 4 | `patch-manager` (baseline + patch group + maintenance window, Scan) | ✅ Done |
| 5 | `run-and-inventory` (Run Command + Inventory associations) | ✅ Done        |
| 6 | `automation-eventbridge` (custom Automation doc + EventBridge trigger) | ✅ Done |
| 7 | Wire modules + `terraform validate`                      | ✅ Done        |
| 8 | `docs/ssm-concepts.md` (concept reference)               | ✅ Done        |
| 9 | `docs/ssm-walkthrough.md` (hands-on console + CLI)       | ✅ Done        |
| 10 | Deploy + explore (Session Manager, Run Command, Patch scan, Inventory, Automation) | ⬜ Not started |

**Learning objectives covered:**

- Configure/install agents → `managed-instance` (SSM Agent + `AmazonSSMManagedInstanceCore`)
- Session Manager for secure remote access → `session-manager` (no inbound ports; S3 + CWL logging)
- Patch Manager → `patch-manager` (baseline + Patch Group tag + maintenance window, Scan)
- Run Command → `run-and-inventory` (AWS-RunShellScript association + ad-hoc in walkthrough)
- Hybrid activation → reference block in `managed-instance` (`i-` vs `mi-`; concepts §5)
- Inventory → `run-and-inventory` (AWS-GatherSoftwareInventory; Resource Data Sync concept)
- Automation docs + EventBridge trigger → `automation-eventbridge` (schemaVersion 0.3, two-role pattern)

### Amazon Managed Grafana + Amazon Managed Prometheus ✅ BUILT (deploy pending)

**Goal:** manage a Grafana workspace, integrate CloudWatch/X-Ray/AMP data sources with SSO
auth, manage users/permissions, optimize + run queries, build dynamic dashboards; and with
AMP: ingest via remote write (SigV4), alert → SNS, PromQL, and the Kubernetes/multi-cluster
collection story.

**Location:** `Grafana/` (own state). **Deployable** — AMG + AMP workspaces. Prereq: **IAM
Identity Center enabled** (for AMG login). EKS/Kubernetes collection is **reference-only**
(`docs/eks-prometheus-reference/`) — no EKS cluster provisioned.

**Decisions:** single account `dev` · `eu-central-1` · AMG auth = **IAM Identity Center** ·
data sources CloudWatch + X-Ray + **AMP** · AMP alert manager → **SNS** (all deployable) ·
EKS/remote-write/multi-cluster = reference snippets · dashboards built in console.

**Steps (checkpoints):**

| # | Checkpoint                                               | Status      |
|---|----------------------------------------------------------|-------------|
| 1 | Terraform scaffold (providers, variables, backend)        | ✅ Done        |
| 2 | `prometheus-workspace` (AMP + recording/alert rules + alert manager → SNS) | ✅ Done |
| 3 | `grafana-workspace` (AMG + IAM role + CloudWatch/X-Ray/AMP sources + SSO) | ✅ Done |
| 4 | Wire modules + `terraform validate`                      | ✅ Done        |
| 5 | `docs/grafana-concepts.md`                               | ✅ Done        |
| 6 | `docs/prometheus-concepts.md`                            | ✅ Done        |
| 7 | `docs/prometheus-promql.md` (PromQL reference)           | ✅ Done        |
| 8 | `docs/eks-prometheus-reference/` (K8s remote-write snippets) | ✅ Done     |
| 9 | `docs/grafana-walkthrough.md` (hands-on console + CLI)   | ✅ Done        |
| 10 | Deploy + explore (assign SSO user, data sources, query editor, dashboard, AMP alert) | ⬜ Not started |

**Learning objectives covered:**

Grafana — workspace mgmt, CloudWatch/X-Ray/AMP integration + SSO auth, Admin/Editor/Viewer
users, query optimization, query editor, template-variable dashboards, third-party sources
(all in `grafana-concepts.md` + modules).

Prometheus — AMP config/secure access (SigV4), AMG integration, exporters + Prometheus
server for K8s (reference), container remote write (reference), **PromQL** (own doc),
multi-cluster/hybrid (reference), alerts → SNS → remediation.

### Amazon SNS — Pub/Sub, Filtering, DLQs & Delivery ← CURRENT PHASE

**Goal:** configure/manage topics, secure them, integrate for event-driven notifications,
filter with message attributes, capture failed deliveries in SQS DLQs, and tune
retries/backoff + monitor DLQ metrics.

**Location:** `Sns/` (own state). **Deployable** — near-zero cost (SNS/SQS/Lambda/KMS).

**Decisions:** single account `dev` · `eu-central-1` · standard + FIFO topics · KMS +
topic policy + HTTPS-deny · two SQS subscribers with filter policies + one Lambda · SQS
DLQ (redrive) · HTTP/S retry/backoff demo against a placeholder URL · DLQ-depth alarm.

**Steps (checkpoints):**

| # | Checkpoint                                               | Status      |
|---|----------------------------------------------------------|-------------|
| 1 | Terraform scaffold (providers, variables, backend)        | ✅ Done        |
| 2 | `topics` (standard + FIFO, KMS, topic policy + TLS deny)  | ✅ Done        |
| 3 | `subscriptions` (SQS filter policies + DLQ redrive, Lambda) | ✅ Done     |
| 4 | `delivery-policy` (HTTP/S retry/backoff + DLQ-depth alarm) | ✅ Done       |
| 5 | Wire modules + `terraform validate`                      | ✅ Done        |
| 6 | `docs/sns-concepts.md`                                   | ✅ Done        |
| 7 | `docs/sns-walkthrough.md`                                | ✅ Done        |
| 8 | Deploy + explore (publish/filter, DLQ, retry policy, metrics) | ⬜ Not started |

**Learning objectives covered:**

- Configure/manage topics → `topics` (standard + FIFO)
- Integrate for notifications + secure topics/messages → service publishers; KMS + topic policy + TLS deny
- Message filtering + attributes → `subscriptions` filter policies on `category`/`severity`
- SNS DLQ via SQS → `subscriptions` redrive policy → SQS DLQ (per-subscription)
- Monitor DLQ + retries/backoff → `delivery-policy` HTTP/S `healthyRetryPolicy` + DLQ-depth alarm; SNS failed/redrive metrics

### Phase 2 — Custom Metrics & Structured Logging (planned)

---

## How to Resume Mid-Session

If this project is picked up by a new LLM session:

1. **Read this README first** — it holds all architectural decisions and the current state
   of every lab.
2. **Find the current lab** — look for the phase/section marked `← CURRENT PHASE`, then read
   its checkpoint table to see the first `⬜ Not started` checkpoint.
3. **Check which files exist** — compare the Repository Structure section against the actual
   files to confirm what's built vs. pending (checkpoint tables and files should agree).
4. **Read the relevant lab docs** before continuing:
   - Cloudwatch lab: `Cloudwatch/docs/phase-1-notes.md` (learner's concept answers — all
     passed) and `Cloudwatch/docs/phase-1-checkpoint-7-metrics-exploration.md` (metrics tour).
   - CloudTrail lab: `Cloudtrail/docs/cloudtrail-concepts.md` (concept reference) and
     `Cloudtrail/docs/cloudtrail-walkthrough.md` (hands-on deploy/explore tutorial).
   - Config lab: `Config/docs/config-concepts.md` (concept reference) and
     `Config/docs/config-walkthrough.md` (hands-on deploy/explore/remediate tutorial).
   - X-Ray (extends Cloudwatch lab): `Cloudwatch/docs/xray-concepts.md` (concept reference)
     and `Cloudwatch/docs/xray-walkthrough.md` (hands-on trace map / bottleneck tutorial).
   - EventBridge lab: `Eventbridge/docs/eventbridge-concepts.md` (concept reference) and
     `Eventbridge/docs/eventbridge-walkthrough.md` (hands-on patterns / auto-heal / cross-Region).
   - Security Hub lab: `Securityhub/docs/securityhub-concepts.md` (concept reference) and
     `Securityhub/docs/securityhub-walkthrough.md` (reference / "if deployed" tour).
   - Systems Manager lab: `Systemsmanager/docs/ssm-concepts.md` (concept reference) and
     `Systemsmanager/docs/ssm-walkthrough.md` (hands-on Session Manager / Patch / Run / Automation).
   - Grafana + Prometheus lab: `Grafana/docs/grafana-concepts.md`, `prometheus-concepts.md`,
     `prometheus-promql.md`, `grafana-walkthrough.md`, and `eks-prometheus-reference/` (K8s snippets).
   - SNS lab: `Sns/docs/sns-concepts.md` (concept reference) and
     `Sns/docs/sns-walkthrough.md` (hands-on publish/filter/DLQ/retry/metrics).
5. **Continue from the first `⬜` checkpoint** — each step is self-contained and the learner
   expects an explanation first, then waits for approval before any code is written.

### Current state (snapshot)

- **Cloudwatch lab (Phase 1):** ✅ complete. Infra validated and previously deployed; the
  learner has since **destroyed** it (can redeploy from `Cloudwatch/terraform`). Concept
  checkpoint passed.
- **CloudTrail lab:** Terraform (CP1–5) and both docs (CP6–7) ✅ done and `terraform
  validate`-clean, but **not yet applied**. Remaining: **CP8 — deploy + explore**.
- **Config lab:** Terraform (CP1–5) and both docs (CP6–7) ✅ done, `terraform
  validate`-clean. Learner has **deployed + explored** it. Recorder may still be running —
  `terraform destroy` to stop charges when done.
- **X-Ray (extends Cloudwatch lab):** infra + handler instrumentation (CP1–2) and both docs
  (CP3–4) ✅ done, `terraform validate`-clean, **not yet applied**. Remaining: **CP5 — deploy
  + explore** (redeploy the Cloudwatch lab, which now includes X-Ray). Requires `pip` on PATH.
- **EventBridge lab:** all six modules (CP1–7) and both docs (CP8–9) ✅ done,
  `terraform validate`-clean, **not yet applied**. Remaining: **CP10 — deploy + explore**.
  Dual-region (`eu-central-1` + `eu-west-1`); the EC2 `t3.micro` is the only always-on cost.
- **Security Hub lab:** all three modules (CP1–5) and both docs (CP6–7) ✅ done,
  `terraform validate`-clean. **Reference lab — NOT meant to be applied** (cost + posture).
  No deploy checkpoint. If applied, enable the Config lab first (controls ≈ Config rules).
- **Systems Manager lab:** all six modules (CP1–7) and both docs (CP8–9) ✅ done,
  `terraform validate`-clean, **not yet applied**. Remaining: **CP10 — deploy + explore**.
  Deployable (one `t3.micro`); needs the Session Manager plugin locally for `start-session`.
- **Grafana + Prometheus lab:** both modules (CP1–4) and all five docs (CP5–9) ✅ done,
  `terraform validate`-clean, **not yet applied**. Remaining: **CP10 — deploy + explore**.
  Deployable (AMG + AMP). **Prereq: IAM Identity Center enabled**. EKS/K8s = reference-only.
- **SNS lab (CURRENT):** all three modules (CP1–5) and both docs (CP6–7) ✅ done and
  `terraform validate`-clean, but **not yet applied**. Remaining: **CP8 — deploy + explore**
  (publish/filter routing, DLQ, retry policy, metrics) via `sns-walkthrough.md`. Deployable,
  near-zero cost. The HTTP/S subscription stays "pending confirmation" (placeholder URL) —
  expected, and useful for showing the delivery policy.
- No lab is guaranteed currently deployed — confirm with `terraform output` before assuming
  live resources.

### Working Style

- **Explain first, then implement.** Each checkpoint is presented as an explanation, the
  learner approves, then code is written.
- **One checkpoint at a time.** Never skip ahead.
- **Terraform modules are independent.** Each module has its own `main.tf`, `variables.tf`,
  and `outputs.tf`.
- **Emphasize "why" over "how."** The learner is studying for a certification — tie every
  resource and configuration choice back to what CloudOps expects them to know.

---

## Prerequisites

- AWS CLI configured with SSO (`aws sso login`)
- Terraform ≥ 1.5
- Python 3.12 (for Lambda code)
- `curl` or similar tool for API testing
- AWS account with permissions for: Lambda, API Gateway, DynamoDB, EventBridge, CloudWatch, IAM

---

## Quick Commands (once deployed)

### Cloudwatch lab

```bash
# Initialize Terraform
cd Cloudwatch/terraform && terraform init

# Plan
terraform plan

# Apply
terraform apply

# Get the API URL
terraform output api_url

# Invoke the API (happy path)
curl -X POST $(terraform output -raw api_url)/orders \
  -H "Content-Type: application/json" \
  -H "x-api-key: manolis-cloudops-lab-key" \
  -d '{"item": "widget", "quantity": 1}'

# Generate a full mix of traffic (happy / 4XX / 5XX / slow / processor-fail / no-key)
./Cloudwatch/scripts/generate-traffic.sh

# Destroy when done
terraform destroy
```

### CloudTrail lab

```bash
aws sso login --profile dev
cd Cloudtrail/terraform && terraform init
terraform apply

# Confirm the trail is actually logging (created ≠ logging)
aws cloudtrail get-trail-status --name $(terraform output -raw trail_name) \
  --query '{IsLogging:IsLogging, LatestDeliveryError:LatestDeliveryError}'

# Verify log file integrity (run ~1h after apply so a digest exists)
aws cloudtrail validate-logs \
  --trail-arn $(aws cloudtrail get-trail --name $(terraform output -raw trail_name) --query 'Trail.TrailARN' --output text) \
  --start-time "$(date -u -v-2H '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date -u -d '2 hours ago' '+%Y-%m-%dT%H:%M:%SZ')" \
  --verbose

# Full hands-on steps: Cloudtrail/docs/cloudtrail-walkthrough.md

# Destroy when done
terraform destroy
```

### Config lab

```bash
aws sso login --profile dev
cd Config/terraform && terraform init
terraform apply

# Confirm the recorder is actually recording (exists ≠ recording)
aws configservice describe-configuration-recorder-status \
  --query 'ConfigurationRecordersStatus[0].{recording:recording, lastStatus:lastStatus}'

# Force a rule to re-evaluate now (instead of waiting for next change/periodic run)
aws configservice start-config-rules-evaluation \
  --config-rule-names cloudops-config-dev-s3-sse-enabled

# Full hands-on steps (trigger rules, watch auto-remediation): Config/docs/config-walkthrough.md

# Destroy when done (remove demo buckets first)
terraform destroy
```

### EventBridge lab

```bash
aws sso login --profile dev
cd Eventbridge/terraform && terraform init
terraform apply

# Send a custom event and see which pattern rules match (read log-target logs)
aws events put-events --entries '[{
  "Source":"myapp.orders","DetailType":"OrderPlaced","EventBusName":"cloudops-eb-dev-demo-bus",
  "Detail":"{\"region\":\"eu-central-1\",\"amount\":150,\"errorCode\":\"E42\"}"
}]'
aws logs tail /aws/lambda/cloudops-eb-dev-log-target --since 5m

# Test the alarm-driven auto-heal without a real fault
aws cloudwatch set-alarm-state --alarm-name cloudops-eb-dev-instance-status-check \
  --state-value ALARM --state-reason "test"

# Full hands-on steps: Eventbridge/docs/eventbridge-walkthrough.md

# Destroy when done
terraform destroy
```

### Systems Manager lab

```bash
aws sso login --profile dev
brew install --cask session-manager-plugin   # one-time, for start-session
cd Systemsmanager/terraform && terraform init && terraform apply

INSTANCE=$(terraform output -raw instance_id)

# Confirm the node is managed
aws ssm describe-instance-information \
  --query "InstanceInformationList[?InstanceId=='$INSTANCE'].{id:InstanceId,ping:PingStatus}"

# Open a shell with NO inbound ports / no SSH keys
aws ssm start-session --target "$INSTANCE"

# Trigger a read-only patch scan
aws ssm send-command --document-name "AWS-RunPatchBaseline" \
  --targets "Key=InstanceIds,Values=$INSTANCE" --parameters 'Operation=Scan'

# Full hands-on steps: Systemsmanager/docs/ssm-walkthrough.md

# Destroy when done
terraform destroy
```

### Grafana + Prometheus lab (needs IAM Identity Center enabled)

```bash
aws sso login --profile dev
cd Grafana/terraform && terraform init && terraform apply
terraform output   # amp_workspace_id, amp_remote_write_url, grafana_workspace_endpoint

# Then in the console: Amazon Managed Grafana → workspace → Authentication →
#   assign your Identity Center user as ADMIN → open the workspace URL → sign in via SSO.
# Add the AMP data source (Prometheus, SigV4, region eu-central-1), build panels/dashboards.

# Full hands-on steps: Grafana/docs/grafana-walkthrough.md

# Destroy when done
terraform destroy
```

### SNS lab

```bash
aws sso login --profile dev
cd Sns/terraform && terraform init && terraform apply
TOPIC=$(terraform output -raw standard_topic_arn)

# Publish with a message attribute → watch filter routing to the matching queue
aws sns publish --topic-arn "$TOPIC" --message '{"id":1}' \
  --message-attributes '{"category":{"DataType":"String","StringValue":"orders"}}'
aws sqs receive-message --queue-url "$(terraform output -raw orders_queue_url)" \
  --max-number-of-messages 10 --query 'Messages[].Body' --output text

# Full hands-on steps: Sns/docs/sns-walkthrough.md

# Destroy when done
terraform destroy
```
