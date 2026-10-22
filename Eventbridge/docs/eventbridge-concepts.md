# Amazon EventBridge — Concept Reference (CloudOps Exam Prep)

> A revisitable reference for the *conceptual* half of the EventBridge objectives — the
> things you need to **explain**, not just click. Pair it with `eventbridge-walkthrough.md`
> for the hands-on part.
>
> This lab's EventBridge setup is in `Eventbridge/terraform/`. References to "our module"
> point there.

---

## 0. What EventBridge is

EventBridge is a **serverless event bus**: a routing layer that receives **events**,
matches them against **rules**, and delivers matching events to **targets**. It's the glue
for **event-driven** and **auto-healing** architectures — "when X happens, do Y" without
polling or custom plumbing.

```
Producer → Event Bus → Rule (event pattern) → Target(s)
 (AWS service,        (default / custom /     (filters)   (Lambda, SNS, SQS, SSM,
  your app, SaaS)      partner)                            Step Functions, another bus,
                                                           API destination, ...)
```

---

## 1. Events — the unit of currency

An **event** is a JSON document with a standard **envelope** plus a free-form payload:

```json
{
  "version": "0",
  "id": "7bf73129-...",
  "detail-type": "OrderPlaced",
  "source": "myapp.orders",
  "account": "123456789012",
  "time": "2026-10-06T12:34:56Z",
  "region": "eu-central-1",
  "resources": ["arn:aws:ec2:...:instance/i-0abc"],
  "detail": { "order_id": "abc-123", "amount": 150 }
}
```

- **`source`** — who produced it. AWS services use `aws.<service>` (e.g. `aws.ec2`); you
  choose your own for custom events (e.g. `myapp.orders`). `aws.` is reserved for AWS.
- **`detail-type`** — human label for the kind of event.
- **`detail`** — the payload (arbitrary JSON).
- **`resources`** — ARNs the event concerns (e.g. the EC2 instance).

> 📌 **Exam angle:** `source` + `detail-type` are the fields you match on most. For AWS
> service events you can only match the values AWS assigns; for custom events you set them.

---

## 2. Event buses — default, custom, partner

| Bus | Receives |
|---|---|
| **Default** | **AWS service events** (automatic) + custom `PutEvents` with no bus specified |
| **Custom** | Your application's events (you create the bus and send to it) |
| **Partner** | Events from SaaS partners (via a partner event source) |

> 📌 **Exam trap:** **AWS service events (`aws.*`) are delivered ONLY to the default bus.**
> A rule matching `aws.ec2` on a *custom* bus will never fire. Our pattern-demo rules live
> on a custom bus (custom events we send); our auto-heal + alarm rules live on the
> **default** bus (because they match AWS service/alarm events).

---

## 3. Rules & event-pattern matching

A **rule** = an **event pattern** + the bus it watches + the **targets** to deliver to.

### How patterns match
- A pattern mirrors the event's JSON shape.
- Each named field lists **acceptable values in an array**; the event matches if its value
  is in the array.
- **Omitted fields** = don't care. **All named fields must match** (implicit AND).

### Content filter operators (beyond exact match)
| Operator | Example | Matches |
|---|---|---|
| exact | `"source": ["myapp.orders"]` | equals the string |
| **prefix** | `[{"prefix": "eu-"}]` | starts with `eu-` |
| **suffix** | `[{"suffix": ".jpg"}]` | ends with `.jpg` |
| **anything-but** | `[{"anything-but": ["ok"]}]` | any value except `ok` |
| **numeric** | `[{"numeric": [">", 100]}]` | number > 100 |
| **exists** | `[{"exists": true}]` | field is present |
| **cidr** | `[{"cidr": "10.0.0.0/24"}]` | IP in range |
| **equals-ignore-case** | `[{"equals-ignore-case": "ERROR"}]` | case-insensitive |
| **$or** | `{"$or": [ {...}, {...} ]}` | either sub-pattern |

