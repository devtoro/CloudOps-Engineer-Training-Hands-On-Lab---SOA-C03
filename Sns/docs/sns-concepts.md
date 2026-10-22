# Amazon SNS — Concept Reference (CloudOps Exam Prep)

> Reference for the SNS objectives. This lab is **deployable** (`Sns/terraform/`) — topics,
> subscriptions with filtering + DLQ, and an HTTP/S retry policy. Pair with
> `sns-walkthrough.md` for hands-on. Content rephrased from AWS docs for licensing
> compliance.

---

## 0. What SNS is

SNS is managed **pub/sub** messaging. **Publishers** send a message to a **topic**;
SNS **fans it out** to all matching **subscribers**. Decouples producers from consumers.

```
publisher → TOPIC → [filter] → subscriber 1 (SQS)
                   → [filter] → subscriber 2 (Lambda)
                   → [filter] → subscriber 3 (HTTP/S, email, SMS, …)
                                    │ (on failure, after retries)
                                    ▼ DLQ (SQS)
```

> 📌 **Exam framing:** SNS = **push** fan-out to many subscribers (one-to-many). SQS =
> **pull** queue (one consumer group). The **SNS→SQS fan-out** pattern (topic with multiple
> SQS subscribers) is a staple.

---

## 1. Topics — standard vs FIFO

| | **Standard** | **FIFO** |
|---|---|---|
| Ordering | best-effort | strict, within a **message group** |
| Delivery | at-least-once | exactly-once (dedup) |
| Throughput | very high | lower (ordered) |
| Name | any | must end **`.fifo`** |
| Subscribers | SQS, Lambda, HTTP/S, email, SMS, mobile push | **FIFO SQS only** |
| Needs | — | `MessageGroupId` (+ dedup id or content-based dedup) |

> 📌 **Exam angle:** need **ordering + no duplicates** → **FIFO** topic → **FIFO SQS**
> subscribers, `.fifo` names, `MessageGroupId`. Otherwise standard for scale/flexibility.

---

## 2. Securing topics & messages

- **Encryption at rest:** **SSE with a KMS key**. The KMS **key policy must grant the SNS
  service** `kms:GenerateDataKey*`/`Decrypt`, and so must the publishing services — a
  missing grant = publishes fail silently. (Same gotcha family as CloudTrail/Config.)
- **Encryption in transit:** SNS endpoints are HTTPS; enforce it with a topic policy
  statement that **Denies** `aws:SecureTransport = false`.
- **Access control:** the **topic access policy** (resource policy) controls who can
  `Publish`/`Subscribe` — scope to specific principals/service ARNs (`aws:SourceArn`).
- **VPC:** reach SNS privately via a **VPC interface endpoint** (PrivateLink).

> 📌 **Exam angle:** three security layers — **KMS** (at rest, needs key-policy grant for
> SNS), **HTTPS/TLS deny** (in transit), **topic policy** (who can publish/subscribe). A
> cross-account publisher is granted via the topic policy + `aws:SourceArn`/`SourceAccount`.

---

## 3. Integrating with AWS services

- **Publishers:** CloudWatch **alarms**, EventBridge rules, Config, S3 events, Budgets,
  CodePipeline, Lambda, and anything calling `Publish`.
- **Subscribers (protocols):** **SQS, Lambda, HTTP/S, email, email-JSON, SMS, mobile push,
  Kinesis Data Firehose**.
- The common CloudOps chain you've seen: **alarm/finding → SNS → (SQS/Lambda/EventBridge)**
  → notification or automated remediation.

> 📌 **Exam angle:** SNS is the **notification hub** — most AWS "notify me" features publish
> to a topic, and you fan out to the right consumers/protocols.

---

## 4. Message filtering & message attributes

- Publishers attach **message attributes** (key/value, e.g. `category=orders`,
  `severity=high`).
- Each subscription can have a **filter policy** — it only receives messages whose
  attributes match. One publish, many subscribers, each getting a filtered slice (no
  publisher-side routing logic).
- **Filter scope:**
  - **MessageAttributes** (default) — match on attributes.
  - **MessageBody** (`FilterPolicyScope=MessageBody`) — match on the JSON **payload** itself.
- Matching supports exact, `anything-but`, numeric ranges, prefix, `exists`, etc. (like
  EventBridge patterns).

> 📌 **Exam angle:** filtering moves routing **into SNS** — subscribers self-select via
> **filter policies** on **message attributes** (or body). "Fan out but each consumer only
> gets its slice" → filter policies, no extra topics needed.

