# -----------------------------------------------------------------------------
# State backend — local, independent from the Cloudwatch and Cloudtrail labs.
# To migrate to S3 later, replace this block with an s3 backend and run
# `terraform init -migrate-state`.
# -----------------------------------------------------------------------------

terraform {
  backend "local" {
    path = "terraform.tfstate"
  }
}
