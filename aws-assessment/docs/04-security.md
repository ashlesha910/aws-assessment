# 4. Security & Secrets Management

## Secret storage
- **Database credentials** are generated and stored in **AWS Secrets Manager**
  (`${env}/database/credentials`). The master password is created by
  `GenerateSecretString` — it never appears in a template, parameter file, or
  git history.
- A **`SecretTargetAttachment`** enriches the secret with the live RDS
  `host`/`port`/`dbname`, so applications resolve a single secret for the full
  connection string.
- The secret is **rotation-ready** (Secrets Manager rotation can be attached
  without app changes).

## Secure application configuration
- **Containerized:** the ECS task definition injects the DB secret as a
  container `secrets` entry (`ValueFrom` the Secrets Manager ARN). The value is
  delivered to the container at start and is **not** visible in the task
  definition, environment printouts, or CloudFormation.
- **Non-containerized:** the EB instance role is granted
  `secretsmanager:GetSecretValue` for exactly that one secret; the app reads it
  at runtime via `DB_SECRET_ARN`. The backend code (`app.py`) fetches it with
  `boto3` and never logs the value.
- Non-secret config (environment name, backend URL) is passed as plain
  environment variables.

## Access control (IAM least-privilege)
- **Security groups** form a strict chain: ALB (`:80/:443` from internet) →
  app SG (from ALB only) → DB SG (`:5432` from app SG only). The database has
  **no public access** and lives in private subnets.
- **Task/instance roles** can read **only** the one DB secret ARN — not all of
  Secrets Manager.
- **ECS execution role** is limited to the managed `AmazonECSTaskExecutionRolePolicy`
  plus read access to the single secret.
- **`iam:PassRole`** on the deploy role is constrained with a condition to
  `ecs-tasks.amazonaws.com` / `elasticbeanstalk.amazonaws.com`.

## Keyless CI/CD (GitHub OIDC)
- `02-security.yaml` provisions a **GitHub OIDC provider** and two roles:
  - `${env}-github-actions-deploy` — app deploys (ECR/ECS/EB/S3/CloudFront).
  - `${env}-github-actions-infra` — CloudFormation only.
- The trust policy restricts assumption to
  `repo:<org>/<repo>:*` via the `sub` claim, so only workflows in *your*
  repository can assume the roles. **No long-lived AWS keys are stored in
  GitHub.**
- The two roles are **separated by duty** (see `03-cicd.md`), so an app pipeline
  cannot modify infrastructure.

## Data protection
- **RDS encryption at rest** (KMS) and **`StorageEncrypted: true`**.
- **S3** frontend bucket: all public access blocked; served only through
  CloudFront via **Origin Access Control (OAC)** with a scoped bucket policy.
- **TLS**: the ALB redirects HTTP→HTTPS when an ACM certificate is supplied;
  CloudFront enforces `redirect-to-https`.
- **ECR image scanning** on push surfaces vulnerable images.

## Auditing & observability
- **CloudWatch Logs** for ECS tasks (`/ecs/${env}/*`) and RDS PostgreSQL logs.
- **Container Insights** and **RDS Performance Insights** enabled.
- CloudTrail (account-level, assumed enabled) records all API/Secrets access.

## Hardening checklist for real production
- Scope the infra role down from `PowerUserAccess` to the exact resources.
- Attach automatic secret rotation (Lambda rotation function).
- Add AWS WAF in front of the ALB/CloudFront.
- Enable GuardDuty + Security Hub at the account level.