---

## 5. Dead-letter queues (DLQ)

- A **DLQ** is an **SQS queue** attached to a **subscription** via its **redrive policy**.
  It captures messages SNS **couldn't deliver to that subscriber** after exhausting
  retries.
- **Per-subscription, not per-topic** — each subscriber has its own failure sink.
- Causes of undeliverable messages: subscriber throttling/errors, deleted endpoint,
  permission problems, client (4xx) or server (5xx) errors on HTTP/S.

> 📌 **Exam angle:** SNS DLQ = **SQS queue on the subscription (redrive policy)**, capturing
> post-retry failures. It's set **per subscription**. (SQS also has its own DLQs for its
> consumers — different thing; don't conflate.)

---

## 6. Delivery retries & backoff

SNS retries failed deliveries. For **HTTP/S** endpoints you can **customize** this with a
**delivery policy** (`healthyRetryPolicy`); AWS-managed endpoints (SQS, Lambda, email) use
fixed built-in retry behavior you don't tune the same way.

**The four retry phases** (HTTP/S delivery policy):
1. **Immediate retry (no delay)** — `numNoDelayRetries`.
2. **Pre-backoff** — `numMinDelayRetries` at `minDelayTarget`.
3. **Backoff** — remaining retries scaled by `backoffFunction` between min and max delay.
4. **Post-backoff** — `numMaxDelayRetries` at `maxDelayTarget`.

- `backoffFunction`: **linear | geometric | exponential**.
- `throttlePolicy.maxReceivesPerSecond` self-throttles delivery; throttled messages are
  **re-queued without consuming retry attempts**.

> 📌 **Exam angle:** custom retry/backoff = **HTTP/S only**, via the delivery policy's four
> phases + `backoffFunction`. Throttling re-queues and does **not** burn retries. After all
> retries fail → the message goes to the subscription's **DLQ** (if configured).

---

## 7. Monitoring & troubleshooting

Key **CloudWatch metrics** (namespace `AWS/SNS`, dimension `TopicName`):
- `NumberOfMessagesPublished`, `NumberOfNotificationsDelivered`.
- **`NumberOfNotificationsFailed`** — deliveries that failed.
- **`NumberOfNotificationsRedrivenToDlq`** — messages moved to the DLQ.
- **`NumberOfNotificationsFailedToRedriveToDlq`** — couldn't even reach the DLQ (e.g. DLQ
  policy wrong) — a serious signal.
- `NumberOfNotificationsFilteredOut*` — filtered out (incl. no/invalid attributes).

For the **DLQ depth**, alarm on the SQS metric **`ApproximateNumberOfMessagesVisible`**
(our lab's alarm). Note: SQS `NumberOfMessagesSent` is **not** suitable for DLQ alarms.

> 📌 **Exam triage:** `NumberOfNotificationsFailed` rising → delivery problem (endpoint
> down, perms). DLQ filling (`ApproximateNumberOfMessagesVisible > 0`) → messages exhausted
> retries. `FailedToRedriveToDlq > 0` → the **DLQ itself** is misconfigured (queue policy).
> `FilteredOut-NoMessageAttributes` → publisher forgot the attributes your filter needs.

---

## Quick-recall cheat sheet

| Question | One-line answer |
|---|---|
| SNS vs SQS? | SNS = push fan-out (1→many); SQS = pull queue (1 consumer group) |
| Ordering + dedup? | **FIFO** topic → FIFO SQS subscribers, `.fifo`, MessageGroupId |
| Encrypt at rest? | **KMS SSE** — key policy must grant SNS `GenerateDataKey*`/`Decrypt` |
| Enforce TLS? | topic policy **Deny** `aws:SecureTransport=false` |
| Route per subscriber? | **filter policy** on message attributes (or body) |
| Where's the DLQ set? | on the **subscription** (redrive policy) → SQS; per-subscription |
| Tune retry/backoff? | **HTTP/S only**, delivery policy `healthyRetryPolicy` (4 phases) |
| Backoff functions? | linear / geometric / exponential |
| Does throttling burn retries? | **No** — throttled messages re-queue |
| Key failed-delivery metrics? | `NumberOfNotificationsFailed`, `...RedrivenToDlq`, `...FailedToRedriveToDlq` |
| Alarm on DLQ depth? | SQS `ApproximateNumberOfMessagesVisible` (not NumberOfMessagesSent) |
| Cross-account publisher? | grant via **topic policy** + `aws:SourceArn`/`SourceAccount` |
