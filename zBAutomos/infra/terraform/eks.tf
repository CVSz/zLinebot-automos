terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

locals {
  cluster_name = "zba-cluster"
  tags = {
    Project = "zBAutomos"
    Env     = "prod"
  }
}
