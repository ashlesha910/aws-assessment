# Production-Grade AWS Architecture — Coditude Assessment

A complete, production-ready deployment of a **Next.js frontend**, a **Python
(FastAPI) backend**, and a **PostgreSQL** database on AWS — provisioned with
**CloudFormation**, deployed with **GitHub Actions + AWS-native services**, and
documented end to end.

The solution deploys the applications using **two approaches** as required:

| Approach | Frontend | Backend | Database |
|----------|----------|---------|----------|
| **Containerized** | Next.js on **ECS Fargate** | FastAPI on **ECS Fargate** | **RDS PostgreSQL** |
| **Non-Containerized** | Next.js static export on **S3 + CloudFront** | FastAPI on **Elastic Beanstalk** (managed EC2 Auto Scaling) | **RDS PostgreSQL** |

Both approaches share the same VPC, RDS, Secrets Manager, and monitoring stacks.

---

## Repository layout

```
.
├── apps/
│   ├── backend/              # Python FastAPI app + Dockerfile + tests + Procfile (EB)
│   └── frontend/             # Next.js app + Dockerfile (standalone & static export)
├── infrastructure/
│   ├── templates/            # CloudFormation stacks (network, security, db, compute…)
│   ├── parameters/           # dev / staging / prod parameter files
│   └── scripts/              # deploy-infra.sh, update-ecs-service.sh
├── .github/workflows/
│   ├── infra.yml                         # Infra-only pipeline (CloudFormation)
│   ├── app-deploy-containerized.yml      # App-only pipeline (ECS)
│   └── app-deploy-noncontainerized.yml   # App-only pipeline (EB + S3/CloudFront)
├── diagrams/                 # Architecture diagram (Mermaid source + rendered)
└── docs/                     # Full assessment documentation
```

## Documentation

All required documentation lives in [`docs/`](docs/):

- [`01-architecture.md`](docs/01-architecture.md) — Architecture overview, AWS services, design decisions
- [`02-deployment.md`](docs/02-deployment.md) — Deployment flow & infrastructure provisioning
- [`03-cicd.md`](docs/03-cicd.md) — CI/CD workflow & app-vs-infra separation
- [`04-security.md`](docs/04-security.md) — Security & secrets management
- [`05-rollback.md`](docs/05-rollback.md) — Rollback strategy
- [`diagrams/architecture.md`](diagrams/architecture.md) — Architecture diagram

## Quick start

```bash
# 1. One-time: provision infrastructure for an environment (run locally or via infra.yml)
export GITHUB_ORG=<owner> GITHUB_REPO=<repo>
infrastructure/scripts/deploy-infra.sh dev us-east-1

# 2. App deploys happen automatically on push to apps/** via GitHub Actions,
#    or run the helper manually:
infrastructure/scripts/update-ecs-service.sh dev-cluster dev-backend backend <image-uri>
```

See [`docs/02-deployment.md`](docs/02-deployment.md) for the full walkthrough,
including the GitHub OIDC setup and required repository secrets/variables.

## How the assessment requirements are met

| Requirement | Where |
|-------------|-------|
| 1. Cloud infrastructure (networking, compute, DB, monitoring, security) | `infrastructure/templates/01`–`07` |
| 1. Containerized **and** non-containerized deployment | `05-ecs-compute.yaml` + `06-noncontainer-compute.yaml` |
| 2. IaC with CloudFormation, reusable, dev/staging/prod | `templates/` + `parameters/` |
| 3. CI/CD with GitHub Actions + AWS-native services | `.github/workflows/` + ECS/EB/CodeDeploy-style flow |
| 4. Separate app vs infra deployments | path-filtered workflows (see `docs/03-cicd.md`) |
| 5. Security & secrets management | Secrets Manager, IAM least-privilege, OIDC (`docs/04-security.md`) |
| 6. Documentation (overview, flow, CI/CD, provisioning, security, rollback) | `docs/` |
