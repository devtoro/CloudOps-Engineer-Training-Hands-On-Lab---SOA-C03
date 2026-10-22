# CloudTrail — Hands-On Walkthrough (Deploy, Explore, Validate)

> Click-by-click and CLI-by-CLI companion to `cloudtrail-concepts.md`. Work through it
> after `terraform apply`. Every step says *what to run / click*, *what you should see*,
> and the *exam angle*.
>
> **Region:** `eu-central-1` · **Profile:** `dev` · **Trail:** `cloudops-trail-dev-trail`
>
> **Doc currency:** verified against AWS docs (CloudTrail User Guide / CLI). Console
> labels drift; where a path may change, the underlying API/CLI is given too.
> Content rephrased from AWS documentation for licensing compliance.

---

## 0. Prerequisites

```bash
aws sso login --profile dev
export AWS_PROFILE=dev
export AWS_REGION=eu-central-1
cd Cloudtrail/terraform
```

---

## 1. Deploy the trail

```bash
terraform init
terraform plan      # review: S3 bucket, KMS key+alias, bucket/key policies,
                    # the trail, CWL group, IAM role, metric filter + alarm
terraform apply
```

Capture the outputs:

```bash
terraform output
#   trail_bucket_name          = cloudops-trail-dev-logs-<acct>
#   trail_kms_key_arn          = arn:aws:kms:eu-central-1:<acct>:key/...
#   trail_name                 = cloudops-trail-dev-trail
#   trail_cloudwatch_log_group = /aws/cloudtrail/cloudops-trail-dev
```

### Confirm it's actually logging

```bash
TRAIL=$(terraform output -raw trail_name)

# Is the trail switched on? (A created trail is not necessarily logging.)
aws cloudtrail get-trail-status --name "$TRAIL" \
  --query '{IsLogging:IsLogging, LatestDeliveryTime:LatestDeliveryTime, LatestDeliveryError:LatestDeliveryError}'
```

