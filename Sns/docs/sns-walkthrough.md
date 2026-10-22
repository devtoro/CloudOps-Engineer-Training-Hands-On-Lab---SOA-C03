# Amazon SNS — Hands-On Walkthrough

> Companion to `sns-concepts.md`. Work through it after `terraform apply`. Each step says
> *what to run / click*, *what you should see*, and the *exam angle*.
>
> **Region:** `eu-central-1` · **Profile:** `dev` · **Prefix:** `cloudops-sns-dev`
>
> **Doc currency:** verified against current AWS docs. Content rephrased for licensing
> compliance.

---

## 0. Deploy

```bash
aws sso login --profile dev
export AWS_PROFILE=dev; export AWS_REGION=eu-central-1
cd Sns/terraform
terraform init && terraform apply
terraform output
#   standard_topic_arn, fifo_topic_arn, orders_queue_url, dlq_url
```

> 💲 Near-zero cost (SNS/SQS/Lambda/KMS at lab volume). `terraform destroy` when done.

---

## 1. Message filtering + attributes — publish once, see routing

Subscriptions: `orders` SQS (filter `category=orders`), `alerts` SQS (filter
`category=alerts` AND `severity in [high,critical]`, with a DLQ), and a Lambda (filter
`category=orders`).

```bash
TOPIC=$(terraform output -raw standard_topic_arn)

# (A) category=orders → orders queue + Lambda; NOT alerts queue
aws sns publish --topic-arn "$TOPIC" --message '{"id":1}' \
  --message-attributes '{"category":{"DataType":"String","StringValue":"orders"}}'

# (B) category=alerts, severity=high → alerts queue only
aws sns publish --topic-arn "$TOPIC" --message '{"id":2}' \
  --message-attributes '{"category":{"DataType":"String","StringValue":"alerts"},"severity":{"DataType":"String","StringValue":"high"}}'

# (C) category=alerts, severity=low → matches NEITHER (severity filtered out)
aws sns publish --topic-arn "$TOPIC" --message '{"id":3}' \
  --message-attributes '{"category":{"DataType":"String","StringValue":"alerts"},"severity":{"DataType":"String","StringValue":"low"}}'
```

Check where each landed:
```bash
aws sqs receive-message --queue-url "$(terraform output -raw orders_queue_url)" --max-number-of-messages 10 \
  --query 'Messages[].Body' --output text
aws sqs receive-message --queue-url "$(terraform output -raw alerts_queue_url 2>/dev/null)" --max-number-of-messages 10 \
  --query 'Messages[].Body' --output text
# Lambda:
aws logs tail /aws/lambda/cloudops-sns-dev-subscriber --since 5m
```

Expected: (A) → orders queue + Lambda; (B) → alerts queue; (C) → nowhere (filtered out).

> 📌 **Exam angle:** filtering happens **in SNS** via per-subscription filter policies on
> **message attributes**. One publish fans out only to matching subscribers. Message (C)
> shows an AND filter rejecting on `severity`.

---

## 2. Encryption & secure transport

- The topics are KMS-encrypted (`terraform output` shows the key via the module). Publishes
  succeed because the key policy grants SNS `GenerateDataKey*`/`Decrypt`.
- The topic policy **denies non-TLS publishes**. All AWS SDK/CLI calls are HTTPS, so you
  won't trip it normally — but it's the guardrail that blocks any plaintext attempt.

```bash
# Inspect the topic policy + KMS setting
aws sns get-topic-attributes --topic-arn "$TOPIC" \
  --query 'Attributes.{Policy:Policy,Kms:KmsMasterKeyId}'
```

> 📌 **Exam angle:** at rest = KMS (key-policy grant for SNS); in transit = the
> `aws:SecureTransport=false` **Deny**. Both visible in the topic attributes.

---

## 3. FIFO topic (ordering + dedup)

The FIFO topic (`...-events.fifo`) needs a FIFO SQS subscriber and a `MessageGroupId`:

```bash
FIFO=$(terraform output -raw fifo_topic_arn)
aws sns publish --topic-arn "$FIFO" --message '{"seq":1}' \
  --message-group-id "orders-stream" \
  --message-attributes '{"category":{"DataType":"String","StringValue":"orders"}}'
```

> 📌 **Exam angle:** FIFO requires `.fifo` names, FIFO SQS subscribers, and
> `MessageGroupId`; content-based dedup (set on our topic) means identical bodies within the
> dedup window are de-duplicated.

---

## 4. DLQ — capture failed deliveries

The `alerts` subscription has a DLQ redrive policy. The clean way to *force* failures is to
subscribe a Lambda that always errors, or point a subscription at a broken endpoint — then
messages exhaust retries and land in the DLQ. To just inspect the DLQ:

```bash
aws sqs get-queue-attributes --queue-url "$(terraform output -raw dlq_url)" \
  --attribute-names ApproximateNumberOfMessagesVisible
```

The HTTP/S subscription (§5) points at a placeholder URL, so its deliveries fail and —
if it were given a DLQ — would redrive there; it's the natural failure generator.

> 📌 **Exam angle:** the DLQ is on the **subscription** (redrive policy). Messages arrive
> after retries are exhausted. Alarm on `ApproximateNumberOfMessagesVisible`.

---

## 5. Retry / backoff (HTTP/S delivery policy)

The `delivery-policy` module created an HTTPS subscription (placeholder URL) with a custom
`healthyRetryPolicy` (5 retries, exponential backoff, 5–60s, throttle 10/s).

```bash
# Find the HTTPS subscription and view its delivery policy
aws sns list-subscriptions-by-topic --topic-arn "$TOPIC" \
  --query "Subscriptions[?Protocol=='https'].SubscriptionArn" --output text
# then:
aws sns get-subscription-attributes --subscription-arn <arn> \
  --query 'Attributes.DeliveryPolicy'
```

Because the endpoint is a placeholder, deliveries fail and exercise the retry schedule
(immediate → pre-backoff → backoff → post-backoff), then stop after `numRetries`.

> 📌 **Exam angle:** retry/backoff is **HTTP/S-only**, four phases, `backoffFunction`
> linear/geometric/exponential. `maxReceivesPerSecond` throttling re-queues **without**
> consuming retries.

---

## 6. Monitor & troubleshoot

```bash
# SNS failed-delivery + DLQ redrive metrics (last 1h)
aws cloudwatch get-metric-statistics --namespace AWS/SNS \
  --metric-name NumberOfNotificationsFailed \
  --dimensions Name=TopicName,Value=cloudops-sns-dev-events \
  --start-time "$(date -u -v-1H '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date -u -d '1 hour ago' '+%Y-%m-%dT%H:%M:%SZ')" \
  --end-time "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" --period 300 --statistics Sum
```

The lab's CloudWatch alarm `cloudops-sns-dev-sns-dlq-not-empty` enters ALARM when the DLQ
has any visible messages.

> 📌 **Exam triage:** `NumberOfNotificationsFailed` ↑ → delivery problem;
> `NumberOfNotificationsRedrivenToDlq` ↑ → messages going to DLQ;
> `NumberOfNotificationsFailedToRedriveToDlq` ↑ → the **DLQ** is misconfigured;
> `NumberOfNotificationsFilteredOut-NoMessageAttributes` → publisher omitted attributes.

---

## 7. Clean up

```bash
cd Sns/terraform
terraform destroy
```

---

## Deploy-and-explore checklist

- [ ] Published 3 messages; confirmed **filter routing** (orders→orders+Lambda, alerts/high→alerts, alerts/low→nowhere).
- [ ] Inspected topic **KMS + policy** (encryption at rest + TLS deny).
- [ ] Published to the **FIFO** topic with a MessageGroupId.
- [ ] Inspected the **DLQ** depth; understood it's per-subscription.
- [ ] Viewed the **HTTP/S delivery policy** (retry/backoff phases).
- [ ] Queried SNS **failed/redrive metrics**; saw the DLQ alarm.
- [ ] `terraform destroy`.
