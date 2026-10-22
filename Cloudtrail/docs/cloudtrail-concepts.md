# CloudTrail — Concept Reference (CloudOps Exam Prep)

> A revisitable reference for the *conceptual* half of the CloudTrail objectives —
> the things you need to be able to **explain**, not just click. Pair it with
> `cloudtrail-walkthrough.md` for the hands-on part.
>
> This lab's trail is defined in `Cloudtrail/terraform/`. References to "our module"
> point there.

---

## 0. What CloudTrail is (and is not)

CloudTrail is an **account-level, always-on recorder of API activity**. Nearly every
action in AWS — console click, CLI command, SDK call, or one service calling another —
is an API call, and CloudTrail captures *who did what, when, from where, and to which
resource*.

Two things it is **not**:

- **Not a performance monitor.** That's CloudWatch (metrics/logs). CloudTrail answers
  *"who called `TerminateInstances`?"*, not *"what's my CPU?"*.
- **Not something services "write to."** CloudTrail observes the control/data plane
  passively. The logged services need no permission and no role. Permissions only
  concern where CloudTrail *delivers* what it captured (see §7).

> 📌 **Exam framing:** CloudTrail = **audit / governance / compliance / security
> forensics**. CloudWatch = **operational health / performance**. Config = **resource
> configuration state over time**. Keep these three straight.

---

## 1. Event History vs a Trail

| | **Event History** | **A Trail** |
|---|---|---|
| Exists by default | Yes, always on | No — you create it |
| Retention | **90 days**, rolling | As long as you keep the S3 objects |
| Scope | **Management events only** | Management + data + Insights |
| Storage | Managed by CloudTrail (viewable in console/API) | **Your** S3 bucket (+ optional CWL) |
| Cost | Free | Mostly free; data events + Insights billed |

> 📌 **Exam trap:** "I need API activity from 6 months ago." Event History only goes
> back **90 days** — you need a **trail** delivering to S3 for anything longer. This is
> *the* reason to create a trail even though Event History is free.

---

## 2. Management events vs Data events

### Management events (control plane)
Operations that **manage** resources: `RunInstances`, `CreateBucket`, `AttachRolePolicy`,
`CreateTable`, console sign-in. These are the "who changed my account" events.

- Enabled by default on a trail.
- **First copy is free** per trail (a second trail copying the same management events
  is billed).
- Can be split into **Read** (e.g. `DescribeInstances`) and **Write** (e.g.
  `RunInstances`) — our module records **All**.

### Data events (data plane)
High-volume, **resource-data-level** operations: S3 `GetObject`/`PutObject`, DynamoDB
`PutItem`/`GetItem`, Lambda `Invoke`.

- **Off by default** — you opt in.
- **Billed per event** (~$0.10 per 100k) and can be *very* high volume.
- **Scoped by resource** via event selectors — you name exactly which buckets / tables /
  functions to record (see §3).

> 📌 **Our design:** data events are ARN-scoped via variables
> (`data_event_dynamodb_table_arn`, `data_event_lambda_function_arns`), **empty by
> default**. Empty → the selector block isn't even created → zero data events for that
> type. We deliberately never add the trail's own log bucket as an S3 data-event target
> — doing so creates a **feedback loop** (each log write is a PutObject = a data event =
> another log write) that bloats storage and runs up per-event charges.

> 📌 **Exam angle:** "CloudTrail isn't recording S3 object reads." → data events are
> **off by default**; you must add an S3 data event selector. "My data-event bill
> exploded." → data events are per-event and high-volume; scope them tightly.

---

## 3. Event selectors — basic vs advanced

Two ways to express *what to record*:

- **Basic event selectors** — the older style. Limited: management read/write type,
  and S3/Lambda/DynamoDB data events.
- **Advanced event selectors** — the current style (what the console uses now and what
  our module uses). Field-based: filter on `eventCategory`, `resources.type`,
  `resources.ARN`, `readOnly`, `eventName`, etc.

Scoping granularity with advanced selectors:

| Goal | How |
|---|---|
| One specific resource | `resources.ARN` **`equals`** `[exact-arn]` |
| A family (prefix) | `resources.ARN` **`startsWith`** `[arn-prefix]` |
| **All** resources of a type | **omit** the `resources.ARN` field entirely |
| Writes only (cut volume) | add `readOnly` `equals` `[false]` |

