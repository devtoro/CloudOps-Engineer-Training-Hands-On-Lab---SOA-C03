# -----------------------------------------------------------------------------
# State backend — local, independent from the other labs.
# -----------------------------------------------------------------------------

terraform {
  backend "local" {
    path = "terraform.tfstate"
  }
}
