# AWS X-Ray — Concept Reference (CloudOps Exam Prep)

> A revisitable reference for the *conceptual* half of the X-Ray objectives — the things
> you need to **explain**, not just click. Pair it with `xray-walkthrough.md` for the
> hands-on part.
>
> This lab instruments the Phase 1 Order Processing Platform (API Gateway → Orders Lambda
> → DynamoDB → EventBridge → Processor Lambda). References to "our handlers/modules" point
> at `Cloudwatch/`.

---

## 0. What X-Ray is (and how it differs from CloudWatch)

X-Ray is a **distributed tracing** service. It follows a single request as it travels
across services and records **where the time went** and **where it failed**. It answers:

- *"This request was slow — which hop/call caused it?"*
- *"This request failed — which service, and was it my fault or a dependency's?"*
- *"What does my application's topology actually look like under load?"*

### X-Ray vs CloudWatch vs CloudTrail (know this cold)

| Service | Core question | Unit |
|---|---|---|
| **CloudWatch** | *Is my system healthy / performant in aggregate?* | metric / log |
| **X-Ray** | *For THIS request, where did time go and where did it fail?* | trace (segments) |
| **CloudTrail** | *Who made which API call?* | event |

> 📌 **Exam framing:** CloudWatch tells you *latency p99 is up*. X-Ray tells you *it's the
> DynamoDB call inside the Orders function on slow requests*. CloudWatch = aggregate
> health; X-Ray = per-request anatomy. They complement each other (ServiceLens ties them
> together — see §9).

---

## 1. The data model — trace, segment, subsegment

