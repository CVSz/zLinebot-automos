module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = "zlinebot-cluster"
  cluster_version = "1.29"

  vpc_id     = "vpc-xxxxxxxx"
  subnet_ids = ["subnet-aaaa", "subnet-bbbb"]

  eks_managed_node_groups = {
    default = {
      instance_types = ["t3.large"]
      min_size       = 1
      max_size       = 3
      desired_size   = 2
    }
  }
}
  vpc_id     = var.vpc_id
  subnet_ids = var.private_subnet_ids

  eks_managed_node_groups = {
    default = {
      desired_size = 2
      max_size     = 10
      min_size     = 2

      instance_types = ["t3.large"]
      capacity_type  = "ON_DEMAND"
    }
  }
}

variable "vpc_id" {
  type        = string
  description = "VPC id for EKS cluster"
}

variable "private_subnet_ids" {
  type        = list(string)
  description = "Private subnets used by EKS"
}
