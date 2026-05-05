#!/usr/bin/env bash
set -euo pipefail

STACK=${1:?'Usage: ./tf.sh <stack> <env> <command> [args]
Stacks: web-app | api-backend | static-site | microservices
Envs:   dev | staging | prod'}
ENV=${2:?'Usage: ./tf.sh <stack> <env> <command> [args]'}
CMD=${3:?'Usage: ./tf.sh <stack> <env> <command> [args]'}
shift 3

STACK_VARS="stacks/${STACK}.tfvars"
ENV_VARS="environments/${ENV}.tfvars"
TF="/mnt/c/Users/user/bin/terraform.exe"

[[ -f "$STACK_VARS" ]] || { echo "ERROR: Stack file not found: $STACK_VARS"; exit 1; }
[[ -f "$ENV_VARS"   ]] || { echo "ERROR: Env file not found: $ENV_VARS";     exit 1; }

echo "Stack: $STACK | Environment: $ENV | Command: $CMD"

"$TF" init -reconfigure \
  -backend-config="key=${ENV}/terraform.tfstate" \
  -input=false -no-color > /dev/null

"$TF" "$CMD" \
  -var-file="$STACK_VARS" \
  -var-file="$ENV_VARS" \
  "${@}"
