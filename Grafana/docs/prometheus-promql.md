# PromQL — Query Language Reference (CloudOps Exam Prep)

> A revisitable PromQL reference for querying AMP (and any Prometheus). Covers the data
> model, selectors, functions, aggregation, and worked examples. Run these in the Grafana
> query editor against the AMP data source, or AMP's query API.

---

## 0. The data model (everything builds on this)

A **time series** is identified by a **metric name** + a set of **labels**:

```
http_requests_total{method="POST", handler="/orders", instance="10.0.1.5:9090"}
```

- **Metric name** = what's measured (`http_requests_total`).
- **Labels** = key/value dimensions (method, handler, instance…). Labels are how you
  **filter** and **group**.
- **Sample** = a value + timestamp for that series.

**Metric types:**
| Type | Meaning | Typical use |
|---|---|---|
| **Counter** | monotonically increasing (resets to 0 on restart) | requests, errors, bytes — use with `rate()` |
| **Gauge** | goes up/down | temperature, memory, queue depth |
| **Histogram** | bucketed observations (`_bucket`,`_sum`,`_count`) | latency distributions → `histogram_quantile()` |
| **Summary** | client-side quantiles (`_sum`,`_count`,quantile) | pre-computed percentiles |

> 📌 **Exam angle:** **counters** are rising totals — you almost always wrap them in
> `rate()`; graphing a raw counter is meaningless. **Gauges** you graph directly.
> **Histograms** → `histogram_quantile()` for p95/p99.

---

## 1. Selectors & matchers

```promql
http_requests_total                              # all series with this name
http_requests_total{method="POST"}               # exact label match
http_requests_total{method!="GET"}               # negate
http_requests_total{handler=~"/orders.*"}        # regex match
http_requests_total{handler!~"/health"}          # regex negate
```

**Range vs instant vectors:**
- **Instant vector** — one sample per series at a point in time: `http_requests_total`.
- **Range vector** — a window of samples: `http_requests_total[5m]` (needed by `rate()` etc.).

> 📌 **Exam angle:** `=`, `!=`, `=~`, `!~` are the four matchers. `[5m]` makes a **range
> vector** — required for rate/increase functions.

---

## 2. Rate & counters

```promql
rate(http_requests_total[5m])        # per-second avg rate over 5m (handles resets)
irate(http_requests_total[5m])       # instantaneous rate (last 2 samples) — spiky
increase(http_requests_total[1h])    # total increase over 1h (= rate * seconds)
```

> 📌 **Exam angle:** `rate()` = smoothed per-second rate (use for dashboards/alerts);
> `irate()` = instantaneous (volatile, for fast-moving graphs); `increase()` = absolute
> count over a window. All require a **counter** + range vector.

---

## 3. Aggregation operators

Collapse many series into fewer, by label:

```promql
sum(rate(http_requests_total[5m]))                       # total across everything
sum by (handler) (rate(http_requests_total[5m]))         # one line per handler
avg by (instance) (node_memory_usage_bytes)              # avg per instance
max by (job) (up)                                        # per job
count(up == 1)                                           # how many targets are up
topk(3, sum by (handler) (rate(http_requests_total[5m])))# top 3 handlers
```

Operators: `sum, avg, min, max, count, stddev, topk, bottomk, quantile`.
Modifiers: **`by (labels)`** (keep these labels) / **`without (labels)`** (drop these).

> 📌 **Exam angle:** aggregation + **`by` / `without`** is the heart of PromQL. `by (x)` =
> group by x; `without (x)` = aggregate away x. `topk`/`bottomk` for ranking.

---

## 4. Histograms & percentiles

```promql
histogram_quantile(0.95,
  sum by (le) (rate(http_request_duration_seconds_bucket[5m])))   # p95 latency
```

> 📌 **Exam angle:** latency SLOs → `histogram_quantile()` over the `_bucket` series,
> aggregated **`by (le)`** (the bucket boundary label). p95/p99 come from here.

---

## 5. Math, comparison & logical ops

```promql
# error ratio
sum(rate(http_requests_total{code=~"5.."}[5m]))
  / sum(rate(http_requests_total[5m]))

# memory used %
100 * (1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)

# filter: only series breaching a threshold
node_cpu_utilization > 80

# logical: series present in A and B
up == 1 and on(instance) node_cpu_utilization > 80
```

> 📌 **Exam angle:** vector math matches on **identical label sets**; use `on()` / `ignoring()`
> + `group_left`/`group_right` for many-to-one joins. Comparisons **filter** (keep breaching
> series) unless you add `bool`.

---

## 6. Common real-world queries

```promql
# Targets down
up == 0

# Per-pod CPU cores (from cAdvisor), top 5
topk(5, sum by (pod) (rate(container_cpu_usage_seconds_total[5m])))

# Node memory pressure (%)
100 * (1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)

# 5xx error rate per service
sum by (service) (rate(http_requests_total{status=~"5.."}[5m]))

# Disk filling up: predict seconds until full (linear)
predict_linear(node_filesystem_free_bytes[1h], 4*3600) < 0

# Across clusters (multi-cluster via external_labels)
sum by (cluster) (rate(http_requests_total[5m]))
```

> 📌 **Exam angle:** `up` = scrape health; `predict_linear()` for capacity/trend alerts;
> grouping `by (cluster)` leverages the `external_labels` you set per cluster.

---

## 7. Query optimization in PromQL

- Prefer **recording rules** for expensive expressions you graph/alert on repeatedly.
- **Narrow the selector** (more labels) and the **range** — big `[1d]` windows over
  high-cardinality metrics are slow.
- Avoid unnecessary **regex** matchers and huge **`by`** groupings (cardinality explosions).
- Use **`rate` over a sensible window** (≥ 4× scrape interval) for stable results.

> 📌 **Exam angle:** performance = **recording rules + tight selectors + bounded ranges +
> low cardinality**. Same themes as the Grafana query-optimization section.

---

## Quick-recall cheat sheet

| Need | PromQL |
|---|---|
| Per-sec rate of a counter | `rate(metric[5m])` |
| Total over a window | `increase(metric[1h])` |
| Group sum by a label | `sum by (label) (rate(metric[5m]))` |
| Top N | `topk(N, …)` |
| p95 latency | `histogram_quantile(0.95, sum by (le)(rate(..._bucket[5m])))` |
| Error ratio | `sum(rate(err[5m])) / sum(rate(total[5m]))` |
| Only breaching series | `metric > threshold` |
| Scrape health | `up == 0` |
| Trend/predict | `predict_linear(metric[1h], horizon)` |
| Per cluster | `sum by (cluster) (…)` (needs external_labels) |
| Counter vs gauge? | counter → `rate()`; gauge → graph directly |
