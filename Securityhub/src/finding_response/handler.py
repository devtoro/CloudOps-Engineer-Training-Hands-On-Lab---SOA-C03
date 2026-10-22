"""
Security Hub automated incident-response Lambda (reference).

Triggered by an EventBridge rule on Security Hub findings filtered to HIGH/
CRITICAL severity. In a real setup this is where you'd take an action:
isolate an instance, revoke a key, quarantine a resource, open a ticket, or
kick off an SSM Automation runbook.

Here it just parses and logs the finding so the wiring is visible. The event
carries findings in event["detail"]["findings"] (AWS Security Finding Format).
"""

import json
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)


def handler(event, context):
    findings = event.get("detail", {}).get("findings", [])
    logger.info("Received %d finding(s)", len(findings))

    for f in findings:
        severity = f.get("Severity", {}).get("Label", "UNKNOWN")
        title = f.get("Title", "")
        resource_ids = [r.get("Id") for r in f.get("Resources", [])]
        product = f.get("ProductName", "")

        logger.info(
            "RESPOND severity=%s product=%s title=%s resources=%s",
            severity, product, title, resource_ids,
        )

        # --- Where real remediation would go --------------------------------
        # e.g. for a specific control/title you might:
        #   - call ec2.modify_instance_attribute to isolate an instance
        #   - call iam.update_access_key to deactivate a leaked key
        #   - start an SSM Automation runbook
        #   - post to an incident channel / create a ticket
        # Keep actions idempotent and tightly scoped to the finding type.

    return {"handled": len(findings)}
