# AWS Security Hub — Concept Reference (CloudOps Exam Prep)

> Reference for the *conceptual* half of the Security Hub objectives. This lab's Terraform
> is **reference code** (`Securityhub/terraform/`) — validated, not deployed. The doc is
> framed to teach *what Security Hub is and when to use each piece*.
>
> **Naming note (current):** AWS now calls the posture-management service **Security Hub
> CSPM** (Cloud Security Posture Management). Older docs/exam items say just "Security Hub."
> They refer to the same core service described here. Content rephrased from AWS docs for
> licensing compliance.

---

## 0. What Security Hub is

Security Hub is the **aggregation + posture-management layer** for AWS security. It:
1. **Ingests findings** from many sources (AWS services + third-party products) in one
   normalized format (**ASFF**).
2. **Runs compliance standards** (sets of automated controls) and produces a **security
   score**.
3. **Routes findings** onward (EventBridge) for export, ticketing, and **automated response**.

It is a **single pane of glass** — it mostly doesn't *detect* things itself; it
**consolidates** what other services detect and measures you against best-practice standards.

```
GuardDuty, Inspector, Macie, IAM Access Analyzer, Config, 3rd-party
        \         |          |            /
         ▼        ▼          ▼           ▼
            Security Hub (ASFF, standards, score)
                        │
                        ▼ EventBridge
          export to S3 · ticketing · automated response
```

> 📌 **Exam framing:** GuardDuty = threat *detection*; Inspector = *vulnerability* scanning;
> Macie = *sensitive data* discovery; Config = *configuration compliance*. **Security Hub =
> aggregates all their findings + runs standards.** Don't confuse the aggregator with the
> detectors.

---

## 1. ASFF — the AWS Security Finding Format

Every finding, whatever its source, is normalized to **ASFF** — a standard JSON schema. That
normalization is what lets Security Hub aggregate GuardDuty, Inspector, Config, and partner
findings in one place and filter/insight across them uniformly.

Key ASFF fields you'll reason about: `Title`, `ProductName`, `Severity` (`Label` +
`Normalized`), `Resources[]`, `Compliance.Status`, `Workflow.Status`, `RecordState`.

---

## 2. Standards & controls

- A **control** = one automated check (e.g. "S3 Block Public Access enabled").
- A **standard** = a curated, versioned set of controls, producing a **score** (% passing).
- Most controls are implemented as **AWS Config rules** → **Config's recorder must be ON**
  for accurate results. (Security Hub can create a *service-linked Config recorder* for
  posture data in newer setups, but the Config dependency is the core relationship.)

Standards available (recognize all; we enabled the first two):
| Standard | Author | Scope |
|---|---|---|
| **AWS FSBP** (Foundational Security Best Practices) | AWS | broadest; many services |
| **CIS AWS Foundations Benchmark** | Center for Internet Security | account hygiene (IAM, logging, monitoring); versioned (v1.2.0, v1.4.0, v3.0.0) |
| **PCI DSS** | PCI Council | payment-card compliance |
| **NIST SP 800-53** | NIST | US federal controls |

> 📌 **Exam angle:** controls ≈ **Config rules** → enable Config. FSBP = AWS's broad
> baseline; CIS = third-party, audit-oriented, **versioned**. The standard ARN format
> differs per standard (FSBP region ARN vs CIS v1.2.0 global ruleset ARN) — a real gotcha.

### Consolidated control findings
A setting where a control shared across standards produces **one** finding referencing the
**security control ID** (e.g. `S3.1`) instead of a separate finding per standard. Reduces
noise. Modern default.

---

## 3. Finding severity & prioritization

ASFF `Severity` has two parts:
- **`Label`** — one of **INFORMATIONAL · LOW · MEDIUM · HIGH · CRITICAL**.
- **`Normalized`** — a number **0–100** (higher = worse). Label and Normalized map to each
  other; providing one auto-populates the other.

AWS's severity guidance (worth knowing):
- **INFORMATIONAL** — passed check / informational (no issue).
- **LOW** — could enable a *future* compromise (weak config, exposure).
- **MEDIUM** — active compromise, objective not yet achieved (suspicious activity).
- **HIGH / CRITICAL** — adversary achieved objective (data loss, DoS).

**Severity ≠ Criticality.** `Severity` = how bad the *finding* is. **`Criticality`** (0–99)
= how important the *resource* is (prod vs test). Prioritize using **both** — a HIGH finding
on a mission-critical resource outranks a HIGH on a sandbox.

> 📌 **Exam angle:** prioritize by **Severity.Label/Normalized** combined with resource
> **Criticality**. Know the five labels and the 0–100 normalized range. "Be conservative
> assigning HIGH/CRITICAL" is AWS's own guidance to keep the to-do list meaningful.

---

## 4. Insights — identifying trends

A **Security Hub Insight** is a **saved grouping/filter of findings** that surfaces a trend
or a "these need attention" collection — e.g. "S3 buckets with public access findings,"
"resources with the most findings," "findings by severity over time."

- **Managed insights** — AWS-provided, cover common questions out of the box.
- **Custom insights** — you define the group-by (e.g. by `ResourceId`, `AwsAccountId`,
  `ProductName`) and filters.

