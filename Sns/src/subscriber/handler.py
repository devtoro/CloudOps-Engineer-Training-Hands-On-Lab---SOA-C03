"""
SNS subscriber Lambda for the SNS lab.

Invoked by SNS when a message matches this subscription's filter policy. Logs
the message plus its attributes so you can see filtering + message attributes
in action.

SNS → Lambda delivers the message in event["Records"][0]["Sns"]:
  - Message            : the body
  - MessageAttributes  : the attributes used for filtering
"""

import json
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)


def handler(event, context):
    for record in event.get("Records", []):
        sns = record.get("Sns", {})
        message = sns.get("Message", "")
        attributes = sns.get("MessageAttributes", {})
        logger.info("SNS message: %s", message)
        logger.info("Attributes: %s", json.dumps(attributes))
    return {"received": len(event.get("Records", []))}
