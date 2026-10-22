# Phase 1 · Checkpoint 7 — CloudWatch Metrics Exploration (Guided Tutorial)

> **Purpose:** A hands-on, revisitable walkthrough of the AWS-generated metrics for
> every service in the Order Processing Platform. Use it now to explore, and again
> later as an exam-prep reference. Each step tells you *where to click*, *what you
> should see*, *why*, and the *exam angle*.
>
> **Region:** `eu-central-1`  ·  **Prerequisite:** you've run
> `Cloudwatch/scripts/generate-traffic.sh` at least once.

---

## 0. Before you start — the two settings that trip everyone up

CloudWatch graphs feel "broken" until you fix two things:

1. **Time range** (top-right of any graph): set to **Last 1 hour**. Default is often
   3 hours, which flattens recent spikes into invisibility.
2. **Period** (Graphed metrics tab → Period column): set to **1 minute**. The default
   5-minute period smears short bursts.

> 📌 **Exam note — latency of metrics:** standard AWS metrics are delivered at
> **1-minute** granularity for most services, and appear with a **1–3 minute delay**.
> "Detailed monitoring" (e.g. EC2 at 1-min instead of 5-min) and **high-resolution
> custom metrics** (down to 1 second) are separate concepts the exam likes to probe.
> The built-in metrics you're about to see are standard resolution.

---

## 1. The navigation mental model (read this once, it unlocks everything)

> ⚠️ **Console note (2026):** AWS reorganized the CloudWatch metrics UI. The old
> left-nav entry **"All metrics"** is gone. The classic namespace/dimension browser
> now lives under **CloudWatch → left nav → Metrics → Classic metrics**. There's also
> a newer **Query Studio** (SQL-style querying) and **Explorer** (tag/resource-based
> views), but for learning the raw namespace→dimension model, **Classic metrics** is
> the one that maps 1:1 to the concepts below. Every path in this guide uses it.

In the console: **CloudWatch → Metrics → Classic metrics**. You land on a **Browse**
tab that lists namespaces. The drill-down path is always:

```
Namespace  →  Dimension grouping  →  Metric  →  (Statistic + Period applied on the graph)
```

Concretely:

```
AWS/Lambda                     ← namespace    (who owns the metric)
   └── By Function Name        ← dimension    (how it's sliced)
         └── Invocations       ← metric       (what is measured)
               └── Sum / 1 min ← statistic    (how it's aggregated over the period)
```

> 📌 **This path IS the Checkpoint 8 answer.** As you click through, say the four
> words out loud: *namespace, dimension, metric, statistic*. By the end of this tour
> you should be able to define each without notes.

---

## 2. Lambda — namespace `AWS/Lambda`

### Step 2.1 — Open the function metrics

1. **CloudWatch → Metrics → Classic metrics → Browse tab**.
2. In the namespace list click **Lambda** (this is the `AWS/Lambda` namespace).
3. Click the dimension grouping **By Function Name**.
4. You'll see two functions: `cloudops-lab-dev-orders` and `cloudops-lab-dev-processor`.
5. Tick the boxes for the **orders** function metrics below to graph them. Then open the
   **Graphed metrics** tab to change the **Statistic** and **Period** per line.

### Step 2.2 — The orders function

| Metric | What you sent | Expected | Why / what to notice |
|---|---|---|---|
| `Invocations` | ~25 requests that reached Lambda | ~25 | Count of executions. Scenario 6 (no key) is **absent** — it never reached Lambda. |
| `Errors` | 5 × `item=fail` | **5** | Only **unhandled exceptions** count. The 5 validation 400s were *handled* (your code returned 400) → **not** errors. |
| `Duration` | 3 × `item=slow` (5s each) | Max ≈ 5000 ms; Average pulled upward | Execution time per invocation. Use **p99** / **Maximum** statistic to see the slow tail; **Average** hides it. |
| `Throttles` | — | 0 | Fires when invocations exceed the concurrency limit. We force this in §6. |
| `ConcurrentExecutions` | overlap of slow + burst | small spike | Instances running at the same moment. |

> ✅ **Record in notes:** Why is `Errors` = 5 and not 10? Articulate the difference
> between a *handled* non-200 response (your 400) and an *unhandled exception*
> (the `fail` path). CloudWatch's `Errors` only sees the latter.

> 📌 **Exam note:** A Lambda that catches all its own exceptions and returns an error
> payload will show **0 Errors** in CloudWatch even though users are seeing failures.
> This is why you also alarm on application-level signals, not just `Errors`.

### Step 2.3 — The processor function (the async-retry lesson)

1. Switch the graph to the **processor** function.
2. Graph `Invocations` and `Errors`.
3. You sent **2** `processor-fail` orders — but you should see **6** invocations and
   **6** errors.

**Why:** EventBridge → Lambda is an **asynchronous** invocation. Async failures are
**retried twice by default** (3 attempts total). 3 × 2 events = 6.

