"""
Custom AWS Config rule — S3 bucket naming check (deliberately simple / "dummy").

Purpose: demonstrate the custom-rule integration end to end, not to be useful.

Flow (how a custom Config rule works):
  1. Config detects a change (or periodic trigger) and INVOKES this Lambda,
     passing an `invokingEvent` (the configuration item) and `resultToken`.
  2. The Lambda decides COMPLIANT / NON_COMPLIANT / NOT_APPLICABLE.
  3. The Lambda calls config.put_evaluations(...) with the verdict and the
     resultToken. That is how the result gets back to Config.

Rule logic (dummy): an S3 bucket is NON_COMPLIANT if its name contains the
forbidden substring (default "public"); otherwise COMPLIANT. Non-S3 resources
are NOT_APPLICABLE.
"""

import json
import os
import boto3

config = boto3.client("config")

FORBIDDEN_SUBSTRING = os.environ.get("FORBIDDEN_SUBSTRING", "public")
APPLICABLE_TYPE = "AWS::S3::Bucket"


def handler(event, context):
    invoking_event = json.loads(event["invokingEvent"])
    result_token = event["resultToken"]

    configuration_item = invoking_event.get("configurationItem", {})
    resource_type = configuration_item.get("resourceType")
    resource_id = configuration_item.get("resourceId")
    capture_time = configuration_item.get("configurationItemCaptureTime")

    # Only evaluate S3 buckets.
    if resource_type != APPLICABLE_TYPE:
        compliance = "NOT_APPLICABLE"
        annotation = f"Rule applies only to {APPLICABLE_TYPE}."
    else:
        name = resource_id or ""
        if FORBIDDEN_SUBSTRING in name.lower():
            compliance = "NON_COMPLIANT"
            annotation = f"Bucket name contains forbidden substring '{FORBIDDEN_SUBSTRING}'."
        else:
            compliance = "COMPLIANT"
            annotation = "Bucket name is acceptable."

    config.put_evaluations(
        Evaluations=[
            {
                "ComplianceResourceType": resource_type,
                "ComplianceResourceId": resource_id,
                "ComplianceType": compliance,
                "Annotation": annotation[:256],
                "OrderingTimestamp": capture_time,
            }
        ],
        ResultToken=result_token,
    )

    return {"compliance": compliance, "resource": resource_id}
