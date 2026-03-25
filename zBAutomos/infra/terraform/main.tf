provider "aws" {
  region = "ap-southeast-1"
}

resource "aws_eks_cluster" "zba" {
  name     = "zba-cluster"
  role_arn = "arn:aws:iam::123:role/eks"

  vpc_config {
    subnet_ids = ["subnet-12345678", "subnet-87654321"]
  }
}