> 📌 **Exam note — sync vs async retries:**
> - **Synchronous** (API Gateway, ALB, direct SDK invoke): NO automatic retries. The
>   caller gets the error and decides what to do.
> - **Asynchronous** (EventBridge, S3 events, SNS): Lambda retries **2×** by default,
>   with delays (~1 min, then ~2 min). After the last failure the event is dropped
>   **unless** you configured a **DLQ** or an **on-failure destination**.
> - **Stream/poll-based** (Kinesis, DynamoDB Streams, SQS): the event-source mapping
>   governs retries, and a poison message can block the shard until it expires.
>
> We deliberately left retries at the default and skipped the DLQ in Phase 1 — this
> is exactly why `Invocations` reads 3× here. In Phase 3 we add the DLQ.

> ✅ **Record in notes:** "Invocations is 3× what I expected" → the one-line answer is
> *async retries*. Write that down; it's a common troubleshooting question.

---

## 3. API Gateway — namespace `AWS/ApiGateway`

### Step 3.1 — Open the API metrics

1. **CloudWatch → Metrics → Classic metrics → Browse tab**.
2. Click namespace **ApiGateway** (`AWS/ApiGateway`) → dimension **By Api Name** →
   `cloudops-lab-dev-api`.
3. (There's also a "By Api Name, Stage, Method, Resource" grouping if you want
   per-route detail — note how **more dimensions = finer slicing**.)

### Step 3.2 — The five metrics from your task list

| Metric | Statistic | Expected | Why / what to notice |
|---|---|---|---|
| `Count` | **Sum** | ~28 | Every request, any outcome — including the 403s. The "how busy am I" metric. |
| `4XXError` | **Sum** | ~8 | Client errors: your 5 validation 400s **plus** the 3 no-key 403s. |
| `5XXError` | **Sum** | 5 | Server errors: the `item=fail` exceptions surfaced as 5XX. |
| `Latency` | **Average** then **p99** | tail near 5s | **Total** time API GW measured: integration time **+** API GW overhead. |
| `IntegrationLatency` | **Average** then **p99** | just under Latency | **Only** the backend (Lambda) time. |

> ✅ **Record in notes (two questions):**
> 1. The 403s showed as `4XXError` but Lambda `Invocations` did **not** include them.
>    What does that tell you about *where* API-key enforcement happens? (At the API GW
>    edge, before integration — so the backend is never invoked and you don't pay for
>    the Lambda.)
> 2. On the slow calls, `Latency ≥ IntegrationLatency` always. The difference is API
>    Gateway's own overhead (request/response mapping, auth checks, etc.).

> 📌 **Exam note — `Latency` vs `IntegrationLatency` is a frequent question:**
> - `IntegrationLatency` high + `Latency` ≈ `IntegrationLatency` → the **backend** is slow.
> - `Latency` high but `IntegrationLatency` low → the **API Gateway layer** (or
>   mapping/throttling) is adding the delay. Different root cause, different fix.

> 📌 **Exam note — statistics matter for latency:** latency metrics are
> **distributions**. Alarming on **Average** hides outliers; real monitoring uses
> **p90/p99**. Know that CloudWatch supports percentile statistics.

---

## 4. DynamoDB — namespace `AWS/DynamoDB`

### Step 4.1 — Open the table metrics

1. **CloudWatch → Metrics → Classic metrics → Browse tab**.
2. Click namespace **DynamoDB** (`AWS/DynamoDB`) → dimension **Table Metrics** →
   `cloudops-lab-dev-orders`.

| Metric | Expected after normal traffic | Why / what to notice |
|---|---|---|
| `ConsumedWriteCapacityUnits` | ≈ number of successful orders | Each happy-path order did one `PutItem`. |
| `ConsumedReadCapacityUnits` | ≈ 0 | The app only writes; it never reads. |
| `ThrottledRequests` | likely 0 so far | Spread-out writes don't exceed 1 WCU **per second**. |

> 📌 **Exam note — capacity is per-second:** provisioned 1 WCU means 1 write/sec of up
> to 1 KB. Ten writes over ten seconds = fine. Ten writes in the **same second** = 9
> throttled. The metric graph's **period** (1 min) sums the second-level activity, so
> to *see* throttling you must *cause* a within-second burst (next step).

### Step 4.2 — Force throttling (do this deliberately)

Run a tight parallel burst so multiple writes land in the same second:

```bash
API_URL=$(terraform -chdir=Cloudwatch/terraform output -raw api_url)
KEY=$(terraform -chdir=Cloudwatch/terraform show -json \
  | jq -r '.values.root_module.child_modules[]?.resources[]?
           | select(.type=="aws_api_gateway_api_key") | .values.value')

for i in $(seq 1 30); do
  curl -s -o /dev/null -X POST "$API_URL/orders" \
    -H "x-api-key: $KEY" -H "Content-Type: application/json" \
    -d '{"item":"widget","quantity":1}' &
done
wait
```

Wait ~2 minutes, then re-check:
- `ConsumedWriteCapacityUnits` — spikes well above 1.
- `WriteThrottleEvents` and/or `ThrottledRequests` — now **non-zero**.

