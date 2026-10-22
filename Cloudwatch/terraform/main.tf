# =============================================================================
# Root module — wires all child modules together
#
# Each module maps to one AWS "part" of the Order Processing Platform.
# Modules are added one checkpoint at a time during Phase 1.
#
# Naming convention passed to all modules:
#   prefix = "${var.project_name}-${var.environment}"
#   e.g.   "cloudops-lab-dev"
# =============================================================================

locals {
  prefix = "${var.project_name}-${var.environment}"
}

# -----------------------------------------------------------------------------
# Checkpoint 2 — DynamoDB (orders table)
# -----------------------------------------------------------------------------
module "dynamodb" {
  source      = "./modules/dynamodb"
  prefix      = local.prefix
  environment = var.environment
}

# -----------------------------------------------------------------------------
# Checkpoint 3 — Lambda: Orders (API-facing)
# -----------------------------------------------------------------------------
module "lambda_orders" {
  source              = "./modules/lambda-orders"
  prefix              = local.prefix
  environment         = var.environment
  dynamodb_table_name = module.dynamodb.table_name
  dynamodb_table_arn  = module.dynamodb.table_arn

  # EventBridge custom bus (built in Checkpoint 5)
  event_bus_name = module.eventbridge.bus_name
  event_bus_arn  = module.eventbridge.bus_arn
}

# -----------------------------------------------------------------------------
# Checkpoint 4 — API Gateway (REST API)
# -----------------------------------------------------------------------------
module "api_gateway" {
  source              = "./modules/api-gateway"
  prefix              = local.prefix
  environment         = var.environment
  lambda_function_arn = module.lambda_orders.function_arn
  lambda_invoke_arn   = module.lambda_orders.invoke_arn
}

# -----------------------------------------------------------------------------
# Checkpoint 5 — EventBridge + Lambda: Processor
# -----------------------------------------------------------------------------
module "lambda_processor" {
  source      = "./modules/lambda-processor"
  prefix      = local.prefix
  environment = var.environment
}

module "eventbridge" {
  source               = "./modules/eventbridge"
  prefix               = local.prefix
  environment          = var.environment
  processor_lambda_arn = module.lambda_processor.function_arn
}
