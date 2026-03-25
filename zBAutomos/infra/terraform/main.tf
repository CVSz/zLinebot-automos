provider "aws" {
  region = "ap-southeast-1"
}

module "eks" {
  source          = "terraform-aws-modules/eks/aws"
  cluster_name    = "zba-cluster"
  cluster_version = "1.29"
  vpc_id          = "vpc-xxxx"
  subnet_ids      = ["subnet-a", "subnet-b"]
}
