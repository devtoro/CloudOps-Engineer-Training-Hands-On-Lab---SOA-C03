terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
  }
}

# Primary region — where the app, rules, and auto-heal live.
provider "aws" {
  region  = var.region
  profile = var.aws_profile

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
      Training    = "cloudops"
    }
  }
}

# Secondary region — the destination for the cross-Region bus-forwarding demo.
# Referenced via `provider = aws.secondary` in the cross-region module.
provider "aws" {
  alias   = "secondary"
  region  = var.secondary_region
  profile = var.aws_profile

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
      Training    = "cloudops"
    }
  }
}