> 📌 **Exam angle:** know that `equals` = exact resource, `startsWith` = prefix/family,
> and *no ARN field* = everything of that type. The presence of the ARN selector is the
> narrowing lever.

---

## 4. Global vs Regional trails

### The mechanics
- A trail is created in a region, but **`is_multi_region_trail = true`** makes it
  capture events from **all regions** into one bucket. This is the recommended default
  (and what our module uses).
- A **single-region** trail only records events in its own region.

### Global service events
Some services are **global** and only emit their events in **`us-east-1`**:
**IAM, STS, CloudFront, Route 53, (and some AWS support/billing events).**

- `include_global_service_events = true` (our setting) ensures these are captured.
- A **multi-region** trail captures them cleanly everywhere.
- Historical gotcha: multiple single-region trails used to risk **duplicating** global
  events; AWS now delivers them to only one trail per account to avoid this.

> 📌 **Exam angle:** "I don't see IAM activity in my eu-central-1 trail." → IAM is a
> global service; its events originate in us-east-1. Use a **multi-region trail** with
> `include_global_service_events`. This is a very common question.

---

## 5. Log file integrity validation

Your objective: *"ensure log files have not been modified."* Mechanism:

1. With **`enable_log_file_validation = true`** (our setting), CloudTrail delivers,
   roughly **hourly**, a **digest file** to the same bucket (under a `CloudTrail-Digest/`
   prefix).
2. Each digest file lists the log files for that period with a **SHA-256 hash** of each,
   and the digest itself is **signed** (asymmetric, private key held by AWS).
3. Digest files are **hash-chained** — each references the previous one — so you can
   detect not just a modified log file but a **deleted** log or a **deleted digest**.
4. You verify with:
   ```bash
   aws cloudtrail validate-logs \
     --trail-arn arn:aws:cloudtrail:eu-central-1:<acct>:trail/<name> \
     --start-time 2026-01-01T00:00:00Z
   ```

> 📌 **Exam angle:** validation proves **integrity** (tamper-evidence), using signed,
> hash-chained digests. It does **not** encrypt or hide the logs — that's SSE-KMS. For
> defense-in-depth also use **S3 Object Lock / MFA Delete** and tight bucket policies so
> logs *can't* be deleted in the first place. Integrity validation *detects* tampering;
> Object Lock *prevents* it.

---

## 6. Storage, retention, encryption

### Storage (S3)
- Logs land under `s3://<bucket>/AWSLogs/<account-id>/CloudTrail/<region>/...`.
- The bucket needs the **CloudTrail bucket policy** (two statements): `s3:GetBucketAcl`
  on the bucket, and `s3:PutObject` on `AWSLogs/<acct>/*` with the
  `bucket-owner-full-control` ACL condition. Our module scopes both with an
  `aws:SourceArn` condition so only *this* trail can write.

### Retention — two independent horizons
| Store | Retention in our lab | Purpose |
|---|---|---|
| **S3** | 365 days (lifecycle rule) | Long-term **archive / audit** |
| **CloudWatch Logs** | 14 days | Short, **hot, queryable** copy for alarms |

> 📌 These are **separate settings**. S3 retention = lifecycle rule (expiration /
> transition to Glacier). CWL retention = `retention_in_days` on the log group. The
> exam likes "keep audit logs cheaply for 7 years" → S3 lifecycle **transition to
> Glacier / Deep Archive**, not CWL.

### Encryption
- **SSE-S3** — AWS-managed, zero config, no key control.
- **SSE-KMS** — our choice. You control the key, its **key policy**, rotation, and get
  CloudTrail/KMS API calls for key usage. The exam prefers KMS when "control over keys"
  or "separate team manages encryption" is mentioned.
- **The KMS key policy must allow CloudTrail** `kms:GenerateDataKey*` (our module does,
  scoped by the `kms:EncryptionContext:aws:cloudtrail:arn` condition). A wrong key
  policy = **trail silently stops delivering logs**. This is the #1 "trail not logging"
  root cause.

---

## 7. The three delivery destinations and their auth model

CloudTrail is *granted* access to each destination differently. Know this table cold:

