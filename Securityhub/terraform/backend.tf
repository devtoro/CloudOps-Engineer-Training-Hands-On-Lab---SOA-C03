# -----------------------------------------------------------------------------
# State backend — local, independent from the other labs.
# NOTE: This lab is REFERENCE CODE. It is validated but not intended to be
# applied by default (Security Hub + GuardDuty incur cost and change account
# security posture). Apply only if you deliberately choose to.
# -----------------------------------------------------------------------------

terraform {
  backend "local" {
    path = "terraform.tfstate"
  }
}
