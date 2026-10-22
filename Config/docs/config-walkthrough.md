# AWS Config — Hands-On Walkthrough (Deploy, Explore, Remediate)

> Click-by-click and CLI-by-CLI companion to `config-concepts.md`. Work through it after
> `terraform apply`. Each step says *what to run / click*, *what you should see*, and the
> *exam angle*.
>
> **Region:** `eu-central-1` · **Profile:** `dev` · **Prefix:** `cloudops-config-dev`
>
> **Doc currency:** verified against current AWS docs (Config Developer Guide; SSM
> Automation runbook reference). Console labels drift; underlying API/CLI given too.
> Content rephrased from AWS documentation for licensing compliance.

---

## 0. Prerequisites & cost note

```bash
aws sso login --profile dev
export AWS_PROFILE=dev
export AWS_REGION=eu-central-1
cd Config/terraform
```

> 💲 **Cost:** Config bills per **configuration item recorded** and per **rule
> evaluation** — cents for a lab, but it accrues while the recorder runs. We chose to
> **record all resource types**, so turning the recorder off (or `terraform destroy`)
> between sessions keeps it minimal. See §8.

---

## 1. Deploy

```bash
terraform init
terraform plan      # recorder + delivery channel + S3 bucket/policy + IAM role,
                    # 3 rules (SSE, required-tags, custom Lambda), remediation
terraform apply
terraform output
#   config_bucket_name   = cloudops-config-dev-<acct>
#   config_recorder_name = cloudops-config-dev-recorder
#   config_rule_names    = [ ...-s3-sse-enabled, ...-required-tags, ...-s3-naming-check ]
```

### Confirm the recorder is actually ON

```bash
aws configservice describe-configuration-recorder-status \
  --query 'ConfigurationRecordersStatus[0].{recording:recording, lastStatus:lastStatus}'
# recording: true, lastStatus: SUCCESS  → good
```

> 📌 **Exam angle:** `recording: true` is the on-switch (our Terraform sets
> `recorder_status.is_enabled = true`). A recorder that exists but isn't recording
> produces **no** configuration items — first thing to check when "Config has no data."
> `lastStatus` other than SUCCESS usually means the **delivery channel / S3 bucket
> policy** is wrong.

---

## 2. See configuration items & the change history

Config needs a few minutes to discover and record resources after first start.

**Console:** AWS Config → **Resources** (inventory) → filter by type (e.g.
`AWS::S3::Bucket`) → click a resource.

- **Resource timeline** — the history of that resource: each **configuration item**,
  what changed, the **compliance** status, and the **linked CloudTrail event** that
  caused the change. (Confirmed current console behavior.)

CLI — pull the raw history of one resource:

```bash
# Example: history for the Config bucket itself
BUCKET=$(terraform output -raw config_bucket_name)
aws configservice get-resource-config-history \
  --resource-type AWS::S3::Bucket \
  --resource-id "$BUCKET" \
  --query 'configurationItems[0].{captureTime:configurationItemCaptureTime, status:configurationItemStatus}'
```

> 📌 **Exam angle:** the **configuration item (CI)** is the atomic unit — a point-in-time
> snapshot of a resource's config + relationships + the related event. "What did this
> look like last week?" → **resource timeline / `get-resource-config-history`**.

---

## 3. Make a resource NON_COMPLIANT (watch rules evaluate)

Create a bucket that trips **two** rules at once — the custom naming rule (name contains
"public") and, briefly, the SSE rule:

```bash
ACCT=$(aws sts get-caller-identity --query Account --output text)
BAD="cloudops-config-dev-public-demo-$ACCT"

# Create WITHOUT tags and WITHOUT touching encryption settings
aws s3api create-bucket --bucket "$BAD" \
  --create-bucket-configuration LocationConstraint=eu-central-1
```

Notes:
- The name contains **"public"** → the **custom `s3-naming-check`** rule should flag it
  **NON_COMPLIANT**.
- It has no `Project` / `Environment` tags → the **`required-tags`** rule should flag it
  **NON_COMPLIANT**.
- New buckets get SSE-S3 by default now, so the **SSE rule** may show COMPLIANT. To force
  an SSE violation for the remediation demo, see §5.

### Trigger evaluation and read compliance

Change-triggered rules fire on the create event within minutes. To force immediately:

```bash
aws configservice start-config-rules-evaluation \
  --config-rule-names cloudops-config-dev-s3-naming-check cloudops-config-dev-required-tags
```

**Console:** AWS Config → **Rules** → open a rule → see **Compliant / Noncompliant**
resource counts, and drill into the specific non-compliant resource.

CLI:

```bash
aws configservice get-compliance-details-by-config-rule \
  --config-rule-name cloudops-config-dev-s3-naming-check \
  --query 'EvaluationResults[].{resource:EvaluationResultIdentifier.EvaluationResultQualifier.ResourceId, compliance:ComplianceType}'
```

> 📌 **Exam angle:** rules return **COMPLIANT / NON_COMPLIANT / NOT_APPLICABLE**.
> `start-config-rules-evaluation` forces a re-eval without waiting for the next change or
> periodic run — handy in demos and in the exam's "how do I re-check now?" scenarios.

---

## 4. Inspect the custom Lambda rule end-to-end

