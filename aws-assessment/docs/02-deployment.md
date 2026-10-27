# 2. Deployment Flow & Infrastructure Provisioning

## Provisioning approach

Infrastructure is defined as a set of **ordered, loosely-coupled CloudFormation
stacks** that communicate through **exported outputs** (`Fn::ImportValue`). This
keeps each stack small, reusable, and independently updatable.

| Order | Stack | Template | Type |
|-------|-------|----------|------|
| 1 | Network | `01-network.yaml` | Infra |
| 2 | Security (SGs, IAM, OIDC) | `02-security.yaml` | Infra |
| 3 | Database | `03-database.yaml` | Infra |
| 4 | Shared (ECR, ALB) | `04-shared.yaml` | Infra |
| 5 | Monitoring | `07-monitoring.yaml` | Infra |
| 6 | ECS compute (containerized) | `05-ecs-compute.yaml` | Infra |
| 7 | Non-container compute (EB, S3/CF) | `06-noncontainer-compute.yaml` | Infra |

All stacks are named `${env}-${stack}` (e.g. `prod-network`), so the three
environments never collide.

### Reusability & maintainability
- **Parameterized** templates + per-environment JSON parameter files.
- **Conditions** (`IsProd`, `CreateSecondNat`, `HasCertificate`) vary behavior
  without duplicating templates.
- **Cross-stack exports** avoid hard-coded ARNs/IDs.
- `DeletionPolicy: Snapshot` on RDS protects data on stack deletion.

## One-time prerequisites

1. An AWS account with permission to create the stacks.
2. GitHub repository secrets and variables (see below).
3. (Optional) an **ACM certificate ARN** for HTTPS → pass via `CERT_ARN`.

### Required GitHub repository configuration

**Variables** (`Settings → Secrets and variables → Actions → Variables`):
| Name | Example |
|------|---------|
| `AWS_REGION` | `us-east-1` |

**Secrets** (per-environment, using GitHub Environments `dev`/`staging`/`prod`):
| Name | Purpose |
|------|---------|
| `AWS_INFRA_ROLE_ARN` | Role assumed by the **infra** pipeline (CloudFormation) |
| `AWS_DEPLOY_ROLE_ARN` | Role assumed by the **app** pipelines (ECS/EB/S3) |
| `AWS_INFRA_ROLE_ARN_DEV` | Dev infra role for PR change-set previews |

These roles are created by `02-security.yaml` via **GitHub OIDC** — no
long-lived AWS access keys are ever stored. Copy the `DeployRoleArn` /
`InfraRoleArn` stack outputs into the secrets above.

## Provisioning the infrastructure

### Option A — via the infra pipeline (recommended)
Push a change under `infrastructure/**`, or run the **Infrastructure
(CloudFormation)** workflow manually (`workflow_dispatch`) and pick the
environment. The pipeline lints templates, then runs `deploy-infra.sh`.

### Option B — locally
```bash
export GITHUB_ORG=<owner> GITHUB_REPO=<repo>
# optional:
export CERT_ARN=arn:aws:acm:us-east-1:...:certificate/xxxx
export ALERT_EMAIL=ops@example.com

infrastructure/scripts/deploy-infra.sh dev us-east-1
```

`deploy-infra.sh` deploys every stack in dependency order and is **idempotent**
(`--no-fail-on-empty-changeset`).

## Application deployment flow

Once infrastructure exists, application releases are fully automated and
**never touch infrastructure** (see [`03-cicd.md`](03-cicd.md)).

### Containerized (ECS)
1. Push to `apps/**` → `app-deploy-containerized.yml` runs.
2. Tests run for both apps.
3. Images built and pushed to ECR (`:<git-sha>` tag).
4. `update-ecs-service.sh` registers a new task-definition revision (image-only
   change) and updates the service.
5. ECS performs a rolling deploy; the **deployment circuit breaker** auto-rolls
   back if new tasks fail health checks.

### Non-containerized (EB + S3/CloudFront)
1. Backend: zip bundle → S3 → `create-application-version` → `update-environment`.
2. Frontend: `BUILD_TARGET=static next build` → `aws s3 sync` → CloudFront
   invalidation.

## Verifying a deployment
```bash
# Containerized endpoint
ALB=$(aws cloudformation list-exports --query "Exports[?Name=='dev-LoadBalancerDNS'].Value" --output text)
curl "http://$ALB/api/health"          # frontend health
curl "http://$ALB/health"              # backend health
curl "http://$ALB/api/backend/info"    # backend + DB status
```
