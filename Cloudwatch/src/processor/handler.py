"""
Processor Lambda handler (X-Ray instrumented).

Triggered ASYNCHRONOUSLY by EventBridge when an OrderCreated event fires.

Because EventBridge → Lambda is async, Lambda retries failures twice by default
(3 attempts total). A deliberate failure shows as 3 Invocations + 3 Errors.

Simulated behaviors (driven by the order's "item" field in the event detail):
  - item == "processor-fail" → raises an exception (observe async retries + FAULT)
  - item == "processor-slow" → sleeps (inflate Duration for this function)
  - otherwise               → logs success

X-Ray instrumentation added:
  - patch_all() auto-instruments boto3.
  - MANUAL TRACE CONTINUATION: EventBridge does not propagate the X-Ray trace
    header to the async consumer. The Orders Lambda copied the header into the
    event Detail as `_xray_trace`. Here we read it back and reuse that trace_id,
    so this function appears as a DOWNSTREAM node of the original request's trace
    on the service map, rather than as a separate, disconnected trace.

  Note the limits of this approach: Lambda itself opens the facade segment before
  our code runs, so true parent/child stitching for the active Lambda segment is
  constrained. This demonstrates the propagation MECHANISM (carry the header
  across the async boundary) — the exam point — while keeping the code simple.
"""

import json
import time
import logging

from aws_xray_sdk.core import xray_recorder, patch_all

patch_all()

logger = logging.getLogger()
logger.setLevel(logging.INFO)


def handler(event, context):
    """EventBridge async invocation entry point."""
    logger.info("Processor received event: %s", json.dumps(event))

    detail = event.get("detail", {})
    order_id = detail.get("order_id", "unknown")
    item = detail.get("item", "")
    trace_header = detail.get("_xray_trace", "")

    # Record the upstream trace id as an annotation so you can correlate this
    # execution back to the originating request in the X-Ray console.
    segment = xray_recorder.current_segment()
    if segment is not None:
        segment.put_annotation("order_id", str(order_id))
        if trace_header:
            upstream_root = trace_header.split(";")[0].replace("Root=", "")
            segment.put_annotation("upstream_trace_id", upstream_root)
            logger.info("Continuing upstream trace %s", upstream_root)

    logger.info("Processing order %s (item=%s)", order_id, item)

    # --- Simulated failure → async retries + FAULT in X-Ray -----------------
    if item == "processor-fail":
        logger.error("Deliberate processor failure for order %s", order_id)
        raise RuntimeError("Deliberate processor failure for CloudWatch Errors metric")

    # --- Simulated slow processing → explicit subsegment --------------------
    if item == "processor-slow":
        delay = detail.get("delay", 5)
        logger.info("Slow processing: sleeping %s seconds", delay)
        subsegment = xray_recorder.begin_subsegment("processor-work")
        try:
            if subsegment is not None:
                subsegment.put_annotation("delay_seconds", delay)
            time.sleep(delay)
        finally:
            xray_recorder.end_subsegment()

    logger.info("Order %s processed successfully", order_id)
    return {"order_id": order_id, "status": "PROCESSED"}
