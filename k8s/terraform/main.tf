locals {
  name = "${var.project_name}-${var.environment}"
}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_eks_cluster_auth" "this" {
  name = module.eks.cluster_name
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${local.name}-vpc"
  cidr = var.vpc_cidr

  azs             = slice(data.aws_availability_zones.available.names, 0, var.az_count)
  private_subnets = [for i in range(var.az_count) : cidrsubnet(var.vpc_cidr, 4, i)]
  public_subnets  = [for i in range(var.az_count) : cidrsubnet(var.vpc_cidr, 4, i + 8)]

  enable_nat_gateway = true
  single_nat_gateway = false

  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
  }
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = local.name
  cluster_version = var.kubernetes_version

  cluster_endpoint_public_access = true

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  enable_cluster_creator_admin_permissions = true

  eks_managed_node_groups = {
    default = {
      desired_size   = 3
      min_size       = 3
      max_size       = 10
      instance_types = ["m6i.large"]
      capacity_type  = "ON_DEMAND"

      labels = {
        workload = "general"
      }
    }

    worker = {
      desired_size   = 2
      min_size       = 2
      max_size       = 20
      instance_types = ["c6i.large"]
      capacity_type  = "ON_DEMAND"

      labels = {
        workload = "worker"
      }
    }
  }

  cluster_addons = {
    coredns             = {}
    kube-proxy          = {}
    vpc-cni             = {}
    aws-ebs-csi-driver  = {}
  }
}

resource "aws_ecr_repository" "api" {
  name                 = "${local.name}/api"
  image_tag_mutability = "MUTABLE"
}

resource "aws_ecr_repository" "worker" {
  name                 = "${local.name}/worker"
  image_tag_mutability = "MUTABLE"
}

resource "aws_ecr_repository" "scheduler" {
  name                 = "${local.name}/scheduler"
  image_tag_mutability = "MUTABLE"
}

resource "aws_ecr_repository" "dashboard" {
  name                 = "${local.name}/dashboard"
  image_tag_mutability = "MUTABLE"
}

resource "aws_route53_zone" "primary" {
  name = var.cloudflare_zone
}

resource "aws_route53_record" "bot" {
  zone_id = aws_route53_zone.primary.zone_id
  name    = "${var.domain_prefix}.${var.cloudflare_zone}"
  type    = "CNAME"
  ttl     = 300
  records = [var.cloudflare_tunnel_cname_target]
}

resource "cloudflare_record" "dashboard" {
  zone_id = data.cloudflare_zone.this.id
  name    = "dashboard"
  type    = "CNAME"
  content = var.cloudflare_tunnel_cname_target
  proxied = true
  ttl     = 1
}

data "cloudflare_zone" "this" {
  name = var.cloudflare_zone
}