**Console:** Lambda → `cloudops-config-dev-s3-naming-rule` → **Monitor** → view logs. You'll
see each invocation log the bucket it evaluated and the verdict it returned.

What happened under the hood (the integration the exam asks about):
1. Config detected the S3 change and **invoked** the Lambda (allowed by the
   `aws_lambda_permission` for `config.amazonaws.com`).
2. The Lambda returned a verdict via **`config:PutEvaluations`** (allowed by its IAM
   policy).

> 📌 **Exam trap:** if a custom rule shows **no results** / stuck evaluating, the usual
> causes are (a) Lambda missing **`config:PutEvaluations`**, or (b) Config lacking
> **invoke permission**. Both are wired in our `config-rules` module.

---

## 5. Remediation — auto-fix an SSE violation

The `s3-sse-enabled` rule has **automatic remediation** attached (SSM Automation document
**`AWS-EnableS3BucketEncryption`**). Create a bucket with encryption explicitly removed so
the rule flags it, then watch it get fixed.

```bash
ACCT=$(aws sts get-caller-identity --query Account --output text)
SSE="cloudops-config-dev-sse-demo-$ACCT"

aws s3api create-bucket --bucket "$SSE" \
  --create-bucket-configuration LocationConstraint=eu-central-1

# Remove default encryption to violate the rule
aws s3api delete-bucket-encryption --bucket "$SSE"

# Force the SSE rule to evaluate now
aws configservice start-config-rules-evaluation \
  --config-rule-names cloudops-config-dev-s3-sse-enabled
```

Then watch:
- **Console:** AWS Config → **Rules** → `...-s3-sse-enabled` → the bucket appears
  **Noncompliant**, then after remediation runs it flips back to **Compliant**. The
  **Action status** column shows the remediation execution.
- Verify the fix directly:

```bash
aws s3api get-bucket-encryption --bucket "$SSE" \
  --query 'ServerSideEncryptionConfiguration.Rules[0].ApplyServerSideEncryptionByDefault'
# → { "SSEAlgorithm": "AES256" }  after remediation
```

How the pieces line up (verified against the runbook reference — parameters are
`AutomationAssumeRole`, `BucketName` (required), `SSEAlgorithm` (default `AES256`)):
- Config maps the non-compliant bucket's id → the document's **`BucketName`**
  (our `resource_value = "RESOURCE_ID"`).
- The document runs under **`AutomationAssumeRole`** = our remediation role, which holds
  `s3:PutEncryptionConfiguration`.

> 📌 **Exam angle:** remediation = **Config rule + SSM Automation runbook + an
> assume-role that holds the fix permissions**. Automatic remediation is convenient but
> **risky at scale** — prefer manual (console "Remediate" button) in sensitive/prod
> environments. AWS also ships a dedicated **`AWSConfigRemediation-*`** runbook family
> for many rules.

### Manual remediation (optional)
If you set `automatic = false` on the module, the console shows a **Remediate** button on
non-compliant resources — you pick which to fix. Same document + role, you just pull the
trigger.

---

## 6. React to non-compliance in real time (concept check)

Config emits **compliance-change events** to **EventBridge**. A rule like this routes any
flip to NON_COMPLIANT to a target (SNS/Lambda/Step Functions):

```json
{
  "source": ["aws.config"],
  "detail-type": ["Config Rules Compliance Change"],
  "detail": { "newEvaluationResult": { "complianceType": ["NON_COMPLIANT"] } }
}
```

> 📌 **Exam angle:** "alert / kick off a workflow the instant something becomes
> non-compliant" → Config → **EventBridge** → target. (We don't deploy this in the lab,
> but recognize the pattern.)

---

## 7. The big three, side by side (reinforcement)

With Config, CloudTrail (previous lab), and CloudWatch (Phase 1) all understood:

- Change the bad bucket's tags, then open its **Config resource timeline** → see the CI
  change **and** the linked **CloudTrail** `PutBucketTagging` event (who did it).
- That link — Config *what changed* + CloudTrail *who changed it* — is the governance
  story the exam keeps returning to.

---

## 8. Clean up

```bash
# Remove the demo buckets first
aws s3 rb "s3://cloudops-config-dev-public-demo-$ACCT" --force
aws s3 rb "s3://cloudops-config-dev-sse-demo-$ACCT" --force

cd Config/terraform
terraform destroy
```

> 📌 Destroy stops configuration-item + evaluation charges. The Config bucket has
> `force_destroy = true` (lab only). If `destroy` complains the recorder is in use, it's
> the ordering again — rerun; Terraform tears down status → delivery channel → recorder.

---

## Deploy-and-explore checklist

- [ ] `describe-configuration-recorder-status` shows `recording: true`, `lastStatus: SUCCESS`.
- [ ] Opened a resource's **timeline** and saw CIs + the linked CloudTrail event.
- [ ] Created a `*public*` untagged bucket; saw **custom** + **required-tags** rules go NON_COMPLIANT.
- [ ] Read the custom rule's Lambda logs; understood invoke + `PutEvaluations`.
- [ ] Forced an SSE violation and watched **automatic remediation** flip it back to COMPLIANT.
- [ ] Verified `get-bucket-encryption` shows `AES256` after remediation.
- [ ] Understood the Config → EventBridge non-compliance pattern.
- [ ] Cleaned up demo buckets + `terraform destroy`.
