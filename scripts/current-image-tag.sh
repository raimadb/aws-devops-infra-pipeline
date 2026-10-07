#!/usr/bin/env bash
# Prints the image tag the ECS service of an environment is running right now.
# Usage: scripts/current-image-tag.sh dev
set -euo pipefail

ENV="${1:?usage: current-image-tag.sh <env>}"
REGION="${AWS_REGION:-ap-south-1}"

TASK_DEF=$(aws ecs describe-services --cluster "${ENV}-cluster" --services "${ENV}-app" \
  --region "$REGION" --query 'services[0].taskDefinition' --output text 2>/dev/null || true)

if [[ -z "$TASK_DEF" || "$TASK_DEF" == "None" ]]; then
  echo "No ${ENV}-app service found. For a first deploy pass -var image_tag=latest" >&2
  exit 1
fi

aws ecs describe-task-definition --task-definition "$TASK_DEF" --region "$REGION" \
  --query 'taskDefinition.containerDefinitions[0].image' --output text | awk -F: '{print $NF}'
