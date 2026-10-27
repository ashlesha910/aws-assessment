# 5. Rollback Strategy

Rollback is handled at two independent layers, matching the app-vs-infra
separation.

## Application rollback

### Containerized (ECS)
- **Automatic.** Each service enables a **deployment circuit breaker with
  `Rollback: true`**. If the new task-definition revision fails to reach a
  healthy state (ALB health checks), ECS automatically rolls back to the last
  known-good revision — no human action required.
- **Manual / instant.** Every deploy keeps previous task-definition revisions.
  To roll back deliberately:
  ```bash
  # List revisions, then point the service at an older one:
  aws ecs update-service --cluster dev-cluster --service dev-backend \
    --task-definition dev-backend:<previous-revision>
  ```
  Because images are tagged by immutable git SHA, the previous image is always
  available in ECR.

### Non-containerized (Elastic Beanstalk)
- EB retains prior **application versions**. Roll back by re-pointing the
  environment:
  ```bash
  aws elasticbeanstalk update-environment \
    --environment-name dev-backend --version-label <previous-sha>
  ```
- Frontend (S3/CloudFront): redeploy the previous commit, or restore from S3
  versioning, then invalidate CloudFront.

### Re-deploy by revert
Reverting the application commit and pushing re-triggers the app pipeline with
the previous code — a clean, auditable rollback through the same gate.

## Infrastructure rollback

### Automatic
- CloudFormation **automatically rolls back a failed stack update** to the last
  stable state. Deployments use change sets through `cloudformation deploy`.

### Manual
- Revert the change under `infrastructure/**` and re-run the infra pipeline;
  CloudFormation converges to the previous template state.
- For a bad but "successful" change, re-deploy the prior template version from
  git history.

## Data / database rollback
- **RDS automated backups** (1 day dev, 7 staging, 30 prod) enable
  **point-in-time recovery**.
- `DeletionPolicy: Snapshot` + `UpdateReplacePolicy: Snapshot` guarantee a
  snapshot is taken before any replacing change or stack deletion.
- Prod has **deletion protection** enabled to prevent accidental loss.
- Restore:
  ```bash
  aws rds restore-db-instance-to-point-in-time \
    --source-db-instance-identifier prod-postgres \
    --target-db-instance-identifier prod-postgres-restore \
    --restore-time <timestamp>
  ```

## Rollback decision guide

| Symptom | Action |
|---------|--------|
| New ECS tasks unhealthy | Automatic circuit-breaker rollback (nothing to do) |
| App bug shipped, infra fine | Re-point ECS/EB to previous revision/version |
| Bad infra change | Revert `infrastructure/**` commit, re-run infra pipeline |
| Data corruption | RDS point-in-time restore to new instance, repoint app |
| Total environment loss | Re-run `deploy-infra.sh`, restore RDS from snapshot |
