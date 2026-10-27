# 3. CI/CD Workflow

## Tooling
- **GitHub Actions** orchestrates build, test, and deploy.
- **AWS-native deploy services** carry out the actual rollout: **ECS** rolling
  deployments with a deployment **circuit breaker** (auto rollback), and
  **Elastic Beanstalk** managed application-version deployments. ECR stores
  images; CloudFront serves the static frontend.
- **GitHub OIDC** issues short-lived credentials — no static AWS keys.

## Pipelines

| Workflow | Trigger (`paths`) | What it does | Touches infra? |
|----------|-------------------|--------------|----------------|
| `infra.yml` | `infrastructure/**` | Lint + deploy CloudFormation stacks | **Yes (only here)** |
| `app-deploy-containerized.yml` | `apps/**` | Test → build images → update ECS | No |
| `app-deploy-noncontainerized.yml` | `apps/**` | Test → EB version + S3/CloudFront | No |

## Requirement #4 — separating application vs infrastructure changes

This is enforced structurally, not by convention:

1. **Path-filtered triggers.** The app pipelines only fire on `apps/**`; the
   infra pipeline only fires on `infrastructure/**`. A commit that changes only
   application code can therefore *never* start an infrastructure deployment,
   and vice-versa.

2. **Different mechanisms.** App pipelines call `ecs update-service` /
   `elasticbeanstalk update-environment` / `s3 sync`. They **do not run
   `cloudformation deploy`**. Only `infra.yml` (and `deploy-infra.sh`) ever
   invoke CloudFormation.

3. **Different IAM roles.** App pipelines assume `AWS_DEPLOY_ROLE_ARN`, whose
   policy allows ECR push, ECS/EB update, and S3/CloudFront — **but not**
   CloudFormation stack mutation. The infra pipeline assumes the separate
   `AWS_INFRA_ROLE_ARN`. Even a mistaken command cannot cross the boundary.

4. **Immutable image tags.** App deploys register a new task-definition revision
   that differs only by image tag (`:<git-sha>`), leaving every other infra-managed
   property untouched.

```
commit changes apps/**            commit changes infrastructure/**
        │                                   │
        ▼                                   ▼
app-deploy-*.yml                        infra.yml
  (DEPLOY_ROLE)                          (INFRA_ROLE)
  ECS / EB / S3  ← no CFN                cloudformation deploy
```

## Pipeline stages

### Containerized app pipeline
```
test-backend ─┐
              ├─► deploy (build→push→ECS update→wait stable)
test-frontend ┘
```
- `pytest` for backend, `next build` for frontend act as the CI gate.
- Deploy only runs after both test jobs pass.
- `aws ecs wait services-stable` blocks until the rollout is healthy.

### Infra pipeline
```
validate (cfn-lint) ─► [PR] plan / validate-template
                    └─► [main or dispatch] deploy all stacks
```
- On **pull requests** it only validates/previews — it never mutates infra.
- On **main push** or manual dispatch it deploys to the chosen environment
  (gated by GitHub **Environments**, which can require manual approval for prod).

## Promotion across environments
- `dev` deploys on merge to `main`.
- `staging` / `prod` are driven by `workflow_dispatch` with an environment input,
  protected by GitHub Environment approval rules (configure required reviewers
  on the `prod` environment for a manual gate).
