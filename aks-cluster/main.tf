terraform {
  backend "remote" {
    hostname      = "app.terraform.io"
    organization  = "$TFC_ORG"

    workspaces {
      name = "$TFC_WORKSPACE"
    }
  }
}