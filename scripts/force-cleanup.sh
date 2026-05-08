#!/usr/bin/env bash
# force-cleanup.sh — Delete all tagged AWS resources for an environment in the correct
# dependency order, then optionally wipe the Terraform state from S3 so the next
# terraform apply starts from a clean slate.
#
# Usage:
#   ./force-cleanup.sh --environment dev --project myapp --region us-east-2
#   ./force-cleanup.sh --environment dev --project myapp --region us-east-2 --clear-state --state-bucket myapp-tfstate-685197708357
#
# All resources must have tags:  Project=<project>  Environment=<environment>
# The script skips resources that are already gone (idempotent).

set -euo pipefail

# ── Defaults ──────────────────────────────────────────────────────────────────
PROJECT="myapp"
ENVIRONMENT="dev"
REGION="us-east-2"
CLEAR_STATE=false
STATE_BUCKET=""

# ── Args ──────────────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --project)       PROJECT="$2";       shift 2 ;;
    --environment)   ENVIRONMENT="$2";   shift 2 ;;
    --region)        REGION="$2";        shift 2 ;;
    --clear-state)   CLEAR_STATE=true;   shift   ;;
    --state-bucket)  STATE_BUCKET="$2";  shift 2 ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

NAME_PREFIX="${PROJECT}-${ENVIRONMENT}"
echo "==> Force-cleanup: project=${PROJECT}  environment=${ENVIRONMENT}  region=${REGION}"
echo "    Deleting all resources tagged Project=${PROJECT}, Environment=${ENVIRONMENT}"
echo ""

aws_tags="Key=Project,Value=${PROJECT} Key=Environment,Value=${ENVIRONMENT}"

# Helper: run a command and swallow "not found" / "does not exist" errors
skip_if_gone() { "$@" 2>&1 | grep -v "NoSuchEntity\|NoSuchBucket\|does not exist\|not found\|InvalidParameterValue\|NotFoundException\|ResourceNotFoundException\|ResourceNotFound" || true; }

# ── 1. EventBridge rules & targets ────────────────────────────────────────────
echo "── EventBridge rules ──"
for RULE in $(aws events list-rules --region "$REGION" --query "Rules[?contains(Name,'${NAME_PREFIX}')].Name" --output text 2>/dev/null); do
  echo "  Removing targets from rule: $RULE"
  TARGET_IDS=$(aws events list-targets-by-rule --rule "$RULE" --region "$REGION" --query 'Targets[*].Id' --output text 2>/dev/null || true)
  [ -n "$TARGET_IDS" ] && aws events remove-targets --rule "$RULE" --ids $TARGET_IDS --region "$REGION" 2>/dev/null || true
  echo "  Deleting rule: $RULE"
  aws events delete-rule --name "$RULE" --force --region "$REGION" 2>/dev/null || true
done

# ── 2. Lambda functions ────────────────────────────────────────────────────────
echo "── Lambda functions ──"
for FN in $(aws lambda list-functions --region "$REGION" --query "Functions[?contains(FunctionName,'${NAME_PREFIX}')].FunctionName" --output text 2>/dev/null); do
  echo "  Deleting lambda: $FN"
  aws lambda delete-function --function-name "$FN" --region "$REGION" 2>/dev/null || true
done

# ── 3. ECS services (scale to 0 first) ────────────────────────────────────────
echo "── ECS services ──"
for CLUSTER in $(aws ecs list-clusters --region "$REGION" --query "clusterArns[?contains(@,'${NAME_PREFIX}')]" --output text 2>/dev/null); do
  for SVC in $(aws ecs list-services --cluster "$CLUSTER" --region "$REGION" --query 'serviceArns[]' --output text 2>/dev/null); do
    echo "  Scaling to 0: $SVC"
    aws ecs update-service --cluster "$CLUSTER" --service "$SVC" --desired-count 0 --region "$REGION" 2>/dev/null || true
    echo "  Deleting service: $SVC"
    aws ecs delete-service --cluster "$CLUSTER" --service "$SVC" --force --region "$REGION" 2>/dev/null || true
  done
  echo "  Deleting cluster: $CLUSTER"
  aws ecs delete-cluster --cluster "$CLUSTER" --region "$REGION" 2>/dev/null || true
done

