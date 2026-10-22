# -----------------------------------------------------------------------------
# State backend — local for now.
# To migrate to S3 later, replace this block with:
#
#   backend "s3" {
#     bucket         = "your-tf-state-bucket"
#     key            = "cloudops-lab/terraform.tfstate"
#     region         = "eu-central-1"
#     dynamodb_table = "terraform-locks"
#     encrypt        = true
#   }
#
# Then run: terraform init -migrate-state
# -----------------------------------------------------------------------------

terraform {
  backend "local" {
    path = "terraform.tfstate"
  }
}