> 📌 **Exam angle:** know prefix / anything-but / numeric / exists cold — they're the
> common ones. Patterns are **AND across fields, OR within a field's array**.

### Rules vs the old "event rules" split
EventBridge rules can be **event-pattern** based (react to events) or **schedule** based
(cron/rate). For scheduled workloads at scale, **EventBridge Scheduler** is the newer,
dedicated service (one-time + recurring, millions of schedules). Know it exists.

---

## 4. Targets & input transformation

A rule can have **up to 5 targets**. Common target types:
- **Lambda, SNS, SQS, Step Functions, Kinesis**
- **SSM Automation / Run Command** (auto-healing — see §6)
- **Another event bus** (cross-account/-Region — see §7)
- **API destination** (external HTTP endpoint — see §8)
- CloudWatch Logs, ECS tasks, and more.

**Input transformation** lets you reshape the event before it reaches the target:
- `input_paths` extracts values from the event (JSONPath).
- `input_template` builds the payload the target receives.

Our auto-heal uses this to pull `$.detail.instance-id` and pass it as the SSM runbook's
`InstanceId` parameter.

> 📌 **Exam angle:** targets can get the **raw event**, a **constant**, a **single JSONPath
> value**, or a **transformed** payload (input transformer). SSM/Step Functions targets
> usually need a transformed input to match the API's expected parameters.

---

## 5. Respond to AWS service changes + CloudWatch alarm integration

Two distinct triggers for the same remediation (both in our lab):

1. **Direct AWS service event** — a rule matches the raw event (e.g. `aws.ec2`
   status-check / state-change). Fast, fires on the event itself.
2. **CloudWatch alarm state change** — a CloudWatch **alarm's state change is itself an
   event** (`source: aws.cloudwatch`, `detail-type: "CloudWatch Alarm State Change"`). A
   rule matches the alarm entering `ALARM`. Slower but **debounced** — the alarm only
   changes state after the condition persists across evaluation periods, filtering out
   transient blips.

> 📌 **Exam trap:** you do **not** wire an alarm "action" into EventBridge. The alarm just
> changes state; EventBridge listens for that **state-change event** like any other. Direct
> event = reflexive/fast; alarm-driven = deliberate/debounced. Both can drive the same
> SSM remediation.

---

## 6. Auto-healing with SSM Automation (the two-role model)

Pattern: unhealthy resource event → rule → **SSM Automation document** → fix.

**Two IAM roles, do not confuse them:**
| Role | Who uses it | Purpose |
|---|---|---|
| **EventBridge invoke role** (`role_arn` on the target) | EventBridge | `ssm:StartAutomationExecution` + `iam:PassRole` |
| **AutomationAssumeRole** | SSM Automation | the permissions to perform the fix (e.g. `ec2:RebootInstances`) |

Resilience knobs on the target (your "monitor/troubleshoot" objective):
- **DLQ** (`dead_letter_config`) — captures events EventBridge couldn't deliver to the target.
- **retry_policy** — `maximum_retry_attempts`, `maximum_event_age_in_seconds`.

> 📌 **Exam angle:** SSM Automation is the standard **action layer** — Config, EventBridge,
> and CloudWatch alarms are all just **triggers** for it. The `iam:PassRole` on the invoke
> role (scoped to `ssm.amazonaws.com`) is what lets EventBridge hand the AutomationAssumeRole
> to SSM.

---

## 7. Cross-account & cross-Region event buses

Mechanism: **make another event bus the target of a rule.**
- **Source side:** a rule whose target is the destination **bus ARN**, plus an **IAM role**
  EventBridge assumes to call `events:PutEvents` on it.
- **Destination side:** a **resource policy** on the bus allowing the source
  account/region to `PutEvents`.
- The destination bus then runs **its own rules** on the forwarded events.

Cross-Region and cross-account are the **same shape** — only the destination bus policy's
principal differs (same account for cross-Region; another account ARN for cross-account).

> 📌 **Exam angle:** centralize events from many accounts/Regions into one "central event
> bus" account → each source forwards via a rule+role; the central bus policy trusts the
> source accounts. This is the common multi-account observability/governance pattern.

