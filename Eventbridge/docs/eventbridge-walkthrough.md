# Amazon EventBridge — Hands-On Walkthrough (Patterns, Auto-heal, Cross-Region)

> Click-by-click and CLI-by-CLI companion to `eventbridge-concepts.md`. Work through it
> after `terraform apply`. Each step says *what to run / click*, *what you should see*, and
> the *exam angle*.
>
> **Region:** `eu-central-1` (primary), `eu-west-1` (secondary) · **Profile:** `dev`
> · **Prefix:** `cloudops-eb-dev`
>
> **Doc currency:** verified against current AWS docs. The EventBridge console lives under
> **Amazon EventBridge** (Buses, Rules, Pipes, Scheduler, Sandbox). Content rephrased from
> AWS documentation for licensing compliance.

---

## 0. Prerequisites & cost note

```bash
aws sso login --profile dev
export AWS_PROFILE=dev
export AWS_REGION=eu-central-1
cd Eventbridge/terraform
```

> 💲 **Cost:** the only always-on billable resource is the **EC2 `t3.micro`** demo target
> (cents/hour). Everything else is event-driven. `terraform destroy` when done.

---

## 1. Deploy

```bash
terraform init     # pulls aws + archive providers; resolves aws.secondary (eu-west-1)
terraform apply
terraform output
#   instance_id        = i-0...
#   autoheal_rule_name = cloudops-eb-dev-autoheal-state-change
#   secondary_bus_name = cloudops-eb-dev-dest-bus
```

---

## 2. Pattern matching — send events, see which rules match

The `rules-patterns` module put five rules on the custom bus `cloudops-eb-dev-demo-bus`,
each demonstrating one operator, all routing to the **log-target Lambda**. Fire events,
then read the Lambda logs.

```bash
BUS=cloudops-eb-dev-demo-bus

# (A) exact + numeric + exists all match this one:
aws events put-events --entries '[{
  "Source":"myapp.orders","DetailType":"OrderPlaced","EventBusName":"'$BUS'",
  "Detail":"{\"region\":\"eu-central-1\",\"amount\":150,\"errorCode\":\"E42\"}"
}]'

# (B) prefix matches (region starts with eu-), numeric does NOT (amount 50):
aws events put-events --entries '[{
  "Source":"myapp.orders","DetailType":"OrderPlaced","EventBusName":"'$BUS'",
  "Detail":"{\"region\":\"eu-west-1\",\"amount\":50}"
}]'

# (C) anything-but matches (status != ok):
aws events put-events --entries '[{
  "Source":"myapp.health","DetailType":"HealthReport","EventBusName":"'$BUS'",
  "Detail":"{\"status\":\"degraded\"}"
}]'
```

Read the log-target Lambda logs to see which rules fired:

```bash
aws logs tail /aws/lambda/cloudops-eb-dev-log-target --since 5m --follow
```

Map what you expect:
- Event **(A)**: `source=myapp.orders`, `amount>100`, `errorCode` exists, `region` prefix
  `eu-` → matches **exact**, **numeric**, **exists**, **prefix** (4 rules → 4 invocations).
- Event **(B)**: matches **exact** + **prefix** only (amount 50 fails numeric, no errorCode).
- Event **(C)**: `source=myapp.health`, `status=degraded` → matches **anything-but** only.

> 📌 **Try the EventBridge Sandbox:** console → **EventBridge → Developer resources →
> Sandbox**. Paste an event pattern and a sample event; it tells you match/no-match
> **without creating a rule**. Great for iterating on patterns.

> 📌 **Exam angle:** one event can match **multiple rules** (each matched rule invokes its
> targets independently). Pattern logic = AND across fields, OR within a field's array.

---

## 3. The AWS-service-event rule (default bus)

The `rules-patterns` module also added a default-bus rule matching
`EC2 Instance State-change Notification`. Trigger it by stopping/starting the instance
(§4 does exactly that) and watch the real AWS event land in the log-target logs — note its
shape differs from your custom `myapp.*` events (`source: aws.ec2`, rich `detail`).

> 📌 **Exam angle:** this rule is on the **default** bus on purpose — AWS service events
> never reach a custom bus.

---

## 4. Auto-heal path #1 — direct EC2 event → SSM restart

> ⚠️ **Accuracy note (verified against AWS docs):** EC2 emits
> **"EC2 Instance State-change Notification"** events (pending/running/stopping/stopped/
> terminated). There is **no** native "status-check" *event* — a failed status check is a
> **CloudWatch metric** (`StatusCheckFailed_*`), handled by the alarm path in §5. So this
> direct-event demo triggers on the instance entering **stopped**.

Trigger it by stopping the instance:

```bash
INSTANCE=$(terraform output -raw instance_id)
aws ec2 stop-instances --instance-ids "$INSTANCE"
```

What happens:
1. Instance reaches `stopped` → EC2 emits the state-change event.
2. The `autoheal-state-change` rule matches (this instance + `state=stopped`).
3. Target = SSM `AWS-RestartEC2Instance`, started via the EventBridge-invoke role, running
   as the AutomationAssumeRole.

Watch the automation run:

```bash
aws ssm describe-automation-executions \
  --filters Key=DocumentNamePrefix,Values=AWS-RestartEC2Instance \
  --query 'AutomationExecutionMetadataList[0].{status:AutomationExecutionStatus, time:ExecutionStartTime}'
```

