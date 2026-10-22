# AWS X-Ray — Hands-On Walkthrough (Trace, Map, Debug)

> Click-by-click and CLI-by-CLI companion to `xray-concepts.md`. Work through it after
> deploying the X-Ray-instrumented Phase 1 app. Each step says *what to run / click*,
> *what you should see*, and the *exam angle*.
>
> **Region:** `eu-central-1` · **Profile:** `dev` · **App:** `cloudops-lab-dev-*`
>
> **Doc currency:** verified against current AWS docs. **Important console change:** the
> standalone X-Ray service map and CloudWatch ServiceLens map are now **merged into one
> "X-Ray trace map" inside the CloudWatch console**. Paths below reflect that.
> Content rephrased from AWS documentation for licensing compliance.

---

## 0. Prerequisites

```bash
aws sso login --profile dev
export AWS_PROFILE=dev
export AWS_REGION=eu-central-1
cd Cloudwatch/terraform
```

Requires `pip` on PATH — the Lambda modules vendor `aws-xray-sdk` into the source dirs via
a Terraform `null_resource` at apply time.

---

## 1. Deploy the instrumented app

```bash
terraform init     # pulls the null provider used for dependency vendoring
terraform apply    # builds zips (with aws-xray-sdk), enables Active tracing + X-Ray IAM
```

What `apply` turns on:
- **API Gateway stage:** `xray_tracing_enabled = true`.
- **Both Lambdas:** `tracing_config.mode = Active` + `AWSXRayDaemonWriteAccess`.
- Handlers call `patch_all()` and emit subsegments.

Grab the API URL + key (from the Phase 1 outputs):

```bash
API_URL=$(terraform output -raw api_url)
KEY=$(terraform output -raw api_key_value 2>/dev/null || \
  terraform show -json | jq -r '.values.root_module.child_modules[]?.resources[]? | select(.type=="aws_api_gateway_api_key") | .values.value')
```

---

## 2. Generate traffic (a mix, so the map has something to show)

```bash
# happy (x8) — API GW → Orders Lambda → DynamoDB + EventBridge → Processor
for i in $(seq 1 8); do
  curl -s -o /dev/null -X POST "$API_URL/orders" -H "x-api-key: $KEY" \
    -H "Content-Type: application/json" -d '{"item":"widget","quantity":1}'
done

# slow (x3) — inflates the Orders Lambda segment (artificial-delay subsegment)
for i in $(seq 1 3); do
  curl -s -o /dev/null -X POST "$API_URL/orders" -H "x-api-key: $KEY" \
    -H "Content-Type: application/json" -d '{"item":"slow","quantity":1,"delay":5}'
done

# fault (x3) — item=fail → 500 → FAULT on the Orders node
for i in $(seq 1 3); do
  curl -s -o /dev/null -X POST "$API_URL/orders" -H "x-api-key: $KEY" \
    -H "Content-Type: application/json" -d '{"item":"fail","quantity":1}'
done

# processor fault (x2) — order succeeds; the async Processor faults
for i in $(seq 1 2); do
  curl -s -o /dev/null -X POST "$API_URL/orders" -H "x-api-key: $KEY" \
    -H "Content-Type: application/json" -d '{"item":"processor-fail","quantity":1}'
done
```

> ⏳ Traces take **~1–2 minutes** to appear.

> 📌 **Sampling caveat (confirmed in docs):** the default rate is **1 request/sec + 5%**
> of the rest — and for **Lambda it is NOT configurable**; Lambda manages its own
> sampling. So you may not see *every* request as a trace. That's expected, not a bug.

---

## 3. The trace map (CloudWatch console)

**Console:** CloudWatch → left nav **X-Ray traces → Trace Map** (this is the merged
X-Ray/ServiceLens map).

You should see nodes roughly like:
```
Client → cloudops-lab-dev-api (API GW) → cloudops-lab-dev-orders (Lambda) → DynamoDB
                                                     └→ EventBridge
         cloudops-lab-dev-processor (Lambda)
```

Reading it (confirmed legend behavior):
- **Circle size** ∝ traced request volume.
- **Color ring:** green = OK, **red = faults (5xx)**, yellow = errors (4xx), purple =
  throttles (429). After the traffic above, the **Orders** node ring shows red (the
  `fail` calls) and the **Processor** node shows red too (the `processor-fail` calls).
- Click a node → latency distribution + response-code breakdown + **View traces**.

> 📌 **Exam angle:** the trace map is the **triage first-stop** — a red node localizes a
> fault to a specific service in one glance before you open any individual trace.

---

## 4. Find the bottleneck (trace timeline)

1. Click the **Orders** node → **View traces** → filter to a **slow** one (sort by
   response time, or filter by annotation — see §6).
2. Open the trace → the **timeline** (segments/subsegments as time-positioned bars).

What you should see on a `slow` trace:
- The **Orders Lambda** segment bar is ~5s long.
- Expand it: the **`artificial-delay`** subsegment is the long bar; the **DynamoDB
  PutItem** and **EventBridge PutEvents** subsegments are milliseconds.