# ── 4. ALB: listeners → target groups → load balancers ───────────────────────
echo "── ALB ──"
for ALB_ARN in $(aws elbv2 describe-load-balancers --region "$REGION" --query "LoadBalancers[?contains(LoadBalancerName,'${NAME_PREFIX}')].LoadBalancerArn" --output text 2>/dev/null); do
  for LISTENER in $(aws elbv2 describe-listeners --load-balancer-arn "$ALB_ARN" --region "$REGION" --query 'Listeners[*].ListenerArn' --output text 2>/dev/null); do
    echo "  Deleting listener: $LISTENER"
    aws elbv2 delete-listener --listener-arn "$LISTENER" --region "$REGION" 2>/dev/null || true
  done
  echo "  Deleting ALB: $ALB_ARN"
  aws elbv2 delete-load-balancer --load-balancer-arn "$ALB_ARN" --region "$REGION" 2>/dev/null || true
done
# Wait for ALBs to fully delete before touching TGs
sleep 10
for TG_ARN in $(aws elbv2 describe-target-groups --region "$REGION" --query "TargetGroups[?contains(TargetGroupName,'${NAME_PREFIX}')].TargetGroupArn" --output text 2>/dev/null); do
  echo "  Deleting target group: $TG_ARN"
  aws elbv2 delete-target-group --target-group-arn "$TG_ARN" --region "$REGION" 2>/dev/null || true
done

# ── 5. RDS instances ───────────────────────────────────────────────────────────
echo "── RDS ──"
for DB in $(aws rds describe-db-instances --region "$REGION" --query "DBInstances[?contains(DBInstanceIdentifier,'${NAME_PREFIX}')].DBInstanceIdentifier" --output text 2>/dev/null); do
  echo "  Deleting RDS: $DB (no final snapshot)"
  aws rds delete-db-instance --db-instance-identifier "$DB" \
    --skip-final-snapshot --delete-automated-backups \
    --region "$REGION" 2>/dev/null || true
done
for SUBNET_GRP in $(aws rds describe-db-subnet-groups --region "$REGION" --query "DBSubnetGroups[?contains(DBSubnetGroupName,'${NAME_PREFIX}')].DBSubnetGroupName" --output text 2>/dev/null); do
  echo "  Deleting DB subnet group: $SUBNET_GRP"
  aws rds delete-db-subnet-group --db-subnet-group-name "$SUBNET_GRP" --region "$REGION" 2>/dev/null || true
done
for PG in $(aws rds describe-db-parameter-groups --region "$REGION" --query "DBParameterGroups[?contains(DBParameterGroupName,'${NAME_PREFIX}')].DBParameterGroupName" --output text 2>/dev/null); do
  [[ "$PG" == default* ]] && continue
  echo "  Deleting parameter group: $PG"
  aws rds delete-db-parameter-group --db-parameter-group-name "$PG" --region "$REGION" 2>/dev/null || true
done

# ── 6. ECR repositories ────────────────────────────────────────────────────────
echo "── ECR ──"
for REPO in $(aws ecr describe-repositories --region "$REGION" --query "repositories[?contains(repositoryName,'${NAME_PREFIX}')].repositoryName" --output text 2>/dev/null); do
  echo "  Deleting ECR repo: $REPO"
  aws ecr delete-repository --repository-name "$REPO" --force --region "$REGION" 2>/dev/null || true
done

# ── 7. S3 buckets (empty first) ────────────────────────────────────────────────
echo "── S3 buckets ──"
for BUCKET in $(aws s3api list-buckets --query "Buckets[?contains(Name,'${NAME_PREFIX}') || contains(Name,'${PROJECT}-${ENVIRONMENT}')].Name" --output text 2>/dev/null); do
  echo "  Emptying & deleting bucket: $BUCKET"
  aws s3 rm "s3://${BUCKET}" --recursive --region "$REGION" 2>/dev/null || true
  # Delete versioned objects
  aws s3api list-object-versions --bucket "$BUCKET" --region "$REGION" \
    --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}' --output json 2>/dev/null | \
    jq -c 'select(.Objects != null) | {Objects: .Objects, Quiet: true}' | \
    xargs -I{} aws s3api delete-objects --bucket "$BUCKET" --delete '{}' --region "$REGION" 2>/dev/null || true
  # Delete delete-markers
  aws s3api list-object-versions --bucket "$BUCKET" --region "$REGION" \
    --query '{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}' --output json 2>/dev/null | \
    jq -c 'select(.Objects != null) | {Objects: .Objects, Quiet: true}' | \
    xargs -I{} aws s3api delete-objects --bucket "$BUCKET" --delete '{}' --region "$REGION" 2>/dev/null || true
  aws s3api delete-bucket --bucket "$BUCKET" --region "$REGION" 2>/dev/null || true
