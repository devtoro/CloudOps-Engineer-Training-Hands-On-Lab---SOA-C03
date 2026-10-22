# Phase 1 — Notes & Concept Answers

Use this file to record your own observations as you explore CloudWatch, and your
answers to the concept checkpoint. Write them in your own words — the point is to be
able to explain these without looking them up.

---

## Concept Checkpoint

Answer these in your own words. We'll review them together at Checkpoint 8.

### 1. What is a metric?

> Information for a specific type of data needed (like number of requests, errors etc)

### 2. What is a metric namespace?

> Namespace in cloudwatch is a grouping of metrics, for a specific service of AWS (like API GW, Lambda etc)

### 3. What is a dimension?

> Dimension is another grouping, one level below the Namespace. It refers a specific instance of a service.

### 4. What is a statistic?

> Statistic is the value of a metric for a given time. It could also be an aggregation for a specifc metric, in correspondance to time.

--- Ignore observations

## Observations While Generating Traffic

### Successful requests (happy path)

> _(what did you see in Lambda / API GW / DynamoDB metrics?)_

### Invalid requests → 4XX

> _(which metric moved? which namespace / dimension?)_

### Application errors → 5XX

> _(Lambda Errors vs API GW 5XXError — did they both move? why?)_

### Slow requests

> _(Duration vs Latency vs IntegrationLatency — what's the difference?)_

### Throttling

> _(did you manage to throttle DynamoDB? which metric showed it?)_
