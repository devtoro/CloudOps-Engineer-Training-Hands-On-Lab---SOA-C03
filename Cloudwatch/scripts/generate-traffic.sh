#!/usr/bin/env bash
#
# generate-traffic.sh
#
# Sends a mix of requests to the Order Processing Platform API to generate
# observability data across Lambda, API Gateway, DynamoDB, and EventBridge.
#
# Each scenario is designed to move a specific CloudWatch metric. After running,
# open the CloudWatch console and hunt for the metrics listed in the comments.
#
# Usage:
#   ./generate-traffic.sh                 # uses terraform output for URL + key
#   API_URL=... API_KEY=... ./generate-traffic.sh   # override manually
#
# Requires: curl, jq, terraform (unless API_URL/API_KEY are provided)

set -uo pipefail

# -----------------------------------------------------------------------------
# Resolve API URL and key
# -----------------------------------------------------------------------------
TF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../terraform" && pwd)"

if [[ -z "${API_URL:-}" ]]; then
  API_URL=$(terraform -chdir="$TF_DIR" output -raw api_url 2>/dev/null)
fi

if [[ -z "${API_KEY:-}" ]]; then
  # api_key_value is marked sensitive, so `terraform output -raw` refuses to
  # print it. Pull it from the state JSON instead.
  API_KEY=$(terraform -chdir="$TF_DIR" show -json 2>/dev/null \
    | jq -r '.values.root_module.child_modules[]?.resources[]?
             | select(.type=="aws_api_gateway_api_key")
             | .values.value' 2>/dev/null)
fi

if [[ -z "$API_URL" ]]; then
  echo "ERROR: Could not resolve API_URL. Run 'terraform apply' first, or set API_URL." >&2
  exit 1
fi

ENDPOINT="${API_URL%/}/orders"

echo "============================================================"
echo "Target endpoint : $ENDPOINT"
echo "API key         : ${API_KEY:0:8}... (hidden)"
echo "============================================================"
echo

# -----------------------------------------------------------------------------
# Helper: send one request and print the status code
#   $1 = label, $2 = JSON body, $3 = send api key? (yes/no)
# -----------------------------------------------------------------------------
send() {
  local label="$1" body="$2" use_key="$3"
  local key_header=()
  if [[ "$use_key" == "yes" ]]; then
    key_header=(-H "x-api-key: ${API_KEY}")
  fi

  local status
  status=$(curl -s -o /dev/null -w "%{http_code}" \
    -X POST "$ENDPOINT" \
    -H "Content-Type: application/json" \
    "${key_header[@]}" \
    -d "$body")

  printf "  [%-18s] HTTP %s\n" "$label" "$status"
}

# -----------------------------------------------------------------------------
# Scenario 1 — Happy path (x10)
# Watch: Lambda Invocations/Duration, DynamoDB ConsumedWriteCapacityUnits,
#        EventBridge rule → Processor Invocations
# -----------------------------------------------------------------------------
echo ">>> Scenario 1: Happy path (x10) — successful orders"
for i in $(seq 1 10); do
  send "happy #$i" '{"item":"widget","quantity":1}' yes
done
echo

# -----------------------------------------------------------------------------
# Scenario 2 — Validation errors → 4XX (x5)
# Watch: API Gateway 4XXError. NOTE: Lambda handled this gracefully (returned
#        400), so it is NOT counted as a Lambda Error.
# -----------------------------------------------------------------------------
echo ">>> Scenario 2: Validation errors (x5) — missing required fields → 400"
for i in $(seq 1 5); do
  send "invalid #$i" '{"item":"widget"}' yes
done
echo

# -----------------------------------------------------------------------------
# Scenario 3 — Application errors → 5XX (x5)
# Watch: Lambda Errors AND API Gateway 5XXError (both move together here).
# -----------------------------------------------------------------------------
echo ">>> Scenario 3: Application errors (x5) — item=fail → exception → 500"
for i in $(seq 1 5); do
  send "fail #$i" '{"item":"fail","quantity":1}' yes
done
echo

# -----------------------------------------------------------------------------
# Scenario 4 — Slow requests (x3)
# Watch: Lambda Duration, API Gateway Latency AND IntegrationLatency.
#        The gap between Latency and IntegrationLatency is API GW overhead.
# -----------------------------------------------------------------------------
echo ">>> Scenario 4: Slow requests (x3) — item=slow → 5s sleep"
for i in $(seq 1 3); do
  send "slow #$i" '{"item":"slow","quantity":1,"delay":5}' yes
done
echo

# -----------------------------------------------------------------------------
# Scenario 5 — Processor failures (x2)
# The order succeeds (200) but emits an event that makes the PROCESSOR fail.
# Watch: Processor Lambda Invocations = 3 per event (async retries!),
#        Processor Lambda Errors.
# -----------------------------------------------------------------------------
echo ">>> Scenario 5: Processor failures (x2) — item=processor-fail"
for i in $(seq 1 2); do
  send "proc-fail #$i" '{"item":"processor-fail","quantity":1}' yes
done
echo

# -----------------------------------------------------------------------------
# Scenario 6 — Missing API key (x3)
# Watch: API Gateway 4XXError (403 Forbidden). The request is rejected at the
#        API GW layer — the Lambda never runs, so no Lambda metrics move.
# -----------------------------------------------------------------------------
echo ">>> Scenario 6: Missing API key (x3) — expect 403"
for i in $(seq 1 3); do
  send "no-key #$i" '{"item":"widget","quantity":1}' no
done
echo

echo "============================================================"
echo "Done. Metrics take 1-3 minutes to appear in CloudWatch."
echo "Explore under:"
echo "  AWS/Lambda       → Invocations, Errors, Duration, Throttles, ConcurrentExecutions"
echo "  AWS/ApiGateway   → Count, 4XXError, 5XXError, Latency, IntegrationLatency"
echo "  AWS/DynamoDB     → ConsumedWriteCapacityUnits, ThrottledRequests"
echo "  AWS/Events       → Invocations, FailedInvocations (per rule)"
echo "============================================================"
