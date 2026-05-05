# AWS Production Infrastructure — Terraform

## Architecture

```
Internet
   │
   ├──► CloudFront (CDN + HTTPS + security headers)
   │         │  X-Origin-Verify secret header
   │         ▼
   ├──► ALB (Application Load Balancer)
   │         │
   │         ▼
   │    ECS Fargate Tasks (nginx / your app)
   │         │
   │    ┌────┴────┐
   │    │         │
   │    ▼         ▼
   │   RDS      S3 Bucket
   │  (MySQL)   (assets)
   │
   └──► EKS API Server (IP-whitelisted)
             │
             ▼
        EKS Nodes (private subnets, via NAT)

State: S3 bucket (native locking, no DynamoDB needed)
Scheduler: EventBridge → Lambda → ECS scale 0/N
```

## Modules

| Module | Purpose |
|---|---|
| `vpc` | VPC, subnets (multi-AZ), IGW, NAT GW, route tables, flow logs |
| `alb` | Application Load Balancer, target group, listeners, access logs |
| `ecs` | ECS cluster, task definition, service, IAM, CloudWatch |
| `ec2` | EC2 launch template + ASG for ECS EC2 launch type |
| `rds` | RDS MySQL/Postgres, subnet group, param group, encryption |
| `s3` | S3 bucket with versioning, SSE, lifecycle, access logging |
| `cloudfront` | CloudFront CDN, security headers, origin verification |
| `eks` | EKS cluster, managed node group, OIDC, add-ons, IP whitelist |
| `lambda-scheduler` | Lambda + EventBridge for ECS start/stop automation |

---

## Prerequisites

- Terraform >= 1.10.0
- AWS CLI v2 configured (`aws configure`)
- kubectl (for EKS)

```bash
# Verify
terraform version    # must be >= 1.10.0
aws sts get-caller-identity
kubectl version --client
```

---

## Quick Start

### Step 1 — Bootstrap backend (one-time only)

```bash
cd scripts/
terraform init
terraform apply -var="project_name=myapp" -var="aws_region=us-east-2"
cd ..
```

This creates:
- S3 bucket `myapp-tfstate-<account-id>` for state storage
- DynamoDB table (used by bootstrap only; main infra uses S3 native locking)

### Step 2 — Init

```bash
terraform init \
  -backend-config="bucket=myapp-tfstate-<ACCOUNT_ID>" \
  -backend-config="key=dev/terraform.tfstate" \
  -backend-config="region=us-east-2" \
  -backend-config="encrypt=true"
```

> S3 native locking is automatic (Terraform >= 1.10). No DynamoDB needed.

### Step 3 — Plan

```bash
terraform plan -var-file=environments/dev.tfvars
```

### Step 4 — Apply

```bash
terraform apply -var-file=environments/dev.tfvars
```

### Step 5 — Configure kubectl (after EKS apply)

```bash
aws eks update-kubeconfig --name myapp-dev-eks --region us-east-2
kubectl get nodes
kubectl get pods -A
```

### Destroy

```bash
terraform destroy -var-file=environments/dev.tfvars
```

---

## Without Makefile — All Commands

```bash
# Format check
terraform fmt -recursive -check

# Auto-format
terraform fmt -recursive

# Validate
terraform validate

# Init (dev)
terraform init \
  -backend-config="bucket=myapp-tfstate-<ACCOUNT_ID>" \
  -backend-config="key=dev/terraform.tfstate" \
  -backend-config="region=us-east-2" \
  -backend-config="encrypt=true" \
  -reconfigure

# Plan and save
terraform plan -var-file=environments/dev.tfvars -out=dev.tfplan

# Apply saved plan
terraform apply dev.tfplan

# Show outputs
terraform output
terraform output -raw eks_kubeconfig_command

# Show state
terraform state list
terraform state show module.vpc.aws_vpc.main

# Destroy
terraform destroy -var-file=environments/dev.tfvars
```

---

## Targeting Specific Services

Use `-target` to provision or update individual modules without touching others.

> **Rule:** Always provision `module.vpc` before any other module — everything depends on it.

### Provision in dependency order

```bash
# 1. Network foundation (always first)
terraform apply -var-file=environments/dev.tfvars -target=module.vpc

# 2. Storage (no dependencies)
terraform apply -var-file=environments/dev.tfvars -target=module.s3

# 3. Load balancer (needs VPC)
terraform apply -var-file=environments/dev.tfvars -target=module.alb

# 4. Database (needs VPC + ECS SG — apply ECS first for the SG)
terraform apply -var-file=environments/dev.tfvars -target=module.ecs
terraform apply -var-file=environments/dev.tfvars -target=module.rds

# 5. Optional modules (independent after VPC)
terraform apply -var-file=environments/dev.tfvars -target=module.cloudfront
terraform apply -var-file=environments/dev.tfvars -target="module.eks[0]"
terraform apply -var-file=environments/dev.tfvars -target="module.lambda_scheduler[0]"
```

### Update only one service

```bash
# Redeploy only ECS service
terraform apply -var-file=environments/dev.tfvars -target=module.ecs

# Update only RDS parameter group
terraform apply -var-file=environments/dev.tfvars -target=module.rds.aws_db_parameter_group.main

# Scale ECS desired count
terraform apply -var-file=environments/dev.tfvars -target=module.ecs.aws_ecs_service.main
```

### Module dependency map

```
module.vpc
  └── module.alb        (needs vpc_id, public_subnet_ids)
  └── module.s3         (no VPC dependency)
  └── module.ecs        (needs vpc_id, private_subnet_ids, alb outputs)
      └── module.rds    (needs ecs_security_group_id)
  └── module.eks[0]     (needs vpc_id, subnet_ids)
  └── module.cloudfront[0]  (needs alb_dns_name)
  └── module.lambda_scheduler[0]  (needs ecs cluster/service names)
```

