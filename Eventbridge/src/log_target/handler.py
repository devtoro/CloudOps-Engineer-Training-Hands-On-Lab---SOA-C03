"""
Log-target Lambda for the EventBridge lab.

A trivial target: it logs the entire event it receives. Use it to SEE which
EventBridge rule matched — fire events, then read this function's CloudWatch
Logs to confirm the pattern matched and what EventBridge delivered.
"""

import json
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)


def handler(event, context):
    logger.info("EventBridge delivered event:\n%s", json.dumps(event, indent=2))

    # Surface the most useful routing fields at the top of the log line.
    logger.info(
        "source=%s detail-type=%s",
        event.get("source"),
        event.get("detail-type"),
    )
    return {"received": True}
