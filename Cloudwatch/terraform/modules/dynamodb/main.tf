# -----------------------------------------------------------------------------
# DynamoDB — Orders table
#
# Provisioned mode with intentionally tiny capacity (1 RCU / 1 WCU).
# This makes it trivial to saturate the table and observe:
#   - ConsumedReadCapacityUnits
#   - ConsumedWriteCapacityUnits
#   - ThrottledRequests
#   - ReadThrottleEvents / WriteThrottleEvents
#
# CloudOps exam note:
#   ThrottledRequests is a per-partition metric (counts requests rejected).
#   ReadThrottleEvents / WriteThrottleEvents are per-table metrics.
#   Both appear under the AWS/DynamoDB namespace, but with different dimensions.
# -----------------------------------------------------------------------------

resource "aws_dynamodb_table" "orders" {
  name         = "${var.prefix}-orders"
  billing_mode = "PROVISIONED"

  read_capacity  = var.read_capacity
  write_capacity = var.write_capacity

  # Simple key schema — order_id is enough for our observability lab
  hash_key = "order_id"

  attribute {
    name = "order_id"
    type = "S"
  }

  # Point-in-time recovery off (lab, not production)
  point_in_time_recovery {
    enabled = false
  }

  tags = {
    Name = "${var.prefix}-orders"
  }
}
