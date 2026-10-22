# AWS Security Hub — Walkthrough (Reference / "If Deployed")

> Companion to `securityhub-concepts.md`. This lab's Terraform is **reference code — not
> intended to be applied by default** (Security Hub + GuardDuty incur cost and change your
> account's security posture). So this doc is framed as *"here's what you'd do and see"* —
> a console/CLI tour you can follow **if** you choose to deploy, and a study aid either way.
>
> **Region:** `eu-central-1` · **Profile:** `dev` · **Prefix:** `cloudops-sh-dev`
>
> **Doc currency:** verified against current AWS docs (Security Hub CSPM). Content rephrased
> for licensing compliance.

---

## 0. If you choose to deploy (and the cost reality)

```bash
aws sso login --profile dev
cd Securityhub/terraform
terraform init
terraform validate     # this is what we rely on — code is sound
# terraform apply      # ONLY if you accept the cost + posture change
```

> 💲 **Why it's not apply-by-default:** Security Hub bills per **finding ingested** and per
> **compliance check**; GuardDuty bills on analyzed events/logs. Standards start evaluating
> your whole account immediately. For a short, deliberate exploration it's modest — but it's
> not a leave-it-running lab. If you apply, **`terraform destroy`** when done.

> ⚠️ **Prerequisite for meaningful results:** enable **AWS Config** first (you have the
> Config lab). Most FSBP/CIS controls are Config rules — without the recorder, controls show
> as no-data.

---

## 1. Enable & standards (what the core module does)

On apply, `securityhub-core` would:
- Enable Security Hub (`aws_securityhub_account`).
- Subscribe **FSBP** + **CIS v1.2.0** standards.
- Create a cross-Region **finding aggregator** (home Region = `eu-central-1`).
- Enable **GuardDuty**, whose findings then flow into Security Hub automatically.

**Console tour (Security Hub):**
- **Summary** — overall security score + findings by severity.
- **Security standards** — each enabled standard with its **% passed** and a drill-down to
  per-control PASS/FAIL.
- **Integrations** — shows GuardDuty (and others) sending findings in; this is where you'd
  also subscribe third-party products.

**CLI spot-checks:**
```bash
aws securityhub get-enabled-standards \
  --query 'StandardsSubscriptions[].{arn:StandardsArn,status:StandardsStatus}'

aws securityhub describe-standards-controls \
  --standards-subscription-arn <fsbp-subscription-arn> \
  --query 'Controls[0:5].{id:ControlId,status:ControlStatus,severity:SeverityRating}'
```

> 📌 **Exam angle:** a freshly enabled standard takes time to evaluate; controls backed by
> Config need the recorder running. The **security score** is % of passed controls.

---

## 2. Findings — severity & prioritization

**Console:** **Findings** — the ASFF list. Sort/filter by **Severity**, **Workflow status**,
**Product**, **Resource**.

```bash
# Current HIGH/CRITICAL, active, new findings
aws securityhub get-findings \
  --filters '{
    "SeverityLabel":[{"Value":"CRITICAL","Comparison":"EQUALS"},{"Value":"HIGH","Comparison":"EQUALS"}],
    "WorkflowStatus":[{"Value":"NEW","Comparison":"EQUALS"}],
    "RecordState":[{"Value":"ACTIVE","Comparison":"EQUALS"}]
  }' \
  --query 'Findings[0:10].{sev:Severity.Label,title:Title,product:ProductName}'
```

Prioritization in practice: start with **CRITICAL/HIGH** (`Severity`), then weight by
resource **Criticality** (prod > test). Update handling with workflow status:

```bash
aws securityhub batch-update-findings \
  --finding-identifiers '[{"Id":"<finding-id>","ProductArn":"<product-arn>"}]' \
  --workflow '{"Status":"NOTIFIED"}'
```

> 📌 **Exam angle:** `Severity.Label` (5 levels) + `Normalized` (0–100); prioritize with
> resource `Criticality` too. Workflow status (`NEW→NOTIFIED→SUPPRESSED→RESOLVED`) tracks
> handling; set it via `BatchUpdateFindings`.

---

## 3. Insights — trends

**Console:** **Insights** — managed insights (e.g. "S3 buckets with public access",
"resources with the most findings") plus any **custom insights** you define (group findings
by a field + filters).

```bash
aws securityhub get-insights --max-results 5 \
  --query 'Insights[].{name:Name,groupBy:GroupByAttribute}'
```

> 📌 **Exam angle:** Insights answer "**where is risk concentrated / is it trending down?**"
> (by account, resource, control, product) — aggregation, not per-finding triage.

---

## 4. Export findings to S3 (what findings-export does)

Pipeline: finding → EventBridge (`Security Hub Findings - Imported`) → **Firehose** → **S3**
(`securityhub-findings/YYYY/MM/DD/`, GZIP). To verify after deploy:

```bash
aws s3 ls "s3://cloudops-sh-dev-findings-<account>/securityhub-findings/" --recursive | tail
```

Firehose batches (5 min / 5 MB here), so allow a few minutes before objects appear. The
commented **Lambda** alternative writes per-finding instead — use it for low volume or
custom transforms.

> 📌 **Exam angle:** detail-type is **"Security Hub Findings - Imported."** Firehose for
> scale; Lambda for transform. S3 is the durable archive for audit / Athena queries.

---

## 5. Automated incident response (what finding-response does)

Rule matches `Security Hub Findings - Imported` filtered to **HIGH/CRITICAL** →
responder **Lambda**. Observe after deploy:

```bash
aws logs tail /aws/lambda/cloudops-sh-dev-finding-response --since 15m
# look for: RESPOND severity=HIGH product=... title=... resources=[...]
```

To force a test finding without a real incident, import a custom ASFF finding:

```bash
aws securityhub batch-import-findings --findings '[{
  "SchemaVersion":"2018-10-08","Id":"test/1","ProductArn":"arn:aws:securityhub:eu-central-1:<account>:product/<account>/default",
  "GeneratorId":"test","AwsAccountId":"<account>","Types":["Software and Configuration Checks"],
  "CreatedAt":"2026-10-06T00:00:00Z","UpdatedAt":"2026-10-06T00:00:00Z",
  "Severity":{"Label":"CRITICAL"},"Title":"Test finding","Description":"manual test",
  "Resources":[{"Type":"Other","Id":"arn:aws:::test"}]
}]'
```

Complementary (console): **Automation rules** (ingest-time triage/suppress) and **Custom
actions** (human-triggered response emitting an EventBridge event).

> 📌 **Exam angle:** auto-response = **EventBridge rule on findings → Lambda/SSM**, filtered
> by severity. Automation rules triage at ingest; custom actions are human-in-the-loop. The
> commented SSM target in the module shows the known-runbook alternative.

---

## 6. Organization & Audit Manager (reference)

- **Org:** from the Organizations management account, designate a **delegated admin**
  (security account), then prefer **central configuration** — define **configuration
  policies** (service/standards/controls) and associate them to **accounts/OUs/root**,
  covering future accounts. Our TF shows the older `auto_enable` model (commented); central
  configuration is the modern approach.
- **Audit Manager:** map an assessment to a framework (e.g. CIS, SOC 2); Security Hub +
  Config become automated **evidence sources**, so control evidence is gathered
  continuously instead of manually.

> 📌 **Exam angle:** org-wide posture = delegated admin + **central configuration**.
> Continuous audit evidence = **Audit Manager** fed by Security Hub/Config.

---

## 7. Clean up (if you deployed)

```bash
cd Securityhub/terraform
terraform destroy
```

Also: disabling Security Hub stops standards evaluation; disabling GuardDuty stops its
charges. Member accounts must be disassociated before an admin disables (org case).

---

## Study checklist (deploy optional)

- [ ] Can explain Security Hub as **aggregator + standards**, vs detectors (GuardDuty/Inspector/Macie).
- [ ] Know FSBP vs CIS, and that controls ≈ Config rules (recorder must be on).
- [ ] Know the 5 severity labels + Normalized 0–100, and Severity vs Criticality.
- [ ] Can describe Insights (managed + custom) for trends.
- [ ] Can describe the S3 export pipeline (EventBridge → Firehose → S3).
- [ ] Can describe auto-response (EventBridge → Lambda/SSM) + automation rules + custom actions.
- [ ] Know org setup: delegated admin + central configuration (configuration policies).
- [ ] Know Audit Manager consumes Security Hub/Config as evidence.