---

## Environment Management

| Environment | File | Key differences |
|---|---|---|
| dev | `environments/dev.tfvars` | t3.micro RDS, 1 ECS task, scheduler ON, SPOT EKS |
| staging | `environments/staging.tfvars` | t3.small RDS, 2 tasks, Multi-AZ off |
| prod | `environments/prod.tfvars` | r6g.large RDS, 3 tasks, Multi-AZ ON, scheduler OFF |

```bash
# Staging
terraform init -backend-config="key=staging/terraform.tfstate" ...
terraform apply -var-file=environments/staging.tfvars

# Production
terraform init -backend-config="key=prod/terraform.tfstate" ...
terraform apply -var-file=environments/prod.tfvars
```

---

## S3 Native State Locking

No DynamoDB needed. Terraform >= 1.10 handles locking via S3 conditional writes.

```hcl
# backend.tf
terraform {
  backend "s3" {
    bucket       = "myapp-tfstate-<ACCOUNT_ID>"
    key          = "dev/terraform.tfstate"
    region       = "us-east-2"
    encrypt      = true
    use_lockfile = true  # S3 native lock — no DynamoDB
  }
}
```

How it works:
- On `plan`/`apply`, Terraform creates `dev/terraform.tfstate.tflock` in S3 using `If-None-Match: *`
- If another apply is running and holds the lock, the second one fails immediately
- Lock is released (file deleted) when the operation completes or is interrupted

---

## EKS IP Whitelisting

The EKS API server is publicly accessible **only from specific IPs**.

```hcl
# environments/dev.tfvars
eks_api_server_allowed_cidrs = [
  "203.0.113.10/32",   # developer 1 home IP
  "198.51.100.20/32",  # developer 2 office IP
  "10.0.0.0/8",        # internal VPC (private endpoint always works)
]
```

Get your current public IP:
```bash
curl -s https://checkip.amazonaws.com
```

What this enforces:
- `endpoint_public_access = true` — API is reachable from internet
- `public_access_cidrs` — only listed IPs can connect
- `endpoint_private_access = true` — cluster nodes always work internally

Verify:
```bash
# From a whitelisted IP — should succeed
kubectl get nodes

# From a non-whitelisted IP — should fail with connection timeout
```

---

## CloudFront Origin Verification

CloudFront adds `X-Origin-Verify: <secret>` to all requests to the ALB.
You can add an ALB listener rule to block requests missing this header:

```hcl
# Add to modules/alb/main.tf for full lockdown:
resource "aws_lb_listener_rule" "verify_cloudfront" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 1

  condition {
    http_header {
      http_header_name = "X-Origin-Verify"
      values           = [var.origin_verify_secret]
    }
  }

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.main.arn
  }
}
```

---

## Code Strength Assessment

### Strong
| Area | Detail |
|---|---|
| Modularity | All services in isolated modules with clean input/output contracts |
| No hardcoding | Every value is a variable with validated types |
| Encryption at rest | RDS (storage_encrypted), S3 (AES256), state (SSE) |
| Network isolation | Private subnets for ECS/RDS/EKS nodes; NAT GW for outbound |
| Least privilege IAM | Separate roles per service, scoped policies |
| IMDSv2 enforced | EC2 and EKS launch templates require token-based metadata |
| State locking | S3 native locking prevents concurrent apply corruption |
| Circuit breaker | ECS deployment circuit breaker with auto-rollback |
| Flow logs | VPC flow logs → CloudWatch for network auditing |
| IRSA | EKS OIDC provider for pod-level IAM without node credentials |

### Hardenable (future work)
| Area | Improvement |
|---|---|
| RDS password | Move to AWS Secrets Manager + rotation |
| KMS encryption | Replace AES256 with customer-managed KMS keys |
| WAF | Add AWS WAF v2 to ALB and CloudFront |
| GuardDuty | Enable per-account threat detection |
| ALB → CF lockdown | Add listener rule to reject non-CloudFront requests |
| EKS network policy | Deploy Calico or AWS VPC CNI network policies |
| Secrets scanning | Add git-secrets or truffleHog to CI pipeline |

---

## Cost Estimates (dev environment)

| Resource | Cost |
|---|---|
| 2x NAT Gateway | ~$0.09/hr ($2.16/day) |
| ALB | ~$0.008/hr |
| RDS db.t3.micro | ~$0.017/hr |
| ECS Fargate (0.25 vCPU) | ~$0.012/hr |
| EKS Control Plane | $0.10/hr ($2.40/day) |
| EKS Node t3.medium (on-demand) | ~$0.047/hr |
| CloudFront | ~$0.0085/10k requests |
| **Total (running 8hr/day)** | **~$5–7/day** |

> Use the scheduler (`enable_scheduler = true`) to auto-stop ECS at 7pm and start at 7am.
> Always `terraform destroy` dev environments when not in use.

---

## Troubleshooting

```bash
# EKS node not joining cluster
aws eks describe-nodegroup --cluster-name myapp-dev-eks --nodegroup-name myapp-dev-eks-node-group --region us-east-2

# ECS task failing to start
aws ecs describe-tasks --cluster myapp-dev-cluster --tasks <task-arn> --region us-east-2

# State lock stuck (from a crashed apply)
# S3 native lock — delete the lock file manually:
aws s3 rm s3://myapp-tfstate-<ACCOUNT_ID>/dev/terraform.tfstate.tflock

# Refresh state after manual AWS changes
terraform refresh -var-file=environments/dev.tfvars

# Import existing resource into state
terraform import -var-file=environments/dev.tfvars module.vpc.aws_vpc.main vpc-xxxxxxxx
```