> 📌 **Exam angle:** Insights = **trend/aggregation views** to spot patterns and hotspots
> (which accounts/resources/control types dominate), not individual-finding triage. Use them
> to answer "where is my risk concentrated / is it getting better?"

---

## 5. Account-level vs Organization-level setup

### Account level (what our core module shows deployable)
- `aws_securityhub_account` enables it; subscribe standards; add a cross-Region
  **finding aggregator** so linked Regions roll up to a home Region.

### Organization level (reference / conceptual — needs AWS Organizations)
Two models — know both, especially the newer one:

1. **Delegated administrator + local config (older):** the Organizations management account
   designates a **delegated admin** (a security/audit account). That admin uses
   `auto_enable` / `auto_enable_standards` to turn Security Hub on for members. (Our TF
   shows this via `aws_securityhub_organization_admin_account` +
   `aws_securityhub_organization_configuration`.)

2. **Central configuration + configuration policies (newer, preferred):** the delegated
   admin creates **configuration policies** (which service/standards/controls are on) and
   **associates them to accounts, OUs, or the org root** — including future accounts —
   across Regions, from one place. This is the modern "manage the whole org's posture
   centrally" mechanism.

> 📌 **Exam angle:** org-wide, consistent, future-proof coverage = **delegated admin** +
> (preferably) **central configuration with configuration policies**. Mirrors org CloudTrail
> / org Config. Delegated admin is almost always a dedicated **security account**, not the
> management account.

---

## 6. Integrations

| Integrates with | Direction / purpose |
|---|---|
| **GuardDuty / Inspector / Macie / IAM Access Analyzer** | findings flow **into** Security Hub automatically once both are enabled |
| **AWS Config** | backs most controls; posture/compliance source |
| **EventBridge** | findings flow **out** → export, ticketing, automated response |
| **Audit Manager** | Security Hub findings/evidence feed **Audit Manager** assessments as automated evidence for frameworks (SOC 2, PCI, etc.) |
| **Third-party products** | subscribe via a **product subscription** (partner product ARN); partners send ASFF findings in |
| **Detective** | pivot from a finding to **Detective** for investigation |

> 📌 **Exam angle (Audit Manager):** Audit Manager **collects evidence** mapped to control
> frameworks; Security Hub is one of its automated **evidence sources**. "Continuously
> gather compliance evidence for an audit framework" → Audit Manager, fed by Security Hub +
> Config.

---

## 7. Exporting findings to S3

No native "export to S3" button. The recommended pipeline (our `findings-export` module):

```
Security Hub finding
  → EventBridge "Security Hub Findings - Imported" (default bus)
  → EventBridge rule
  → Kinesis Data Firehose (batch/buffer/compress)
  → S3 (date-partitioned)
```

- **Firehose** is preferred for volume: batching, buffering, retries, no code.
- A **Lambda** alternative works for low volume or per-finding transformation (shown
  commented in the module).

> 📌 **Exam angle:** Security Hub → **EventBridge** → (Firehose | Lambda) → **S3**. Firehose
> for scale; Lambda for custom transform. The event detail-type is **"Security Hub Findings
> - Imported."**

---

## 8. Automating incident response

Pattern (our `finding-response` module):
```
finding (filter by Severity.Label HIGH/CRITICAL)
  → EventBridge rule
  → Lambda  (custom action)  OR  SSM Automation runbook  (known fix)
```

Complementary Security Hub mechanisms:
- **Automation rules** — in Security Hub itself, auto-update/suppress/triage findings on
  ingest (e.g. raise severity for a prod OU, auto-suppress a known-accepted finding).
- **Custom actions** — a named action a human triggers from the console that emits an
  EventBridge event (human-in-the-loop response).
- **Finding workflow status** — `NEW → NOTIFIED → SUPPRESSED → RESOLVED` to track handling.

> 📌 **Exam angle:** auto-response = **EventBridge rule on findings → Lambda/SSM**. Use
> **automation rules** for ingest-time triage/suppression, **custom actions** for
> human-initiated response. Filter on **Severity.Label** / `Normalized` to decide what
> warrants automation.

---

## Quick-recall cheat sheet

| Question | One-line answer |
|---|---|
| What does Security Hub actually do? | **Aggregates** findings (ASFF) + runs **standards** → score |
| Detector vs aggregator? | GuardDuty/Inspector/Macie detect; **Security Hub aggregates** |
| Controls are powered by…? | mostly **AWS Config rules** → Config recorder must be on |
| FSBP vs CIS? | FSBP = AWS broad baseline; CIS = 3rd-party, audit, versioned |
| Severity labels? | INFORMATIONAL/LOW/MEDIUM/HIGH/CRITICAL + Normalized 0–100 |
| Severity vs Criticality? | finding badness vs **resource** importance — prioritize with both |
| Spot trends/hotspots? | **Insights** (managed + custom) |
| Org-wide, future-proof setup? | delegated admin + **central configuration** (configuration policies) |
| Export findings to S3? | EventBridge → **Firehose** (or Lambda) → S3 |
| Automate response? | EventBridge rule on findings → **Lambda/SSM**; automation rules for triage |
| Evidence for an audit framework? | **Audit Manager**, fed by Security Hub + Config |
| Finding schema? | **ASFF** (AWS Security Finding Format) |