done

# ── 8. CloudWatch log groups ───────────────────────────────────────────────────
echo "── CloudWatch log groups ──"
for LG in $(aws logs describe-log-groups --region "$REGION" --query "logGroups[?contains(logGroupName,'${NAME_PREFIX}')].logGroupName" --output text 2>/dev/null); do
  echo "  Deleting log group: $LG"
  aws logs delete-log-group --log-group-name "$LG" --region "$REGION" 2>/dev/null || true
done

# ── 9. IAM roles ───────────────────────────────────────────────────────────────
echo "── IAM roles ──"
for ROLE in $(aws iam list-roles --query "Roles[?contains(RoleName,'${NAME_PREFIX}')].RoleName" --output text 2>/dev/null); do
  echo "  Cleaning IAM role: $ROLE"
  # Detach managed policies
  for POLICY in $(aws iam list-attached-role-policies --role-name "$ROLE" --query 'AttachedPolicies[*].PolicyArn' --output text 2>/dev/null); do
    aws iam detach-role-policy --role-name "$ROLE" --policy-arn "$POLICY" 2>/dev/null || true
  done
  # Delete inline policies
  for POLICY in $(aws iam list-role-policies --role-name "$ROLE" --query 'PolicyNames[]' --output text 2>/dev/null); do
    aws iam delete-role-policy --role-name "$ROLE" --policy-name "$POLICY" 2>/dev/null || true
  done
  # Remove from instance profiles
  for PROFILE in $(aws iam list-instance-profiles-for-role --role-name "$ROLE" --query 'InstanceProfiles[*].InstanceProfileName' --output text 2>/dev/null); do
    aws iam remove-role-from-instance-profile --instance-profile-name "$PROFILE" --role-name "$ROLE" 2>/dev/null || true
    aws iam delete-instance-profile --instance-profile-name "$PROFILE" 2>/dev/null || true
  done
  aws iam delete-role --role-name "$ROLE" 2>/dev/null || true
done

# ── 10. SSM Parameters ────────────────────────────────────────────────────────
echo "── SSM Parameters ──"
for PARAM in $(aws ssm describe-parameters --region "$REGION" --parameter-filters "Key=Name,Option=Contains,Values=${NAME_PREFIX}" --query 'Parameters[*].Name' --output text 2>/dev/null); do
  echo "  Deleting SSM param: $PARAM"
  aws ssm delete-parameter --name "$PARAM" --region "$REGION" 2>/dev/null || true
done

# ── 11. VPC resources (strict dependency order) ───────────────────────────────
echo "── VPC cleanup ──"

# Find all VPCs with this project/env name
VPC_IDS=$(aws ec2 describe-vpcs --region "$REGION" \
  --filters "Name=tag:Name,Values=${NAME_PREFIX}-vpc" \
  --query 'Vpcs[*].VpcId' --output text 2>/dev/null)