- Conclusion: time is in that code block, not a downstream dependency.

> 📌 **Exam angle:** bottleneck = the **longest subsegment**. Long subsegment that is a
> *downstream call* → the dependency is slow. Long subsegment that is *your code* → the
> function. The timeline makes "where did the time go" literal.

---

## 5. Error vs Fault tracking

1. Click the **Orders** node → **View traces** → open a trace from an `item=fail` call.
2. The segment is flagged a **Fault** (5xx); expand to see the exception type + stack
   captured by the SDK.
3. Compare with a validation trace (missing fields → 400) → flagged an **Error** (4xx).

> 📌 **Exam angle:** **Error = 4xx (client), Fault = 5xx (server), Throttle = 429.** A
> spike of **faults** points at your code/dependency; a spike of **errors** points at
> callers sending bad requests. The map's ring color reflects the ratio.

---

## 6. Filter traces by annotation (our instrumentation payoff)

Our handlers add annotations (`item`, `order_id`, `upstream_trace_id`, `delay_seconds`).
In the traces view, use a filter expression:

```
annotation.item = "slow"
annotation.item = "fail"
```

Only matching traces show — this is why annotations (indexed) beat metadata (not indexed)
for querying.

CLI equivalent (grab recent trace summaries):

```bash
aws xray get-trace-summaries \
  --start-time "$(date -u -v-15M '+%s' 2>/dev/null || date -u -d '15 min ago' '+%s')" \
  --end-time "$(date -u '+%s')" \
  --filter-expression 'annotation.item = "slow"'
```

> 📌 **Exam angle:** **annotations are indexed and filterable**; metadata is not. Design
> instrumentation so the fields you'll want to query are annotations.

---

## 7. The async boundary (why the Processor was a design talking-point)

Open a `processor-fail` trace path and note:
- API Gateway → Orders Lambda is one connected trace (sync, header auto-propagated).
- The **Processor** work is correlated via our **manual propagation** — the Orders Lambda
  put the trace header into the event (`_xray_trace`), and the Processor recorded
  `upstream_trace_id` as an annotation.

Verify the correlation:
```
annotation.upstream_trace_id = "<the Root id from an Orders trace>"
```

> 📌 **Exam angle:** async hops (EventBridge/SQS/SNS/S3) **don't auto-propagate** the
> trace header to the consumer. Without manual propagation the Processor would be a
> **separate, disconnected trace**. Carrying the header in the message is the fix.

---

## 8. X-Ray Insights (anomaly detection)

**Console:** CloudWatch → **X-Ray traces → Insights** (enable Insights for the default
group if prompted).

- Insights baselines fault/latency and raises an **incident** when a node deviates
  significantly (e.g. the Orders node's fault rate jumps from the `fail` traffic).
- Incidents track start time, impact, and the implicated node.

> ⏳ Like other anomaly features, Insights needs some baseline data; a brand-new app won't
> show incidents immediately.

> 📌 **Exam angle:** "automatically detect + notify on unusual fault/latency patterns in a
> distributed app" → **X-Ray Insights** (notify via **EventBridge**).

---

## 9. Sampling rules (see + tune)

```bash
# View the default rule (1 req/sec reservoir + 5% rate)
aws xray get-sampling-rules \
  --query 'SamplingRuleRecords[].SamplingRule.{name:RuleName, reservoir:ReservoirSize, rate:FixedRate, priority:Priority}'
```

- The **Default** rule is reservoir 1 + rate 0.05.
- You can add a higher-priority custom rule (e.g. trace 100% of a specific path) in the
  console under **X-Ray traces → Settings → Sampling**.
- Reminder: **Lambda sampling is not configurable** via these rules — Lambda decides.

> 📌 **Exam angle:** reservoir = guaranteed first-N-per-second; fixed rate = % of the
> rest. Lower sampling = cheaper but less visibility. Custom rules target specific paths.

---

## 10. Clean up

```bash
cd Cloudwatch/terraform
terraform destroy
```

- Tracing itself has no standalone resource to delete — it's config on the Lambdas/stage,
  removed with the app. X-Ray trace storage is time-boxed (traces expire automatically).

---

## Deploy-and-explore checklist

- [ ] `apply` succeeded; Lambdas show Active tracing (console → function → Configuration → Monitoring).
- [ ] Generated happy/slow/fault/processor-fail traffic.
- [ ] Opened the **trace map** in the CloudWatch console; saw the topology + red fault rings.
- [ ] Opened a **slow** trace; identified `artificial-delay` as the longest subsegment.
- [ ] Distinguished a **Fault** (item=fail, 5xx) from an **Error** (missing fields, 4xx).
- [ ] Filtered traces with `annotation.item = "slow"`.
- [ ] Correlated the async Processor via `annotation.upstream_trace_id`.
- [ ] Viewed the default **sampling rule** and noted Lambda sampling is not configurable.
- [ ] (Optional) Explored **X-Ray Insights**.
- [ ] `terraform destroy`.
```
