# Architecture Diagram

GitHub renders the Mermaid diagrams below directly.

## Containerized architecture (ECS Fargate)

```mermaid
flowchart TB
    user([Internet Users])

    subgraph AWS["AWS Region (us-east-1)"]
        subgraph VPC["VPC — 2 Availability Zones"]
            subgraph public["Public Subnets (AZ-a, AZ-b)"]
                alb["Application Load Balancer<br/>:80 / :443"]
                nat["NAT Gateway(s)"]
            end
            subgraph private["Private Subnets (AZ-a, AZ-b)"]
                fe["ECS Fargate<br/>Next.js Frontend<br/>:3000"]
                be["ECS Fargate<br/>FastAPI Backend<br/>:8000"]
                rds[("RDS PostgreSQL<br/>Multi-AZ")]
            end
        end
        ecr["ECR<br/>frontend / backend images"]
        sm["Secrets Manager<br/>DB credentials"]
        cw["CloudWatch<br/>logs · alarms · dashboard"]
    end

    user -->|HTTPS| alb
    alb -->|"/ , /_next/*"| fe
    alb -->|"/api/backend/* , /health"| be
    be --> rds
    be -. reads .-> sm
    fe -. pull image .-> ecr
    be -. pull image .-> ecr
    fe --> cw
    be --> cw
    rds --> cw
```

## Non-containerized architecture (Elastic Beanstalk + S3/CloudFront)

```mermaid
flowchart TB
    user([Internet Users])

    subgraph AWS["AWS Region"]
        cf["CloudFront (CDN)"]
        s3["S3 Bucket<br/>Next.js static export"]
        subgraph VPC["VPC — 2 AZs"]
            eb["Elastic Beanstalk<br/>EC2 Auto Scaling<br/>FastAPI Backend"]
            rds[("RDS PostgreSQL")]
        end
        sm["Secrets Manager"]
        cw["CloudWatch"]
    end

    user -->|static assets| cf
    cf --> s3
    user -->|API| eb
    eb --> rds
    eb -. reads .-> sm
    eb --> cw
    rds --> cw
```

## CI/CD — app vs infra separation

```mermaid
flowchart LR
    subgraph gh["GitHub"]
        appchange["commit → apps/**"]
        infrachange["commit → infrastructure/**"]
    end

    appchange --> appwf["app-deploy-*.yml<br/>(DEPLOY role)"]
    infrachange --> infrawf["infra.yml<br/>(INFRA role)"]

    appwf -->|build + push| ecr["ECR"]
    appwf -->|update service| ecs["ECS / Beanstalk / S3"]
    infrawf -->|cloudformation deploy| cfn["CloudFormation Stacks"]

    appwf -. "cannot run CFN" .-x cfn
```
