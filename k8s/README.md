# zLineBot-Automos Kubernetes + Terraform (AWS EKS)

This folder is a production-oriented starting point for deploying zLineBot-Automos end-to-end on AWS EKS with Cloudflare-based public webhook routing.

## Structure

- `config/`: namespace, ConfigMap, and example Secret manifest.
- `deployments/`: API, worker, scheduler, and dashboard workloads.
- `database/`: PostgreSQL and Redis StatefulSets.
- `services/`: ClusterIP services for application and data-plane discovery.
- `ingress/`: NGINX ingress + cloudflared tunnel deployment.
- `volumes/`: standalone PVC examples.
- `autoscaling/`: HPAs for API/worker.
- `terraform/`: EKS, VPC, ECR, Route53, and Cloudflare DNS provisioning.

## Quick start

1. Create infrastructure:
   ```bash
   cd k8s/terraform
   terraform init
   terraform plan
   terraform apply
   ```
2. Create secrets:
   ```bash
   kubectl apply -f k8s/config/namespace.yaml
   kubectl apply -f k8s/config/secrets.example.yaml
   ```
   Edit `secrets.example.yaml` values before applying in production.
3. Deploy workloads:
   ```bash
   kubectl apply -k k8s
   ```
4. Confirm runtime:
   ```bash
   kubectl get pods -n zlinebot
   kubectl get ingress -n zlinebot
   ```

## Notes

- Use External Secrets or AWS Secrets Manager + CSI driver for production secrets.
- Replace `zeaz/zlinebot-*` images with your ECR repositories from Terraform outputs.
- Validate your Cloudflare tunnel and set `CLOUDFLARE_TUNNEL_TOKEN` in `bot-secrets`.

## Documentation Refresh — 2026-03-26 (UTC)

- Revalidated Kubernetes/Terraform onboarding narrative with current manifest layout.
- Audit scope: repository-wide markdown and operational-documentation verification pass.

