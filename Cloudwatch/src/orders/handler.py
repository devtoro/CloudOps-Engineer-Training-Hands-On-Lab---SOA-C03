"""
Orders Lambda handler (X-Ray instrumented).

Sits behind API Gateway. Writes to DynamoDB, emits an EventBridge event.

Request scenarios (unchanged from Phase 1):
  1. Happy path   → writes to DynamoDB, emits EventBridge event
  2. Validation   → missing required fields returns 400  (API GW 4XXError)
  3. Forced error → item="fail" raises an exception       (Lambda Errors, API GW 5XXError)
  4. Slow request → item="slow" sleeps before responding   (Lambda Duration, API GW Latency)

X-Ray instrumentation added:
  - patch_all() auto-creates SUBSEGMENTS for every boto3 call (DynamoDB, EventBridge),
    so the trace shows exactly how long each downstream call took.
  - A manual subsegment wraps the artificial "slow" delay so the bottleneck is
    explicit on the trace timeline.
  - MANUAL TRACE PROPAGATION: EventBridge does NOT carry the X-Ray trace header to
    the async consumer automatically. We copy the current trace header into the
    event Detail (_xray_trace) so the Processor Lambda can continue THIS trace
    instead of starting a disconnected one.
"""

import json
import os
import time
import uuid
import logging

import boto3
from aws_xray_sdk.core import xray_recorder, patch_all

# Auto-instrument boto3/botocore (and other supported libs). Every AWS SDK call
# made after this becomes an X-Ray subsegment of the current segment.
patch_all()

logger = logging.getLogger()
logger.setLevel(logging.INFO)

dynamodb = boto3.resource("dynamodb")
events_client = boto3.client("events")

TABLE_NAME = os.environ["ORDERS_TABLE"]
EVENT_BUS_NAME = os.environ.get("EVENT_BUS_NAME", "default")


def handler(event, context):
    """API Gateway proxy integration entry point."""
    logger.info("Received event: %s", json.dumps(event))

    try:
        body = json.loads(event.get("body") or "{}")
    except (json.JSONDecodeError, TypeError):
        return _response(400, {"error": "Invalid JSON in request body"})

    item = body.get("item")
    quantity = body.get("quantity")

    # Annotate the trace so you can filter/group by these in the X-Ray console.
    # Annotations are indexed + filterable; metadata is not indexed.
    segment = xray_recorder.current_segment()
    if segment is not None:
        segment.put_annotation("item", str(item))

    # --- Validation: missing required fields → 400 --------------------------
    if not item or quantity is None:
        return _response(400, {
            "error": "Missing required fields",
            "required": ["item", "quantity"],
        })

    # --- Forced error path → 500 (shows as a FAULT in X-Ray) ----------------
    if item == "fail":
        logger.error("Deliberate failure triggered (item='fail')")
        raise RuntimeError("Deliberate failure for CloudWatch Errors metric")

    # --- Slow path → explicit subsegment so the bottleneck is visible --------
    if item == "slow":
        delay = body.get("delay", 5)
        logger.info("Slow path: sleeping %s seconds", delay)
        subsegment = xray_recorder.begin_subsegment("artificial-delay")
        try:
            if subsegment is not None:
                subsegment.put_annotation("delay_seconds", delay)
            time.sleep(delay)
        finally:
            xray_recorder.end_subsegment()

    # --- Happy path: write order + emit event --------------------------------
    order_id = str(uuid.uuid4())

    # This put_item is auto-captured as a DynamoDB subsegment by patch_all().
    table = dynamodb.Table(TABLE_NAME)
    table.put_item(Item={
        "order_id": order_id,
        "item": item,
        "quantity": int(quantity),
        "status": "CREATED",
    })
    logger.info("Order %s written to DynamoDB", order_id)

    # --- Manual trace propagation across the EventBridge (async) boundary ----
    # Grab the current trace header. Format X-Ray expects downstream:
    #   Root=<trace_id>;Parent=<segment_id>;Sampled=1
    trace_header = _current_trace_header()

    # This put_events is auto-captured as an EventBridge subsegment.
    events_client.put_events(Entries=[{
        "Source": "orders.api",
        "DetailType": "OrderCreated",
        "Detail": json.dumps({
            "order_id": order_id,
            "item": item,
            "quantity": int(quantity),
            # Carry the trace context so the Processor can continue this trace.
            "_xray_trace": trace_header,
        }),
        "EventBusName": EVENT_BUS_NAME,
    }])
    logger.info("Event emitted to bus '%s' (trace header propagated)", EVENT_BUS_NAME)

    return _response(200, {
        "order_id": order_id,
        "status": "CREATED",
    })


def _current_trace_header():
    """Build an X-Ray trace header string from the current segment, or '' if none."""
    segment = xray_recorder.current_segment()
    if segment is None:
        return ""
    sampled = "1" if getattr(segment, "sampled", True) else "0"
    return f"Root={segment.trace_id};Parent={segment.id};Sampled={sampled}"


def _response(status_code, body):
    """Build an API Gateway proxy-compatible response."""
    return {
        "statusCode": status_code,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body),
    }
