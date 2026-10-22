# AWS Config — Concept Reference (CloudOps Exam Prep)

> A revisitable reference for the *conceptual* half of the AWS Config objectives — the
> things you need to **explain**, not just click. Pair it with `config-walkthrough.md`
> for the hands-on part.
>
> This lab's Config setup is defined in `Config/terraform/`. References to "our module"
> point there.

---

## 0. What AWS Config is (and how it differs from CloudTrail)

AWS Config continuously **records the configuration of your AWS resources** and lets you
**evaluate that configuration against rules** for compliance. It answers:

- *"What does this resource's configuration look like **right now**?"*
- *"What did it look like **last Tuesday**, and **what changed** since?"*
- *"Which resources are **non-compliant** with my policies, and can I **auto-fix** them?"*

### Config vs CloudTrail vs CloudWatch (know this cold)

| Service | Core question | Unit of data |
|---|---|---|
| **CloudTrail** | *Who made which API call, when?* | an **event** (API activity) |
| **Config** | *What is this resource's configuration, and how did it change?* | a **configuration item** (resource state) |
| **CloudWatch** | *How is my system performing / is it healthy?* | a **metric / log** |

> 📌 **Exam framing:** "who deleted the security group?" → **CloudTrail**. "what did the
> security group's rules look like before it was changed, and is it compliant?" →
> **Config**. They're complementary: Config often shows the *what changed*, CloudTrail
> the *who did it* — and a Config configuration item links to the CloudTrail event.

---

## 1. The configuration recorder

The **configuration recorder** is the engine. It discovers your resources and records a
**configuration item** every time one is created, changed, or deleted.

Key facts:
- **One recorder per region per account** (for the standard recorder).
- It can record **all supported resource types** (our lab) or a **narrow list**.
- **Global resources** (IAM users, roles, policies) are special — you choose whether to
  include them (`include_global_resource_types`). To avoid duplicate recording, record
  globals in **one** region only when you have recorders in many regions.
- **A recorder that exists but is not STARTED records nothing.** Creating the recorder
  and *starting* it are two separate actions.

> 📌 **Exam trap:** "Config shows no data." First checks: is there a **recorder**, is it
> **started/recording**, and does the **delivery channel + S3 bucket policy** allow
> delivery? Our Terraform sets `aws_config_configuration_recorder_status { is_enabled =
> true }` precisely because the recorder is off until you flip it on.

---

## 2. Configuration items (CI) & the delivery channel

### Configuration item (CI)
A **point-in-time snapshot** of a resource, containing:
- The resource's **attributes/configuration** (e.g. a bucket's encryption settings).
- **Relationships** (e.g. "this ENI is attached to this instance").
- **Metadata** — capture time, a link to the related **CloudTrail event** that caused the
  change, and the CI's version.

A new CI is emitted on **every change** (and on the periodic snapshot schedule).

### Delivery channel
Defines **where** CIs and snapshots go: an **S3 bucket** (history + snapshots) and
optionally an **SNS topic** (notifications). `delivery_frequency` controls how often a
full **configuration snapshot** is written (our lab: every 24h).

> 📌 **Exam angle:** the **S3 bucket policy** must allow the Config service principal to
> `PutObject` under `AWSLogs/<acct>/Config/*` with `bucket-owner-full-control`. A wrong
> bucket policy is the #1 "delivery channel failed to create" cause.

---

## 3. Configuration history & snapshots

- **Configuration history** — the time-ordered series of CIs for a resource, delivered to
  S3 (and queryable via the API `GetResourceConfigHistory`). This is how you answer "what
  did it look like last week."
- **Configuration snapshot** — a point-in-time capture of **all** recorded resources at
  once, delivered on the `delivery_frequency` schedule or on demand.
- **Resource timeline** (console) — a visual history of a single resource: each change,
  what differed, and the linked CloudTrail event.

> 📌 **Exam angle:** "I need the state of all resources as of a date for an audit" →
> configuration **snapshot**. "I need the change history of **one** resource" →
> configuration **history** / resource **timeline**.

---

## 4. Config rules — evaluations & compliance

A **Config rule** evaluates CIs and marks each resource **COMPLIANT**, **NON_COMPLIANT**,
or **NOT_APPLICABLE**. Three rule source types:

| Source | What it is | Our lab |
|---|---|---|
| **AWS managed** | Prebuilt rules; reference by `sourceIdentifier` | `S3_BUCKET_SERVER_SIDE_ENCRYPTION_ENABLED`, `REQUIRED_TAGS` |
| **Custom Lambda** | Your Lambda returns the verdict via `PutEvaluations` | the `s3-naming-check` dummy rule |
| **Custom Policy** | Guard (policy-as-code), no Lambda needed | not used here |

### Trigger types
- **Configuration change** — re-evaluates when a matching resource changes (our custom
  rule, via `ConfigurationItemChangeNotification`).
- **Periodic** — re-evaluates on a schedule (e.g. every 24h), independent of changes.
- A rule can use one or both.