- `IsLogging: true` → good.
- `LatestDeliveryError` → if present, usually a **bucket policy** or **KMS key policy**
  problem (the #1 cause). Our module sets both correctly, so this should be empty.

> 📌 **Exam angle:** `get-trail-status` → `IsLogging` and `LatestDeliveryError` are the
> first things you check when "the trail exists but no logs are showing up." Trail
> *created* ≠ trail *logging* — `StartLogging` must have run (Terraform/console do this).

---

## 2. Generate some activity

Any API call works. Make a few harmless ones so there's something to find:

```bash
aws sts get-caller-identity
aws s3 ls
aws ec2 describe-instances --max-items 5 >/dev/null
# a deliberate denied call, for later error-rate / unauthorized exploration:
aws iam create-user --user-name cloudtrail-lab-should-fail-$RANDOM || true
```

> Management events land in **Event History within minutes**. Delivery to **S3** can
> take ~5 minutes; to **CloudWatch Logs** it's near-real-time.

---

## 3. Event History (the free, built-in 90-day view)

**Console:** CloudTrail → **Event history**.

1. The default list shows recent **management** events across the account.
2. Use the **Lookup attributes** dropdown to filter — e.g. **Event name** = `CreateUser`,
   or **User name**, or **Event source** = `s3.amazonaws.com`.
3. Click an event → **View event** to see the raw JSON record.

CLI equivalent:

```bash
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=GetCallerIdentity \
  --max-results 5
```

### Anatomy of an event record (know these fields)

| Field | Meaning |
|---|---|
| `eventName` / `eventSource` | the API action + the service (`CreateUser` / `iam.amazonaws.com`) |
| `userIdentity` | **who** — `type` (IAMUser / AssumedRole / Root / AWSService), `arn`, `accountId` |
| `sourceIPAddress` | **from where** |
| `eventTime` | **when** (UTC) |
| `awsRegion` | region the call was made in |
| `errorCode` / `errorMessage` | present when the call failed (e.g. `AccessDenied`) |
| `readOnly` | true for Describe/Get/List, false for mutations |
| `managementEvent` / `eventCategory` | Management vs Data |

> 📌 **Exam angle:** Event History is **management events only** and **90 days**. If a
> question needs data events, or history older than 90 days, you need the **trail** →
> S3 (steps 4–5), not Event History.

---

## 4. Inspect a log file in S3

```bash
BUCKET=$(terraform output -raw trail_bucket_name)
ACCT=$(aws sts get-caller-identity --query Account --output text)

# Browse the prefix structure
aws s3 ls "s3://$BUCKET/AWSLogs/$ACCT/CloudTrail/$AWS_REGION/" --recursive | head

# Pull the newest log object and pretty-print it
KEY=$(aws s3 ls "s3://$BUCKET/AWSLogs/$ACCT/CloudTrail/$AWS_REGION/" --recursive \
      | sort | tail -1 | awk '{print $4}')
aws s3 cp "s3://$BUCKET/$KEY" /tmp/ct.json.gz && gunzip -f /tmp/ct.json.gz
jq '.Records[0]' /tmp/ct.json
```

What to notice:
- Objects are **gzipped JSON**, path `AWSLogs/<acct>/CloudTrail/<region>/YYYY/MM/DD/`.
- The download succeeded because your identity can **`kms:Decrypt`** with the trail key
  (granted in the key policy). Remove that and the download fails with `AccessDenied` —
  proving SSE-KMS is in force.
- Alongside `CloudTrail/` you'll see a **`CloudTrail-Digest/`** prefix (step 6).

> 📌 **Exam angle:** can't read log objects → check the **KMS key policy** grants your
> principal `Decrypt`. Encryption at rest (SSE-KMS) is independent from integrity
> validation (digests) — different problems, different fixes.

---

## 5. Management vs Data events (optional — needs targets)

Our trail records **management events** out of the box. **Data events** only fire for
ARNs you supply. To see them:

1. Redeploy the Phase 1 Cloudwatch lab (or point at any table/function), then:

   ```bash
   # in Cloudtrail/terraform
   terraform apply \
     -var 'data_event_dynamodb_table_arn=arn:aws:dynamodb:eu-central-1:<acct>:table/cloudops-lab-dev-orders' \
     -var 'data_event_lambda_function_arns=["arn:aws:lambda:eu-central-1:<acct>:function:cloudops-lab-dev-orders"]'
   ```

2. Generate item/invoke activity (hit the Phase 1 API, or `put-item` directly).
3. In **Event history**, filter **Event name** = `PutItem` or `Invoke`. These are
   **data events** — note `eventCategory: Data` and `readOnly` in the record.

> 📌 **Exam angle:** data events are **off by default**, **ARN-scoped**, and **billed per
> event**. Never target the trail's own log bucket for S3 data events (feedback loop).

---

## 6. Verify log file integrity (`validate-logs`)

This is the "prove logs weren't modified" objective. With validation enabled, CloudTrail
delivers a **digest file about once per hour** to the `CloudTrail-Digest/` prefix; each
digest lists the hour's log files with SHA-256 hashes and is **signed** and
**hash-chained** to the previous digest.

> ⏳ You need at least one delivered digest, so run this **an hour or more** after apply.

```bash
TRAIL_ARN=$(aws cloudtrail get-trail --name "$TRAIL" --query 'Trail.TrailARN' --output text)

aws cloudtrail validate-logs \
  --trail-arn "$TRAIL_ARN" \
  --start-time "$(date -u -v-2H '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date -u -d '2 hours ago' '+%Y-%m-%dT%H:%M:%SZ')" \
  --verbose
```

Reading the output (confirmed against current CLI docs):
- Starts with a header: `Validating log files for trail <ARN> between <ts> and <ts>`.
- Each line: `[<optional (backfill)>] <Digest file|Log file> <S3 path> <message>`.
- **Non-verbose** prints only problems (any `INVALID: ...`). **`--verbose`** also prints
  `valid` lines for every digest and log file — use it to *see* success, not just the
  absence of errors.
- Key messages: `valid`; `INVALID: hash value doesn't match` (log modified after
  delivery); `INVALID: signature verification failed` (digest tampered); `INVALID: not
  found` (file deleted). Lines prefixed `(backfill)` belong to a separate backfill
  digest chain.

### Prove tamper-detection yourself (optional, satisfying)

```bash
# Re-upload a log object with one byte changed, then re-validate that window:
#   validate-logs should report  INVALID: hash value doesn't match
```

> 📌 **Exam angle:** validation = **integrity / tamper-evidence** via signed,
> hash-chained digests. To *prevent* deletion/modification (not just detect it) add
> **S3 Object Lock** / **MFA Delete** and lock down the bucket policy. Detect vs prevent
> is a classic distractor pair.

---

## 7. CloudWatch Logs integration + the root-usage alarm

Our trail also streams to a CloudWatch Logs group for near-real-time analysis, with a
metric filter + alarm for **root account usage** already wired.

### See events arriving

**Console:** CloudWatch → **Log groups** → `/aws/cloudtrail/cloudops-trail-dev` → latest
stream. Or Logs Insights:

```
fields eventTime, eventName, userIdentity.arn, sourceIPAddress
| sort @timestamp desc
| limit 20
```

### Inspect the metric filter + alarm

**Console:** CloudWatch → **Alarms** → `cloudops-trail-dev-root-account-usage`
(state `OK` / `Insufficient data` until it fires). And the filter under the log group's
**Metric filters** tab (pattern matches `userIdentity.type = "Root"`).

### Trigger it (optional — requires root)

Sign in to the console as the **account root user** and make any call. Within a few
minutes the metric filter emits a data point and the alarm flips to **ALARM**.
(No SNS in this lab — the alarm just changes state, visible in the console. SNS
notifications come in the Alarms phase.)

> 📌 **Exam angle:** near-real-time alerting on CloudTrail = **CWL → metric filter →
> alarm → SNS**. The CIS-benchmark filters worth recognizing: root usage, console
> sign-in without MFA, unauthorized (`AccessDenied`) calls, IAM/security-group changes,
> and changes to CloudTrail itself (`StopLogging`, `DeleteTrail`).

---

## 8. CloudTrail Insights

Insights baselines your normal activity and flags anomalies in **API call rate**
(write-only management/data calls per minute) and **API error rate** (read+write).
Enabled on our trail via `insight_selector`.

**Console:** CloudTrail → **Insights** → shows a timeline of any detected anomalies; a
flagged item opens an **Insights event** with the baseline vs observed rate.

> ⏳ **Important (confirmed in docs):** after first enabling Insights it can take **up to
> ~7 days** to establish a baseline before any Insights events are delivered. So an empty
> Insights tab right after apply is **expected**, not a bug.

To *provoke* an anomaly later, run an unusual burst of write calls (e.g. create/delete
many resources in a tight loop) well above your baseline and check back.

> 📌 **Exam angle:** Insights = **statistical anomaly detection** (call-rate /
> error-rate), distinct from deterministic metric-filter alarms. Needs **write**
> management events for call-rate, **read+write** for error-rate. Baseline/delivery is
> **not instant** (up-to-7-day warm-up).

---

## 9. (Reference) Analyze history at scale

- **Athena** — query the S3 logs with SQL (CloudTrail console can auto-create the table).
  Best for ad-hoc "who did X last quarter" over the archive.
- **CloudTrail Lake** — managed, immutable event data store with SQL, longer retention,
  no S3/Athena plumbing. Newer; increasingly referenced in exam questions.

> 📌 **Exam angle:** real-time alert → **CWL + metric filter**. Ad-hoc historical query →
> **Athena / CloudTrail Lake**. Anomaly detection → **Insights**. Three different tools
> for three different questions.

---

## 10. Clean up

```bash
cd Cloudtrail/terraform
terraform destroy
```

- The log bucket has `force_destroy = true` (lab convenience) so it's removed even with
  objects inside. **Never** set that on a real audit bucket.
- The KMS key is scheduled for deletion (7-day window from the module) — it is not
  destroyed instantly, by design.

---

## Deploy-and-explore checklist

- [ ] `terraform apply` succeeded; `get-trail-status` shows `IsLogging: true`, no delivery error.
- [ ] Found my own `GetCallerIdentity` / `CreateUser` in **Event History** and read the JSON.
- [ ] Downloaded and `jq`'d a log object from S3 (proving KMS decrypt works).
- [ ] (Optional) Enabled data events and saw `PutItem` / `Invoke` with `eventCategory: Data`.
- [ ] Ran `validate-logs --verbose` and saw `valid` digest + log lines (after ~1h).
- [ ] Queried the CloudWatch Logs group; located the root-usage metric filter + alarm.
- [ ] Opened the **Insights** tab (understanding the up-to-7-day warm-up).
- [ ] `terraform destroy` to stop charges.
