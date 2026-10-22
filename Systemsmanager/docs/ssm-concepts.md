# AWS Systems Manager — Concept Reference (CloudOps Exam Prep)

> Reference for the *conceptual* half of the SSM objectives. This lab's Terraform is
> **deployable** (`Systemsmanager/terraform/`) — one `t3.micro` managed node plus the SSM
> features. Pair with `ssm-walkthrough.md` for hands-on. Hybrid activation is reference-only
> (needs a real external machine). Content rephrased from AWS docs for licensing compliance.

---

## 0. What Systems Manager is

SSM is an **operations toolbox** for managing fleets of nodes (EC2, on-prem, other clouds)
from one control plane. The common thread: a **managed node** runs the **SSM Agent**, which
**dials out** to SSM — so management needs **no inbound ports, no SSH keys, no bastion**.

A node becomes "managed" with three things:
1. **SSM Agent** running (pre-installed on AL2023, Ubuntu, Windows AMIs).
2. **Permissions** — EC2: an **instance profile** with `AmazonSSMManagedInstanceCore`;
   hybrid: an **IAM service role** via an activation.
3. **Network egress** to the SSM endpoints (public, or via **VPC interface endpoints** in
   private subnets).

> 📌 **Exam angle:** the agent is **outbound-only**. "Manage a private instance with no
> inbound access / no bastion" → SSM. Missing managed node? → agent not running, missing
> `AmazonSSMManagedInstanceCore`, or no network path to the endpoints.

---

## 1. SSM Agent & installation

- **Pre-installed** on current Amazon Linux, Ubuntu, Windows Server AMIs.
- **Manual install** for other/older OSes or on-prem (`yum`/`apt`/MSI).
- The agent is what executes Run Command, Session Manager, Patch, Inventory on the node.

> 📌 **Exam angle:** if the agent isn't installed/updated, none of the SSM node features
> work. Agent auto-update can be managed via a State Manager association.

---

## 2. Session Manager — secure shell with no SSH

A **session** is a TLS 1.2, SigV4-signed, bidirectional channel between you and a node.

- **No inbound ports, no bastion, no SSH keys.** Access is **IAM** (`ssm:StartSession`).
- **Logging:** session transcripts to **S3 and/or CloudWatch Logs**; API calls in
  **CloudTrail**. (Configured via the `SSM-SessionManagerRunShell` document.)
- **Extras:** **port forwarding** (reach a service on the node without opening it) and
  **SSH over Session Manager** (real `ssh`/`scp` tunneled through SSM — still no open port).

Two ways to connect:
| Method | What it is | Keys? |
|---|---|---|
| `aws ssm start-session` | pure SSM shell (NOT ssh) | none |
| `ssh` with a `ProxyCommand` using `AWS-StartSSHSession` | real SSH tunneled through SSM | yes (normal SSH keys) |

> 📌 **Exam angle:** "replace the bastion / close port 22" → **Session Manager**. It's
> IAM-controlled and **auditable** (session logs), which SSH keys are not. `start-session`
> is not SSH; SSH-over-SSM is the escape hatch when a tool needs the SSH protocol.

---

## 3. Run Command — run scripts/commands at scale

Run a **document** (e.g. `AWS-RunShellScript`, `AWS-RunPowerShellScript`) against targets
**on demand** (`aws ssm send-command`) or **recurring** (a State Manager association).

- Target by **instance IDs, tags, or resource groups** — fan out across a fleet.
- Controls: **rate control** (`max-concurrency`) and **error control** (`max-errors`) to
  roll out safely.
- No inbound ports — same agent-outbound model.
- Output to console, S3, or CloudWatch Logs.