> 📌 Console: **Systems Manager → Automation** shows the execution + step status; **EC2**
> shows the instance returning to `running`. (Note: `AWS-RestartEC2Instance` reboots a
> running instance; depending on timing you may see it start/reboot the stopped instance.
> The teaching point is the **event → SSM** wiring, not the exact restart semantics.)

---

## 5. Auto-heal path #2 — CloudWatch alarm → EventBridge → SSM

The `alarm-to-eventbridge` module created an alarm on `StatusCheckFailed_Instance` for the
demo instance and a rule matching that alarm's transition to **ALARM**.

Rather than wait for a real hardware fault, flip the alarm state manually:

```bash
aws cloudwatch set-alarm-state \
  --alarm-name cloudops-eb-dev-instance-status-check \
  --state-value ALARM \
  --state-reason "manual test of alarm-driven auto-heal"
```

What happens:
1. The alarm enters ALARM → CloudWatch emits a **"CloudWatch Alarm State Change"** event.
2. The `alarm-to-autoheal` rule matches (this alarm, `state.value = ALARM`).
3. Same SSM restart target fires (reusing the autoheal roles).

> 📌 **Exam angle:** `set-alarm-state` is the standard way to **test alarm-driven
> automation** without producing the real metric condition. The alarm's **state change is
> the event** — you did not wire an alarm "action"; EventBridge listens for the state-change
> event. This is also exactly how AWS's own "automatic instance recovery" reacts to
> `StatusCheckFailed_System`.

---

## 6. Troubleshooting & monitoring

### Rule metrics (CloudWatch `AWS/Events`)
Console: **CloudWatch → Metrics → Events** → by rule name. Key metrics:
- `MatchedEvents` — events the rule matched (0 → pattern/bus wrong).
- `Invocations` — target invocations.
- `FailedInvocations` — delivery failures (→ permission/target problem; check the DLQ).
- `ThrottledRules`, `DeadLetterInvocations`.

### The DLQ
The auto-heal target has an SQS DLQ for undeliverable invocations:

```bash
aws sqs receive-message --queue-url "$(terraform output -raw autoheal_dlq_url 2>/dev/null)" 2>/dev/null \
  || echo "DLQ empty / no output wired — check cloudops-eb-dev-autoheal-dlq in the console"
```

> 📌 **Exam triage:** `MatchedEvents = 0` → fix the **pattern/bus**. `MatchedEvents > 0`
> but `FailedInvocations > 0` → fix **target permissions**; inspect the **DLQ** for the
> dropped events. This split is the fastest way to localize an EventBridge problem.

---

## 7. Cross-Region forwarding (eu-central-1 → eu-west-1)

The `cross-region` module forwards `myapp.crossregion` events from a source bus here to a
destination bus in `eu-west-1`, which logs them to CloudWatch Logs.

```bash
# Send to the SOURCE bus (primary region)
aws events put-events --region eu-central-1 --entries '[{
  "Source":"myapp.crossregion","DetailType":"Ping",
  "EventBusName":"cloudops-eb-dev-source-bus",
  "Detail":"{\"hello\":\"from-eu-central-1\"}"
}]'

# Read the DESTINATION log group in the SECONDARY region
aws logs tail /aws/events/cloudops-eb-dev-forwarded --region eu-west-1 --since 5m
```

You should see the event appear in the **eu-west-1** log group — it traveled: source bus
→ (rule target = destination bus ARN, via the forward role) → destination bus → (rule →
CloudWatch Logs).

> 📌 **Exam angle:** forwarding = **another bus as the target**, with an **IAM role on the
> source** (`events:PutEvents`) and a **resource policy on the destination** bus. Cross-
> account is identical except the destination policy trusts another account. This is the
> "central event bus" multi-account pattern.

---

## 8. API destinations (concept recap — not deployed)

Not built in this lab (by design). Recognize the shape: a **Connection** (holds Basic/API-
key/OAuth auth, backed by Secrets Manager) + an **API destination** (external HTTPS URL +
method + rate limit). A rule targets the API destination; EventBridge POSTs the event to
the external system. Use it to reach SaaS/webhooks/on-prem without a glue Lambda. Full
detail in §8 of `eventbridge-concepts.md`.

---

## 9. Clean up

```bash
cd Eventbridge/terraform
terraform destroy
```

- Stops the EC2 instance charge and removes both-region resources.
- If destroy complains about the non-default custom buses having rules, rerun — Terraform
  resolves the ordering.

---

## Deploy-and-explore checklist

- [ ] Sent custom events; confirmed via log-target logs which rules matched (and that one event can match several rules).
- [ ] Tried the **EventBridge Sandbox** to test a pattern without a rule.
- [ ] Stopped the instance; saw the **direct state-change** rule trigger the SSM restart.
- [ ] Used `set-alarm-state ALARM`; saw the **alarm-driven** rule trigger the same SSM restart.
- [ ] Checked `AWS/Events` metrics (`MatchedEvents`, `Invocations`, `FailedInvocations`).
- [ ] Forwarded an event eu-central-1 → eu-west-1 and read it from the secondary log group.
- [ ] Understood API destinations conceptually (Connection + endpoint).
- [ ] `terraform destroy`.
```