---

## 8. API destinations (route to EXTERNAL systems) — concept only

An **API destination** sends matching events to an **external HTTP(S) endpoint** (SaaS,
webhook, on-prem API) — a target type for things *outside* AWS.

Two pieces:
1. **Connection** — holds the **auth** (Basic, API key header, or OAuth). Credentials are
   stored in Secrets Manager behind the scenes.
2. **API destination** — the **endpoint URL + HTTP method** + a reference to the
   connection + an **invocation rate limit**.

A rule targets the API destination; on match, EventBridge makes the outbound HTTPS call
with the event as the body and the connection's auth attached.

```
AWS event → rule → API destination (POST https://...) → external system
                        └── Connection (auth: API key / Basic / OAuth)
```

> 📌 **Exam angle:** API destinations = EventBridge calling **out** to third-party/HTTP
> endpoints, with managed **auth (Connection)** and **rate limiting / retries**. Use them
> instead of writing a Lambda just to call a webhook. (We cover this conceptually; it's not
> deployed in the lab.)

---

## 9. Troubleshooting & monitoring workflows

| Symptom | Where to look / fix |
|---|---|
| Rule doesn't fire | event isn't reaching the bus; pattern doesn't match; **AWS event on a custom bus** (must be default) |
| Rule fires but target not invoked | missing **target permission** (resource policy for Lambda, or `role_arn` for SSM/bus/Kinesis) |
| Target intermittently fails | check the **DLQ**; tune **retry_policy** |
| Need to see what matched | route to a **log target** / CloudWatch Logs and inspect |
| Metrics | **CloudWatch `AWS/Events`**: `Invocations`, `FailedInvocations`, `ThrottledRules`, `MatchedEvents`, `DeadLetterInvocations` |
| Archive/replay | **EventBridge Archive + Replay** to re-process past events |

> 📌 **Exam angle:** `FailedInvocations` > 0 → delivery/permission problem (check DLQ +
> target policy). `MatchedEvents` = 0 → the **pattern** or **bus** is wrong, not the target.
> **Archive + Replay** is the feature for reprocessing historical events.

---

## 10. EventBridge vs other eventing (disambiguation)

| Need | Service |
|---|---|
| Route/filter events by content to many target types | **EventBridge** |
| Simple pub/sub fan-out, high throughput, SMS/email/HTTP | **SNS** |
| Durable queue, decouple producer/consumer, one consumer group | **SQS** |
| Scheduled jobs at scale (cron/rate) | **EventBridge Scheduler** |
| Ordered streaming, replay by offset, analytics | **Kinesis** |

> 📌 **Exam angle:** EventBridge shines at **content-based routing + AWS/SaaS event sources
> + many target types**. SNS is simpler fan-out; SQS is a buffer/queue; pick by the
> routing/filtering/ordering need.

---

## Quick-recall cheat sheet

| Question | One-line answer |
|---|---|
| Where do AWS service events go? | the **default** bus only (never custom) |
| Match "field starts with X"? | `[{"prefix":"X"}]` content filter |
| Pattern logic? | AND across fields, OR within a field's array |
| How many targets per rule? | up to **5** |
| Reshape event for a target? | **input transformer** (`input_paths` + `input_template`) |
| Alarm → remediation wiring? | alarm **state change is an event**; rule matches it (not an "action") |
| Auto-heal action layer? | **SSM Automation** doc, with EventBridge-invoke role + AutomationAssumeRole |
| Forward events to another account/Region? | make the other **bus the target** (role on source, resource policy on dest) |
| Call an external webhook/SaaS? | **API destination** (+ Connection for auth) |
| Rule fires but nothing happens? | missing **target permission** / check **DLQ** |
| MatchedEvents = 0? | wrong **pattern** or wrong **bus** |
| Reprocess past events? | **Archive + Replay** |
| Scheduled jobs at scale? | **EventBridge Scheduler** |