### How a custom Lambda rule integrates (exam favorite)
1. Config **invokes** your Lambda, passing the `invokingEvent` (the CI) + a `resultToken`.
   → requires an `aws_lambda_permission` allowing `config.amazonaws.com` to invoke.
2. Your Lambda decides COMPLIANT / NON_COMPLIANT / NOT_APPLICABLE.
3. Your Lambda calls **`config:PutEvaluations`** with the verdict + `resultToken`.
   → requires `config:PutEvaluations` in the Lambda's IAM policy.

> 📌 **Exam trap:** a custom rule stuck "evaluating" / no results → the Lambda usually
> lacks **`config:PutEvaluations`**, or Config lacks **permission to invoke** the Lambda.
> Both are in our `config-rules` module for a reason.

---

## 5. Remediation — automatic & manual

When a rule reports NON_COMPLIANT, Config can **remediate** via an **SSM Automation
document**:

- **Automatic** — runs on its own as soon as a resource is non-compliant (our lab, on the
  SSE rule).
- **Manual** — you click **Remediate** in the console for selected resources.

Mechanics:
- The SSM document runs under an **IAM role you supply** (`AutomationAssumeRole`) — that
  role, not Config, holds the permissions to perform the fix.
- Config maps the **non-compliant resource's ID** into the document's target parameter
  (our module: `BucketName` ← `RESOURCE_ID`).
- `MaximumAutomaticAttempts` + retry window prevent flapping/looping.

> 📌 **Exam angle:** automatic remediation is powerful but **risky** — a misfiring rule
> can change resources fleet-wide. Prefer **manual** in sensitive/prod contexts, or gate
> automatic remediation carefully. Know that remediation = **Config rule + SSM Automation
> document + an assume-role**.

> 📌 Our end-to-end demo: `s3-sse-enabled` rule finds an unencrypted bucket →
> `AWS-EnableS3BucketEncryption` SSM doc runs under the remediation role → bucket gets
> default encryption → rule re-evaluates → COMPLIANT.

---

## 6. Conformance packs (concept)

A **conformance pack** is a **collection of Config rules + remediations** packaged as a
single YAML template you deploy as one unit (and can deploy across an **organization**).
AWS ships sample packs mapped to frameworks (CIS, PCI DSS, NIST, S3 best practices, etc.).

> 📌 **Exam angle:** "deploy a consistent compliance baseline across many accounts in one
> step" → **conformance pack** (often via AWS Organizations). A single rule is one check;
> a conformance pack is a governed bundle.

---

## 7. Aggregators — multi-account, multi-region (concept)

A **configuration aggregator** collects Config data (compliance + CIs) from **multiple
accounts and regions** into a **single view** (in a designated aggregator account).

- Sources: specific accounts, or an entire **AWS Organization**.
- Read-only: you *view* compliance centrally; rules still run in each source account.

> 📌 **Exam angle:** "central dashboard of compliance across all accounts/regions" →
> **aggregator**. "enforce the same rules everywhere" → **conformance pack / org rules**.
> Aggregator = **see**; conformance pack / org rules = **enforce**.

---

## 8. Integrations (how Config connects to the rest)

| Integration | Purpose |
|---|---|
| **S3** | stores configuration history + snapshots (delivery channel) |
| **SNS** | streams configuration + compliance change notifications |
| **CloudTrail** | each CI links to the API event that caused the change |
| **Lambda** | backs **custom rules** (and can be a remediation target) |
| **SSM Automation** | performs **remediations** |
| **EventBridge** | Config compliance-change events → trigger workflows/alerts |
| **Security Hub** | consumes Config rule findings into a central security view |
| **Organizations** | org-wide rules, conformance packs, aggregators |

> 📌 **Exam angle:** "alert/kick off a workflow the moment a resource becomes
> non-compliant" → Config → **EventBridge** rule → target (SNS/Lambda/Step Functions).

---

## Quick-recall cheat sheet

| Question | One-line answer |
|---|---|
| Who made the change? | **CloudTrail** (Config tells you *what* changed, links to the event) |
| What did a resource look like last week? | Config **configuration history** / resource **timeline** |
| State of everything as of a date? | Config **configuration snapshot** |
| Config shows no data? | No/unstarted **recorder**, or **delivery channel / bucket policy** wrong |
| Is this resource compliant? | A **Config rule** → COMPLIANT / NON_COMPLIANT / NOT_APPLICABLE |
| Custom rule stuck evaluating? | Lambda missing **`config:PutEvaluations`**, or Config can't **invoke** it |
| Auto-fix a violation? | **Remediation** = Config rule + **SSM Automation** doc + assume-role |
| Risky part of auto-remediation? | Fleet-wide unwanted changes on a misfiring rule → prefer manual in prod |
| One-step compliance baseline across accounts? | **Conformance pack** (via Organizations) |
| Central multi-account compliance view? | **Aggregator** (see); conformance pack/org rules (enforce) |
| React instantly to non-compliance? | Config → **EventBridge** → SNS/Lambda/Step Functions |
| Change-triggered vs periodic rule? | change = on resource change; periodic = on schedule |