| Term | What it is |
|---|---|
| **Trace** | All data for **one request** as it crosses services. Identified by a **trace ID**. |
| **Segment** | The work done by **one service/resource** for that request (e.g. the Orders Lambda's segment). The unit each service emits. |
| **Subsegment** | A finer slice **inside** a segment — e.g. the DynamoDB `PutItem` call, or our explicit `artificial-delay`. This is where you see *what inside the function* took time. |

```
Trace  (one request, one trace ID)
 ├── Segment: API Gateway
 ├── Segment: Orders Lambda
 │     ├── Subsegment: DynamoDB PutItem      (auto, from patch_all)
 │     ├── Subsegment: EventBridge PutEvents  (auto, from patch_all)
 │     └── Subsegment: artificial-delay       (manual, our code)
 └── Segment: Processor Lambda  (continued across the async hop)
```

### Trace ID format
`1-<8 hex: start time epoch>-<24 hex: random>` — e.g. `1-581cf771-a006649127e371903a2de979`.

> 📌 **Exam angle:** "segment vs subsegment" — a **segment** = one service's slice of the
> trace; a **subsegment** = a timed operation *within* that service (a downstream call or
> a code block). Subsegments are what pinpoint bottlenecks.

---

## 2. Annotations vs metadata (both attach to segments)

| | **Annotations** | **Metadata** |
|---|---|---|
| Indexed / searchable | **Yes** — filter traces by them | No |
| Use for | key-value you want to **query** (e.g. `item=slow`, `order_id=...`) | extra context, not searchable |
| Limits | up to 50 annotations/trace, simple scalar values | larger/arbitrary objects |

Our handlers add annotations like `item`, `order_id`, `upstream_trace_id`, `delay_seconds`
so you can filter traces in the console (e.g. `annotation.item = "slow"`).

> 📌 **Exam angle:** want to **filter/group traces** by a business value → **annotation**.
> Just want to attach debugging context you'll read manually → **metadata**.

---

## 3. Sampling — why not every request is traced

Tracing every request is expensive and unnecessary. X-Ray **samples**:

- **Default reservoir + rate:** record the **first request each second** (the reservoir),
  plus **5%** of additional requests. This guarantees representation without full volume.
- **Custom sampling rules:** change rate/reservoir per service, URL path, HTTP method,
  etc. (e.g. trace 100% of `/checkout`, 1% of `/health`).
- Sampling decision is made **once at the start** and propagated via the trace header
  (`Sampled=1/0`) so every downstream service makes the **same** decision — a request is
  traced consistently end-to-end or not at all.

> 📌 **Exam angle:** "we're not seeing all requests in X-Ray" → **sampling** (default is
> 1/sec + 5%, not 100%). To trace more of a specific path, add a **custom sampling rule**.
> "costs too high" → reduce sampling. The reservoir+rate model is a classic question.

---

## 4. The service map

The **service map** is X-Ray's visual topology: **nodes** (services/resources) connected
by **edges** (calls between them), built from aggregated trace data.

Reading a node:
- **Size of the circle** ∝ traffic (number of traced requests).
- **Color ring** shows health: **green** = OK, **red** = faults (5xx), **yellow** =
  errors (4xx), **purple** = throttles (429).
- Click a node/edge → latency distribution, response-code breakdown, and a jump to the
  underlying traces.

In our app you'll see: `Client → API Gateway → Orders Lambda → DynamoDB`, plus the
`Orders Lambda → EventBridge` edge and the `Processor Lambda` node.

> 📌 **Exam angle:** the service map is the **first stop** to triage "something's wrong" —
> a red node localizes the fault to a service in one glance, before you open individual
> traces.

---

## 5. Errors vs Faults vs Throttles (precise X-Ray meanings)

X-Ray classifies non-success by HTTP-status family — memorize this:

| X-Ray term | HTTP | Meaning |
|---|---|---|
| **Error** | **4xx** | Client-side issue (bad request, validation) |
| **Fault** | **5xx** | Server-side issue (unhandled exception, dependency failure) |
| **Throttle** | **429** | Rate/throughput limit hit (subset, called out separately) |

Mapping to our deliberate scenarios:
- `item` missing → 400 → **Error** (4xx).
- `item=fail` → unhandled exception → 500 → **Fault** (5xx).
- Exceed API GW usage-plan rate → 429 → **Throttle**.

> 📌 **Exam angle:** **Error = 4xx (client), Fault = 5xx (server), Throttle = 429.** This
> exact vocabulary appears in questions. A spike in **faults** points at your code or a
> dependency; a spike in **errors** points at callers sending bad requests.

---

## 6. Finding performance bottlenecks (the trace timeline)

Open a single trace → the **timeline** shows each segment/subsegment as a horizontal bar,
positioned and sized by *when* and *how long*.

Worked example — a `slow` request in our app:
- The **Orders Lambda** segment is long (~5s).
- Expanding it, the `artificial-delay` **subsegment** is the long bar — not the DynamoDB
  or EventBridge subsegments (which are milliseconds).
- Conclusion: the time is in that code block, not a downstream call.

Contrast — if DynamoDB were throttling, the **DynamoDB subsegment** would be the long/red
bar instead. Same timeline, different culprit, instantly visible.

> 📌 **Exam angle:** bottleneck hunting = open the trace → find the **longest subsegment**.
> Latency *in a subsegment that is a downstream call* → the dependency is slow. Latency
> *in your own code block* → your function. The timeline makes "where did the time go"
> literal.

---

## 7. X-Ray Insights (anomaly detection)

**Insights** continuously analyzes trace data and flags **anomalies** — e.g. a sustained
rise in **fault rate** on a node versus its baseline — and tracks the incident over time
(start, impact, root-cause service). Enable it per group.

> 📌 **Exam angle:** "automatically detect and get notified about unusual error/fault
> patterns in a distributed app" → **X-Ray Insights** (can notify via EventBridge). It's
> the X-Ray analogue of CloudTrail Insights, but for trace faults/latency.

---

## 8. Tracing across boundaries — sync vs async, the trace header

X-Ray propagates context via the **trace header** `X-Amzn-Trace-Id`:
```
Root=1-5759e988-...;Parent=53995c3f42cd8ad8;Sampled=1
```

- **Synchronous calls** (API GW → Lambda → SDK call): the header is passed automatically
  by the instrumented services/SDK. The trace stays connected with no extra work.
- **Asynchronous hops** (EventBridge, SQS, SNS, S3 events): the trace header is **not**
  automatically carried into the event payload to the consumer. If you do nothing, the
  consumer starts a **separate** trace.

Our lab demonstrates the fix: the Orders Lambda copies the trace header into the event
`Detail` (`_xray_trace`); the Processor reads it back and records it, so the async work is
correlated to the originating request.

> 📌 **Exam angle:** "my trace breaks / the downstream Lambda shows as a separate trace
> after an SQS/EventBridge hop" → async boundaries don't auto-propagate the trace header;
> you must **pass it in the message and continue the trace** on the consumer side.

---

## 9. Integrations (how X-Ray connects to the rest)

| Integration | How tracing happens |
|---|---|
| **API Gateway** | Enable **active tracing** on the stage; API GW becomes the first node |
| **Lambda** | **Active tracing** (`tracing_config = Active`) + `AWSXRayDaemonWriteAccess`; the runtime runs the X-Ray daemon for you |
| **SDK auto-instrumentation** | `patch_all()` turns every boto3 call into a subsegment |
| **ECS / EC2 / on-prem** | run the **X-Ray daemon** sidecar/process; app sends segments to it over UDP 2000 |
| **CloudWatch ServiceLens** | ties X-Ray traces + CloudWatch metrics + logs into one view |
| **EventBridge / SNS** | X-Ray **Insights** can send anomaly notifications |

### Where ADOT (AWS Distro for OpenTelemetry) fits
AWS's strategic direction is **OpenTelemetry**. **ADOT** is AWS's supported OTel
distribution; on Lambda it's delivered as a **layer** plus the
`AWS_LAMBDA_EXEC_WRAPPER=/opt/otel-instrument` env var, giving **auto-instrumentation**
without SDK code. OTel can **export to X-Ray** (so the service map/traces still work) and,
unlike the X-Ray SDK, is **vendor-neutral** (same instrumentation can target other
backends).

> 📌 **Exam / real-world angle:** the classic **`aws-xray-sdk`** (what we used) is simplest
> and still the dominant exam vocabulary (segments/subsegments/sampling). **ADOT/OTel** is
> the forward-looking choice when you want vendor-neutral instrumentation or a unified
> metrics+traces+logs pipeline. Know that OTel uses *spans* (≈ X-Ray segments/subsegments)
> and can export to X-Ray.

---

## Quick-recall cheat sheet

| Question | One-line answer |
|---|---|
| Aggregate latency vs per-request anatomy? | CloudWatch (aggregate) vs **X-Ray** (per request) |
| Segment vs subsegment? | Segment = one service's slice; subsegment = a timed op inside it |
| Filter traces by a business value? | **Annotation** (indexed); metadata is not searchable |
| Why aren't all requests traced? | **Sampling** — default 1 req/sec + 5%; add custom rules for more |
| First stop to triage a problem? | **Service map** — red node localizes the fault instantly |
| Error vs Fault vs Throttle? | 4xx client / 5xx server / 429 rate-limit |
| Where did the time go? | Open the trace → longest **subsegment** on the timeline |
| Auto-detect unusual fault patterns? | **X-Ray Insights** (notify via EventBridge) |
| Trace broke after SQS/EventBridge hop? | Async doesn't auto-propagate the header; pass it in the message |
| Trace EC2/ECS/on-prem apps? | Run the **X-Ray daemon**; app sends segments over UDP 2000 |
| Vendor-neutral / future direction? | **ADOT (OpenTelemetry)** — layer + wrapper on Lambda, exports to X-Ray |
| One view of traces + metrics + logs? | CloudWatch **ServiceLens** |
