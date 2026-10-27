# 1. Architecture Overview

## High-level design

The platform runs across **two Availability Zones** for high availability. A
single VPC hosts a public tier (ALB, NAT) and a private tier (application
compute + database). Public users reach the applications only through the
Application Load Balancer (containerized) or CloudFront/EB load balancer
(non-containerized); application and database tiers are never exposed directly.

```
Internet
   │
   ▼
Application Load Balancer (public subnets, 2 AZs)
   │  path /api/backend/* , /health  →  Backend target group
   │  everything else                →  Frontend target group
   ▼
Private subnets (2 AZs)
   ├── Frontend tasks (ECS Fargate)      ── or ── S3 + CloudFront (non-container)
   ├── Backend tasks  (ECS Fargate)      ── or ── Elastic Beanstalk EC2 ASG
   └── RDS PostgreSQL (Multi-AZ in prod)
          ▲
          └── credentials from AWS Secrets Manager
```

See the rendered diagram in [`../diagrams/architecture.md`](../diagrams/architecture.md).

## AWS services used

| Category | Service | Purpose |
|----------|---------|---------|
| **Networking** | VPC, Subnets, IGW, NAT Gateway, Route Tables | Isolated 2-AZ network with public/private separation |
| | Application Load Balancer | Public entry, path-based routing to FE/BE, health checks |
| **Compute (containerized)** | ECS Fargate, ECR | Serverless containers for FE & BE; private image registry |
| **Compute (non-containerized)** | Elastic Beanstalk (EC2 Auto Scaling), S3, CloudFront | Managed EC2 backend; static frontend via CDN |
| **Database** | RDS PostgreSQL | Managed, encrypted, Multi-AZ, automated backups |
| **Security** | IAM, Secrets Manager, Security Groups, OIDC provider | Least-privilege access, secret storage, keyless CI/CD |
| **Monitoring** | CloudWatch (alarms, dashboard, logs), Container Insights, SNS | Metrics, logs, alerting |
| **IaC** | CloudFormation | Declarative, versioned infrastructure |
| **CI/CD** | GitHub Actions + ECS/EB native deploys | Build, test, deploy automation |

## Design decisions

### Why two compute approaches?
The assessment explicitly requires both. We chose:
- **Containerized → ECS Fargate.** No servers to patch, scales to zero cost when
  idle (dev), native ALB + Secrets Manager + CloudWatch integration, and a
  built-in **deployment circuit breaker** that auto-rolls-back failed releases.
  Simpler than EKS for a two-service workload while remaining fully production-grade.
- **Non-containerized → Elastic Beanstalk (backend) + S3/CloudFront (frontend).**
  EB gives managed EC2 Auto Scaling, health, and immutable deploys without
  hand-rolling an ASG + user-data. A Next.js static export on S3+CloudFront is
  the canonical non-container frontend pattern — cheap, globally cached, no servers.

### Why RDS PostgreSQL (not self-managed)?
Managed backups, Multi-AZ failover, encryption at rest (KMS), Performance
Insights, and automated minor-version patching. Multi-AZ is forced on in `prod`.

### Why an ALB with path-based routing?
A single public endpoint serves both apps. `/, /_next/*` → frontend;
`/api/backend/*` and `/health` → backend. This keeps one TLS certificate, one
DNS name, and avoids CORS complexity.

### High availability
- 2 AZs for subnets, ALB, ECS tasks, EB instances, and RDS (Multi-AZ in prod).
- Minimum 2 tasks/instances per service in staging/prod.
- One NAT Gateway per AZ in prod (`SingleNatGateway=false`); single NAT in
  dev/staging to save cost.

### Scalability
- ECS **target-tracking auto scaling** on CPU (example on backend; mirrors to
  frontend). EB uses an Auto Scaling Group (min 2 / max 4).
- RDS storage autoscaling via `MaxAllocatedStorage`.
- CloudFront absorbs frontend read traffic in the non-container path.

## Environment strategy (dev / staging / prod)
Each environment is a **fully isolated set of stacks** keyed by `EnvironmentName`,
with its own VPC CIDR (`10.0/10.1/10.2`), sizing, and backup policy driven by
[`infrastructure/parameters/*.json`](../infrastructure/parameters). Prod enables
Multi-AZ, deletion protection, 30-day backups, and per-AZ NAT automatically.