| Destination | Auth mechanism | Where it lives |
|---|---|---|
| **S3 bucket** | **Resource-based** — S3 **bucket policy** names `cloudtrail.amazonaws.com` | on the bucket |
| **KMS key** | **Resource-based** — KMS **key policy** names `cloudtrail.amazonaws.com` | on the key |
| **CloudWatch Logs** | **Identity-based** — an **IAM role CloudTrail assumes** (trust = `cloudtrail.amazonaws.com`) | the role |

> 📌 **Exam angle:** S3 and KMS use **resource policies**; CloudWatch Logs uses an
> **assumed IAM role**. There is exactly **one** role in a CloudTrail setup, and it's
> assumed by CloudTrail itself — never by the services being logged.

---

## 8. CloudWatch Logs integration (real-time analysis)

- Logs reach **S3 within ~5 minutes** (archive). Delivering **also** to **CloudWatch
  Logs** gives a near-real-time stream you can act on.
- The value is **metric filters → alarms**: turn a log pattern into a metric, alarm on
  it. Our module ships the classic example — a **root-account-usage** filter + alarm.
- Common CloudOps metric-filter/alarm patterns (CIS benchmark favorites, all
  exam-relevant): root usage, unauthorized API calls (`AccessDenied`), console sign-in
  **without MFA**, IAM policy changes, security-group changes, changes to CloudTrail
  itself (`StopLogging`, `DeleteTrail`).

> 📌 **Exam angle:** "near-real-time alerting on API activity" = CloudTrail → **CloudWatch
> Logs** → metric filter → alarm → SNS. "query historical activity ad-hoc" = **Athena**
> over the S3 logs, or **CloudTrail Lake**.

---

## 9. CloudTrail Insights

- **Insights** detects **unusual activity** by learning your normal baseline and flagging
  anomalies in:
  - **API call rate** (`ApiCallRateInsight`) — a burst/drop in write-management-call
    volume (e.g. a runaway script, or an attacker enumerating).
  - **API error rate** (`ApiErrorRateInsight`) — a spike in errors like `AccessDenied`
    (e.g. a misconfigured deploy, or probing).
- Enabled on our trail via `insight_selector` (gated by `enable_insights`).
- **Billed** per analyzed event type; Insights events are written to S3 under an
  `Insight/` prefix (and visible in the console).

> 📌 **Exam angle:** Insights = **anomaly detection on top of CloudTrail**, specifically
> call-rate and error-rate. It is **not** a replacement for metric-filter alarms (which
> are deterministic pattern matches); it's statistical baselining for the *unexpected*.

---

## 10. Organization & cross-account trails (concept)

Our lab is single-account, but know the multi-account story:

- An **organization trail** (created from the AWS Organizations **management account**)
  applies to **every member account** automatically, including accounts added later.
  Member-account admins can see it but **cannot modify or delete** it.
- All member logs land in **one central S3 bucket** (typically in a dedicated
  **log-archive** account) — the Control Tower / landing-zone pattern.
- Benefits: consistent coverage, central audit, tamper separation (log-archive account
  is locked down).

> 📌 **Exam angle:** "ensure all accounts, including future ones, are logged to a central,
> tamper-resistant location" → **organization trail** + central **log-archive account**
> bucket with restrictive policy / Object Lock.

---

## Quick-recall cheat sheet

| Question | One-line answer |
|---|---|
| Activity older than 90 days? | Need a **trail → S3**; Event History is 90 days only |
| Record S3 object reads? | Add an **S3 data event** selector (data events off by default) |
| Don't see IAM events? | Global service → us-east-1 → use **multi-region** + global service events |
| Prove logs untampered? | **Log file validation** → signed, hash-chained **digest files** → `validate-logs` |
| Prevent log deletion? | **S3 Object Lock / MFA Delete** + tight bucket policy (prevention ≠ validation) |
| Keep audit logs cheaply for years? | S3 **lifecycle → Glacier/Deep Archive** |
| Trail stopped logging after KMS change? | **KMS key policy** no longer allows CloudTrail `GenerateDataKey*` |
| Real-time alert on root login? | CloudTrail → **CWL** → metric filter → alarm → SNS |
| Ad-hoc query of history? | **Athena** over S3 logs, or **CloudTrail Lake** |
| Detect unusual API bursts/errors? | **CloudTrail Insights** (call-rate / error-rate) |
| Log all accounts incl. future ones? | **Organization trail** from the management account |
| Who gets the role — logged service or CloudTrail? | **CloudTrail** assumes the role (only for CWL); S3/KMS use resource policies |