> 📌 **Exam angle:** Run Command = fleet-wide script/command execution without SSH.
> `max-concurrency`/`max-errors` are the safe-rollout knobs (e.g. "1 at a time, stop after
> 1 failure"). Target by tag to hit dynamic fleets.

---

## 4. Patch Manager — automated patching

Pieces:
- **Patch baseline** — rules for which patches are *approved* (by classification, severity,
  auto-approval delay). Each OS has an AWS default; you can author a **custom** baseline.
- **Patch group** — instances grouped by the **`Patch Group` tag**; a group maps to one
  baseline per OS.
- **Maintenance window** — schedule + targets + task that runs **`AWS-RunPatchBaseline`**.
- **Operation** = **Scan** (report compliance, read-only) or **Install** (apply, may reboot).

Patch **compliance** (missing/installed per node) is visible in SSM and can flow to
**Security Hub / Config**.

> 📌 **Exam angle:** instances match a baseline via the **`Patch Group` tag**.
> `AWS-RunPatchBaseline` with Operation **Scan** vs **Install**. Maintenance windows give
> you a controlled schedule + rate/error limits for fleet patching.

---

## 5. Hybrid activation — manage on-prem / other-cloud nodes

Extend SSM beyond EC2:
1. Create an **IAM service role** (trust `ssm.amazonaws.com`) with
   `AmazonSSMManagedInstanceCore`.
2. Create a **hybrid activation** → yields an **Activation Code + Activation ID**
   (`aws ssm create-activation`).
3. On the external machine, install SSM Agent and **register** with the code/ID + region.

The node then appears as a managed node with an **`mi-` id** (vs **`i-`** for EC2) and
supports Session Manager, Run Command, Patch, Inventory — identically.

> 📌 **Exam angle:** hybrid activation = **one control plane for on-prem + multicloud +
> EC2**. EC2 uses an **instance profile**; hybrid uses an **activation + service role** and
> gets an **`mi-`** id. "Manage on-prem servers alongside EC2" → hybrid activation.

---

## 6. Inventory — track software, patches, configuration

**Inventory** collects metadata from managed nodes: installed **applications**, **AWS
components**, **network config**, **services**, **Windows updates**, instance details, and
**custom** inventory. Collected via an **`AWS-GatherSoftwareInventory`** association.

- Query in the console / API; see what's installed across the fleet.
- **Resource Data Sync** aggregates inventory (and across accounts/Regions) into a central
  **S3** bucket for **Athena/QuickSight** querying.

> 📌 **Exam angle:** Inventory answers "what software/patches/config is on my fleet?" Use
> **Resource Data Sync → S3** to centralize and query at org scale. Pairs with Patch Manager
> for patch posture.

---

## 7. Automation documents — runbooks + triggers

An **Automation document** (schemaVersion **0.3**, type **Automation**) is a multi-step
runbook. Steps use actions like `aws:executeAwsApi`, `aws:runCommand`, `aws:branch`,
`aws:approve` (manual gate), `aws:sleep`. Runs under an **AutomationAssumeRole** (now
*optional* in some cases, required for elevated/long-running actions).

Triggers (all point at the same document):
- **Manual** (console/CLI `start-automation-execution`).
- **EventBridge** — scheduled or event-pattern rule → start the automation (needs an
  EventBridge-invoke role: `ssm:StartAutomationExecution` + `iam:PassRole`).
- **Config / Security Hub remediation**, **maintenance windows**.

> 📌 **Exam angle:** custom runbooks = schemaVersion **0.3**. The **two-role** pattern for
> event-driven automation: EventBridge-invoke role (StartAutomationExecution + PassRole) +
> the AutomationAssumeRole the runbook runs as. Same engine behind Config and Security Hub
> remediation and EC2 auto-heal.

---

## 8. The rest of the SSM toolbox (recognize these)

| Capability | Purpose |
|---|---|
| **Parameter Store** | config + secrets (SecureString via KMS); hierarchical params (you used it for AMI lookup) |
| **State Manager** | enforce desired state via **associations** (document + targets + schedule) |
| **Maintenance Windows** | scheduled operational tasks (patching, commands) with rate/error limits |
| **OpsCenter** | aggregate + manage operational issues (OpsItems) |
| **Compliance** | patch + association compliance status across the fleet |
| **Documents (SSM docs)** | the shared artifact type: Command, Automation, Session, Policy |

> 📌 **Exam angle:** **Parameter Store** (config/secrets) vs **Secrets Manager** (secrets +
> rotation) is a frequent compare — Parameter Store SecureString is cheaper, Secrets Manager
> does managed rotation. State Manager = **desired-state** enforcement via associations.

---

## Quick-recall cheat sheet

| Question | One-line answer |
|---|---|
| What makes a node "managed"? | SSM Agent + `AmazonSSMManagedInstanceCore` (EC2) / activation role (hybrid) + egress |
| Shell with no SSH/bastion/keys? | **Session Manager** (IAM auth, logged to S3/CWL) |
| Run a script across a fleet? | **Run Command** (target by tag; max-concurrency/max-errors) |
| Match instance to a patch baseline? | the **`Patch Group` tag** |
| Scan vs install patches? | `AWS-RunPatchBaseline` Operation = **Scan** / **Install** |
| Manage on-prem servers? | **hybrid activation** (code+ID, service role, `mi-` id) |
| What's installed on my fleet? | **Inventory** (+ Resource Data Sync → S3) |
| Custom runbook schema version? | **0.3**, document_type **Automation** |
| Event-driven automation roles? | EventBridge-invoke (Start + PassRole) + AutomationAssumeRole |
| Config/secrets store? | **Parameter Store** (SecureString via KMS) |
| EC2 vs hybrid node id? | **`i-`** vs **`mi-`** |
| Private subnet, no internet? | **VPC interface endpoints** for SSM |
