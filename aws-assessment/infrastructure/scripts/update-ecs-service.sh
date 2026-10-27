#!/usr/bin/env bash
#
# update-ecs-service.sh - Application-only ECS deployment.
#
# Registers a NEW task-definition revision that differs from the current one
# ONLY by container image, then points the service at it. CloudFormation is
# never invoked, satisfying "app deploys must not modify infrastructure".
#
# Usage:
#   update-ecs-service.sh <cluster> <service> <container-name> <image-uri> [region]
set -euo pipefail

CLUSTER="${1:?cluster}"
SERVICE="${2:?service}"
CONTAINER="${3:?container name}"
IMAGE="${4:?image uri}"
REGION="${5:-us-east-1}"

echo "Fetching current task definition for ${SERVICE}..."
TASK_DEF_ARN=$(aws ecs describe-services \
  --cluster "$CLUSTER" --services "$SERVICE" --region "$REGION" \
  --query "services[0].taskDefinition" --output text)

aws ecs describe-task-definition \
  --task-definition "$TASK_DEF_ARN" --region "$REGION" \
  --query "taskDefinition" > /tmp/taskdef.json

# Swap the image for the named container and strip read-only fields CFN/ECS
# will reject on re-register.
jq --arg IMG "$IMAGE" --arg NAME "$CONTAINER" '
  .containerDefinitions = (
    .containerDefinitions | map(if .name == $NAME then .image = $IMG else . end)
  )
  | del(.taskDefinitionArn, .revision, .status, .requiresAttributes,
        .compatibilities, .registeredAt, .registeredBy)
' /tmp/taskdef.json > /tmp/newtaskdef.json

echo "Registering new task definition revision..."
NEW_TD=$(aws ecs register-task-definition \
  --region "$REGION" \
  --cli-input-json file:///tmp/newtaskdef.json \
  --query "taskDefinition.taskDefinitionArn" --output text)

echo "Updating service ${SERVICE} -> ${NEW_TD}"
aws ecs update-service \
  --cluster "$CLUSTER" --service "$SERVICE" \
  --task-definition "$NEW_TD" --region "$REGION" >/dev/null

echo "Service update initiated."