> ✅ **Record in notes:** You'll likely see most requests still returned **200** even
> though DynamoDB threw throttling internally. Why? The AWS SDK (boto3) has **built-in
> retry with exponential backoff** for `ProvisionedThroughputExceededException`, so it
> silently retried and succeeded before your handler saw an error. To surface
> throttling to the *client* you'd disable/limit SDK retries or set a tight timeout.

> 📌 **Exam note — the two families of DynamoDB throttle metrics:**
> - `ThrottledRequests` — counts **requests** that were throttled (per table/operation).
> - `ReadThrottleEvents` / `WriteThrottleEvents` — counts **events** at a finer grain,
>   useful for spotting a **hot partition** (throttling even when total capacity looks OK).
> - Fixes the exam expects you to know: switch to **on-demand** billing, enable
>   **auto-scaling**, raise provisioned capacity, or redesign the **partition key** to
>   spread load.

---

## 5. EventBridge — namespace `AWS/Events`

### Step 5.1 — Open the rule metrics

1. **CloudWatch → Metrics → Classic metrics → Browse tab**.
2. Click namespace **Events** (`AWS/Events`) → dimension **By Rule Name** →
   `cloudops-lab-dev-order-created`.

| Metric | Expected | Why / what to notice |
|---|---|---|
| `Invocations` | ≈ one per `OrderCreated` event | The rule matched and fired its target. |
| `FailedInvocations` | non-zero if a target couldn't be invoked | **Delivery** failures to the target — distinct from the Lambda's own code errors. |
| `TriggeredRules` | ≈ matched events | How many times the rule pattern matched. |

> ✅ **Record in notes:** `FailedInvocations` (EventBridge) vs `Errors` (processor
> Lambda) count different things:
> - `FailedInvocations` = EventBridge **could not deliver** the event to the target
>   (e.g. permissions, target gone).
> - Lambda `Errors` = the event was delivered and the **function code** failed.
> A healthy rule can show `FailedInvocations = 0` while the Lambda shows many `Errors`.

---

## 6. (Optional) Force Lambda Throttles

To light up the Lambda `Throttles` metric from §2:

1. Temporarily set a **reserved concurrency** of 1 on the orders function
   (console: function → Configuration → Concurrency), **or** add it in Terraform via
   `reserved_concurrent_executions = 1`.
2. Fire the §4.2 parallel burst again.
3. Check `AWS/Lambda → orders → Throttles` — now non-zero, because concurrent requests
   exceeded the reserved limit of 1.

> 📌 **Exam note:** `Throttles` on Lambda = invocations rejected because the concurrency
> ceiling (account limit, or reserved concurrency) was hit. The fix is raising reserved
> concurrency or requesting an account limit increase. Don't confuse Lambda `Throttles`
> with DynamoDB/API Gateway throttling — same word, different services and dimensions.

---

## 7. Wrap-up — "What is happening to my system right now?"

By now you can read the whole system's health from built-in metrics alone:

- **Traffic:** API GW `Count`, Lambda `Invocations`.
- **Errors:** API GW `4XX`/`5XX`, Lambda `Errors`, EventBridge `FailedInvocations`.
- **Performance:** Lambda `Duration`, API GW `Latency` vs `IntegrationLatency` (p99).
- **Capacity pressure:** DynamoDB `Consumed*CapacityUnits`, `ThrottledRequests`;
  Lambda `Throttles`, `ConcurrentExecutions`.

### Checklist before Checkpoint 8

- [ ] Found all 5 Lambda metrics for the orders function.
- [ ] Confirmed `Errors` = 5 (handled 400s don't count) and explained why.
- [ ] Confirmed processor `Invocations` = 6 for 2 events and explained async retries.
- [ ] Compared `Latency` vs `IntegrationLatency` on slow requests.
- [ ] Confirmed 403s appear in API GW `4XXError` but not in Lambda `Invocations`.
- [ ] Forced DynamoDB throttling and saw `WriteThrottleEvents` / `ThrottledRequests`.
- [ ] Explained `FailedInvocations` (EventBridge) vs `Errors` (Lambda).

When those are ticked, move to **Checkpoint 8** and define, in your own words:
**metric**, **namespace**, **dimension**, **statistic**.

---

## Quick reference — namespaces & key metrics (exam cram)

| Namespace | Key metrics | Watch for |
|---|---|---|
| `AWS/Lambda` | Invocations, Errors, Duration, Throttles, ConcurrentExecutions, DeadLetterErrors | Errors ≠ handled non-200; async retries inflate Invocations |
| `AWS/ApiGateway` | Count, 4XXError, 5XXError, Latency, IntegrationLatency | Latency ≥ IntegrationLatency; key rejection = edge, no backend |
| `AWS/DynamoDB` | Consumed{Read,Write}CapacityUnits, ThrottledRequests, {Read,Write}ThrottleEvents | Capacity is per-second; hot partition vs total capacity |
| `AWS/Events` | Invocations, FailedInvocations, TriggeredRules, DeadLetterInvocations | Delivery failure ≠ target code failure |
