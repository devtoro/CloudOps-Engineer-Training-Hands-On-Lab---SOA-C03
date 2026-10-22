# AWS Systems Manager — Hands-On Walkthrough

> Companion to `ssm-concepts.md`. Work through it after `terraform apply`. Each step says
> *what to run / click*, *what you should see*, and the *exam angle*.
>
> **Region:** `eu-central-1` · **Profile:** `dev` · **Prefix:** `cloudops-ssm-dev`
>
> **Doc currency:** verified against current AWS docs. Content rephrased for licensing
> compliance.

---

## 0. Prerequisites

```bash
aws sso login --profile dev
export AWS_PROFILE=dev
export AWS_REGION=eu-central-1
cd Systemsmanager/terraform

# For Session Manager from your Mac, install the plugin once:
brew install --cask session-manager-plugin   # or the AWS pkg installer
```

> 💲 **Cost:** one `t3.micro` managed node is the only always-on charge. `terraform destroy`
> when done.

---

## 1. Deploy & confirm the node is managed

```bash
terraform init
terraform apply
INSTANCE=$(terraform output -raw instance_id)

# Is the node managed? (agent registered + reachable)
aws ssm describe-instance-information \
  --query "InstanceInformationList[?InstanceId=='$INSTANCE'].{id:InstanceId,ping:PingStatus,agent:AgentVersion,platform:PlatformName}"
# PingStatus = Online  → managed and reachable
```

> ⏳ Give the agent 1–3 minutes after boot to register. If it never appears: check the
> instance profile has `AmazonSSMManagedInstanceCore` and the node has egress to the SSM
> endpoints.

> 📌 **Exam angle:** `describe-instance-information` + `PingStatus: Online` is how you
> confirm a node is SSM-managed. "Instance not showing in Session Manager" → this is your
> first check.

---

## 2. Session Manager — connect with no SSH, no open ports

Recall the instance's security group has **no inbound rules**. Yet:

### (a) Pure SSM shell (not SSH, no keys)
```bash
aws ssm start-session --target "$INSTANCE"
# You're now on the box as ssm-user. Try:
whoami; hostname; cat /etc/os-release | head -1
exit
```

Console equivalent: **Systems Manager → Session Manager → Start session → pick the node.**

### (b) Real SSH tunneled through SSM (optional, needs a key)
Add to `~/.ssh/config`:
```
Host i-* mi-*
    ProxyCommand sh -c "aws ssm start-session --target %h --document-name AWS-StartSSHSession --parameters 'portNumber=%p' --profile dev"
```
Then `ssh ec2-user@$INSTANCE` — real SSH, still no open inbound port (sshd reached via the
SSM tunnel to localhost:22).

### (c) See the session logs (you enabled BOTH targets)
```bash
# CloudWatch Logs
aws logs tail "/ssm/session-logs/cloudops-ssm-dev" --since 10m
# S3
aws s3 ls "s3://$(terraform output -raw session_log_bucket)/" --recursive | tail
```

> 📌 **Exam angle:** no inbound ports, IAM-authenticated, **fully logged** (S3 + CWL) — the
> audit story SSH lacks. `start-session` ≠ SSH; the ProxyCommand method is real SSH over the
> SSM tunnel.

---

## 3. Run Command — run a script on the node

The lab created a recurring association, but try an **ad-hoc** command too:

```bash
CMD=$(aws ssm send-command \
  --document-name "AWS-RunShellScript" \
  --targets "Key=InstanceIds,Values=$INSTANCE" \
  --parameters 'commands=["uptime","df -h /"]' \
  --query 'Command.CommandId' --output text)

# Fetch the output once it completes
aws ssm get-command-invocation --command-id "$CMD" --instance-id "$INSTANCE" \
  --query '{status:Status,stdout:StandardOutputContent}'
```

Target by **tag** instead of id to hit a fleet:
```bash
aws ssm send-command --document-name "AWS-RunShellScript" \
  --targets "Key=tag:Patch Group,Values=cloudops-ssm-dev" \
  --parameters 'commands=["echo fleet-wide"]'
```

> 📌 **Exam angle:** Run Command fans out by **id/tag/resource group**, no SSH.
> `max-concurrency`/`max-errors` control safe rollout. Output → console/S3/CWL.

---

## 4. Patch Manager — scan for missing patches (read-only)

The lab wired a baseline + patch group + maintenance window (Scan). Trigger a scan **now**
without waiting for the window:

```bash
aws ssm send-command \
  --document-name "AWS-RunPatchBaseline" \
  --targets "Key=InstanceIds,Values=$INSTANCE" \
  --parameters 'Operation=Scan'

# After it runs, view patch compliance
aws ssm list-compliance-items --resource-ids "$INSTANCE" --resource-types "ManagedInstance" \
  --query 'ComplianceItems[?ComplianceType==`Patch`].[Title,Status,Severity]' --output table
```

Console: **Systems Manager → Patch Manager** (compliance dashboard) and **Fleet Manager** →
node → Patch.

> 📌 **Exam angle:** **Scan** reports compliance without installing/rebooting; **Install**
> applies and may reboot. Node ↔ baseline link is the **`Patch Group` tag**. Compliance can
> flow to Security Hub/Config.

---

## 5. Inventory — see what's on the node

The lab created an `AWS-GatherSoftwareInventory` association. After it runs (allow a few
minutes):

```bash
# List inventory entry types collected for the node
aws ssm list-inventory-entries --instance-id "$INSTANCE" \
  --type-name "AWS:Application" \
  --query 'Entries[0:10].[Name,Version]' --output table
```

Console: **Fleet Manager → node → Inventory**, or **Inventory** dashboard for fleet-wide
software/counts.

> 📌 **Exam angle:** Inventory = fleet software/patch/config visibility. **Resource Data
> Sync → S3** centralizes it (across accounts/Regions) for Athena/QuickSight.

---

## 6. Custom Automation document + EventBridge trigger

The lab created a custom runbook (`cloudops-ssm-dev-tag-instances`) and an hourly EventBridge
trigger. Run the automation manually to see it work:

```bash
DOC=$(terraform output -raw automation_document_name)
ROLE_ARN=$(aws iam get-role --role-name cloudops-ssm-dev-automation-role --query 'Role.Arn' --output text)

EXEC=$(aws ssm start-automation-execution \
  --document-name "$DOC" \
  --parameters "InstanceId=$INSTANCE,AutomationAssumeRole=$ROLE_ARN" \
  --query 'AutomationExecutionId' --output text)

aws ssm get-automation-execution --automation-execution-id "$EXEC" \
  --query '{status:AutomationExecutionStatus}'

# Confirm the effect: the instance now has a LastAutomationRun tag
aws ec2 describe-tags --filters "Name=resource-id,Values=$INSTANCE" "Name=key,Values=LastAutomationRun" \
  --query 'Tags[0].Value'
```

Console: **Systems Manager → Automation** shows the execution + per-step status.

> 📌 **Exam angle:** custom runbook = schemaVersion **0.3**. The EventBridge trigger uses the
> **two-role** pattern (invoke role: StartAutomationExecution + PassRole; AutomationAssumeRole
> the runbook runs as). Same engine as Config/Security Hub remediation and EC2 auto-heal.
> (The scheduled rule's target input has a placeholder InstanceId — set it, or switch to an
> event-pattern rule with an input transformer, for the hourly run to target a real node.)

---

## 7. Hybrid activation (reference — not deployed)

To manage an on-prem machine (commented in `managed-instance`):

```bash
# 1. create an activation (needs the hybrid service role)
aws ssm create-activation --default-instance-name onprem-web \
  --iam-role cloudops-ssm-dev-hybrid-role --registration-limit 5
#   → returns ActivationId + ActivationCode

# 2. on the on-prem box, install SSM Agent then register:
#   sudo amazon-ssm-agent -register -code "<code>" -id "<id>" -region eu-central-1
```

The node appears with an **`mi-`** id and supports all the above features identically.

> 📌 **Exam angle:** hybrid activation extends SSM to on-prem/multicloud — one control plane.
> EC2 = instance profile + `i-`; hybrid = activation + service role + `mi-`.

---

## 8. Clean up

```bash
cd Systemsmanager/terraform
terraform destroy
```

> Note: Terraform owns the `SSM-SessionManagerRunShell` document — destroy removes the lab's
> session-logging preference. If you had other session config, re-set it afterward.

---

## Deploy-and-explore checklist

- [ ] `describe-instance-information` shows the node **Online**.
- [ ] Opened a **Session Manager** shell on an instance with **no inbound ports**; saw logs in CWL + S3.
- [ ] (Optional) Connected via **SSH-over-SSM** ProxyCommand.
- [ ] Ran an ad-hoc **Run Command** and fetched output; targeted by **tag**.
- [ ] Triggered a **patch Scan**; viewed patch **compliance**.
- [ ] Viewed **Inventory** (applications) for the node.
- [ ] Ran the **custom Automation** doc; confirmed the `LastAutomationRun` tag.
- [ ] Understood **hybrid activation** (`i-` vs `mi-`).
- [ ] `terraform destroy`.
