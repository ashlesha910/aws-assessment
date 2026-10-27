#!/usr/bin/env bash
#
# deploy-infra.sh - Provision/update the INFRASTRUCTURE stacks for one environment.
# This is the ONLY path that mutates infrastructure. Application pipelines never
# call this script, which enforces the "separate app vs infra" requirement.
#
# Usage:
#   ./deploy-infra.sh <dev|staging|prod> [aws-region]
#
# Requires: awscli v2, jq, and credentials for the target account.
set -euo pipefail

ENV="${1:?Usage: deploy-infra.sh <dev|staging|prod> [region]}"
REGION="${2:-us-east-1}"
PARAM_FILE="$(dirname "$0")/../parameters/${ENV}.json"
TEMPLATE_DIR="$(dirname "$0")/../templates"

if [[ ! -f "$PARAM_FILE" ]]; then
  echo "Parameter file not found: $PARAM_FILE" >&2
  exit 1
fi

# GitHub coordinates needed by the security stack OIDC trust policy.
GITHUB_ORG="${GITHUB_ORG:?Set GITHUB_ORG to the repo owner}"
GITHUB_REPO="${GITHUB_REPO:?Set GITHUB_REPO to the repo name}"

# Convert the flat JSON parameter file into CFN "Key=Value" overrides.
param_overrides() {
  jq -r 'to_entries | map("\(.key)=\(.value)") | .[]' "$PARAM_FILE"
}

deploy() {
  local name="$1"; shift
  local template="$1"; shift
  echo ""
  echo "==> Deploying stack: ${ENV}-${name}"
  aws cloudformation deploy \
    --region "$REGION" \
    --stack-name "${ENV}-${name}" \
    --template-file "${TEMPLATE_DIR}/${template}" \
    --capabilities CAPABILITY_NAMED_IAM \
    --no-fail-on-empty-changeset \
    --parameter-overrides "$@"
}

# Order matters: network -> security -> database/shared -> compute -> monitoring.
deploy "network"    "01-network.yaml"    $(param_overrides)
deploy "security"   "02-security.yaml"   EnvironmentName="$ENV" GitHubOrg="$GITHUB_ORG" GitHubRepo="$GITHUB_REPO"
deploy "database"   "03-database.yaml"   $(param_overrides)
deploy "shared"     "04-shared.yaml"     EnvironmentName="$ENV" CertificateArn="${CERT_ARN:-}"
deploy "monitoring" "07-monitoring.yaml" EnvironmentName="$ENV" AlertEmail="${ALERT_EMAIL:-}"

# Containerized compute is seeded with a placeholder image; the app pipeline
# then rolls real images without CloudFormation. Seed only if not present.
SEED_IMAGE="public.ecr.aws/docker/library/nginx:latest"
deploy "ecs" "05-ecs-compute.yaml" \
  EnvironmentName="$ENV" \
  FrontendImage="$SEED_IMAGE" \
  BackendImage="$SEED_IMAGE" \
  FrontendDesiredCount="$(jq -r .FrontendDesiredCount "$PARAM_FILE")" \
  BackendDesiredCount="$(jq -r .BackendDesiredCount "$PARAM_FILE")" \
  TaskCpu="$(jq -r .TaskCpu "$PARAM_FILE")" \
  TaskMemory="$(jq -r .TaskMemory "$PARAM_FILE")"

# Non-containerized compute (second approach).
deploy "noncontainer" "06-noncontainer-compute.yaml" \
  EnvironmentName="$ENV" InstanceType="$(jq -r .InstanceType "$PARAM_FILE")"

echo ""
echo "Infrastructure for '$ENV' deployed successfully."