for VPC_ID in $VPC_IDS; do
  echo "  Processing VPC: $VPC_ID"

  # VPC endpoints
  for EP in $(aws ec2 describe-vpc-endpoints --region "$REGION" --filters "Name=vpc-id,Values=${VPC_ID}" --query 'VpcEndpoints[*].VpcEndpointId' --output text 2>/dev/null); do
    echo "    Deleting VPC endpoint: $EP"
    aws ec2 delete-vpc-endpoints --vpc-endpoint-ids "$EP" --region "$REGION" 2>/dev/null || true
  done

  # NAT gateways
  for NAT in $(aws ec2 describe-nat-gateways --region "$REGION" --filter "Name=vpc-id,Values=${VPC_ID}" "Name=state,Values=available,pending" --query 'NatGateways[*].NatGatewayId' --output text 2>/dev/null); do
    echo "    Deleting NAT gateway: $NAT"
    aws ec2 delete-nat-gateway --nat-gateway-id "$NAT" --region "$REGION" 2>/dev/null || true
  done

  # Wait for NATs to finish deleting before releasing EIPs
  echo "    Waiting for NAT gateways to delete..."
  for i in {1..12}; do
    REMAINING=$(aws ec2 describe-nat-gateways --region "$REGION" \
      --filter "Name=vpc-id,Values=${VPC_ID}" "Name=state,Values=deleting,available,pending" \
      --query 'NatGateways[*].NatGatewayId' --output text 2>/dev/null)
    [ -z "$REMAINING" ] && break
    sleep 10
  done

  # Release EIPs tagged to this env
  for ALLOC in $(aws ec2 describe-addresses --region "$REGION" \
    --filters "Name=tag:Environment,Values=${ENVIRONMENT}" "Name=tag:Project,Values=${PROJECT}" \
    --query 'Addresses[*].AllocationId' --output text 2>/dev/null); do
    echo "    Releasing EIP: $ALLOC"
    aws ec2 release-address --allocation-id "$ALLOC" --region "$REGION" 2>/dev/null || true
  done

  # Internet gateways
  for IGW in $(aws ec2 describe-internet-gateways --region "$REGION" --filters "Name=attachment.vpc-id,Values=${VPC_ID}" --query 'InternetGateways[*].InternetGatewayId' --output text 2>/dev/null); do
    echo "    Detaching & deleting IGW: $IGW"
    aws ec2 detach-internet-gateway --internet-gateway-id "$IGW" --vpc-id "$VPC_ID" --region "$REGION" 2>/dev/null || true
    aws ec2 delete-internet-gateway --internet-gateway-id "$IGW" --region "$REGION" 2>/dev/null || true
  done

  # Network interfaces (not managed by EC2/ECS — they clean up automatically, but stragglers block SG/subnet deletion)
  for ENI in $(aws ec2 describe-network-interfaces --region "$REGION" --filters "Name=vpc-id,Values=${VPC_ID}" --query 'NetworkInterfaces[?Status!=`in-use`].NetworkInterfaceId' --output text 2>/dev/null); do
    echo "    Deleting ENI: $ENI"
    aws ec2 delete-network-interface --network-interface-id "$ENI" --region "$REGION" 2>/dev/null || true
  done

  # Security groups (skip default)
  for SG in $(aws ec2 describe-security-groups --region "$REGION" --filters "Name=vpc-id,Values=${VPC_ID}" --query 'SecurityGroups[?GroupName!=`default`].GroupId' --output text 2>/dev/null); do
    echo "    Deleting SG: $SG"
    aws ec2 delete-security-group --group-id "$SG" --region "$REGION" 2>/dev/null || true
  done

  # Subnets
  for SUBNET in $(aws ec2 describe-subnets --region "$REGION" --filters "Name=vpc-id,Values=${VPC_ID}" --query 'Subnets[*].SubnetId' --output text 2>/dev/null); do
    echo "    Deleting subnet: $SUBNET"
    aws ec2 delete-subnet --subnet-id "$SUBNET" --region "$REGION" 2>/dev/null || true
  done

  # Route tables (skip main)
  for RT in $(aws ec2 describe-route-tables --region "$REGION" --filters "Name=vpc-id,Values=${VPC_ID}" --query 'RouteTables[?Associations[0].Main!=`true`].RouteTableId' --output text 2>/dev/null); do
    echo "    Deleting route table: $RT"
    aws ec2 delete-route-table --route-table-id "$RT" --region "$REGION" 2>/dev/null || true
  done

  # VPC flow logs
  for FL in $(aws ec2 describe-flow-logs --region "$REGION" --filter "Name=resource-id,Values=${VPC_ID}" --query 'FlowLogs[*].FlowLogId' --output text 2>/dev/null); do
    echo "    Deleting flow log: $FL"
    aws ec2 delete-flow-logs --flow-log-ids "$FL" --region "$REGION" 2>/dev/null || true
  done

  # Finally delete the VPC
  echo "    Deleting VPC: $VPC_ID"
  aws ec2 delete-vpc --vpc-id "$VPC_ID" --region "$REGION" 2>/dev/null || true
done

# ── 12. Optionally wipe Terraform state ───────────────────────────────────────
if [ "$CLEAR_STATE" = true ]; then
  if [ -z "$STATE_BUCKET" ]; then
    echo "ERROR: --clear-state requires --state-bucket <bucket-name>"
    exit 1
  fi
  echo ""
  echo "── Clearing Terraform state from S3 ──"
  STATE_KEY="${ENVIRONMENT}/terraform.tfstate"
  LOCK_KEY="${ENVIRONMENT}/terraform.tfstate.tflock"
  echo "  Deleting s3://${STATE_BUCKET}/${STATE_KEY}"
  aws s3 rm "s3://${STATE_BUCKET}/${STATE_KEY}" --region "$REGION" 2>/dev/null || true
  aws s3 rm "s3://${STATE_BUCKET}/${LOCK_KEY}" --region "$REGION" 2>/dev/null || true
  echo "  State cleared. Next terraform apply will start from scratch."
fi

echo ""
echo "==> Force-cleanup complete for ${NAME_PREFIX} in ${REGION}"
