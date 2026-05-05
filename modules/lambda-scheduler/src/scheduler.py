import boto3
import os
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

ecs = boto3.client("ecs")

CLUSTER_NAME = os.environ["ECS_CLUSTER_NAME"]
SERVICE_NAME = os.environ["ECS_SERVICE_NAME"]


def handler(event, context):
    desired_count = int(event.get("desired_count", 0))

    logger.info(
        "Updating ECS service",
        extra={
            "cluster": CLUSTER_NAME,
            "service": SERVICE_NAME,
            "desired_count": desired_count,
        },
    )

    response = ecs.update_service(
        cluster=CLUSTER_NAME,
        service=SERVICE_NAME,
        desiredCount=desired_count,
    )

    updated_count = response["service"]["desiredCount"]
    logger.info("Service updated. desiredCount=%d", updated_count)

    return {
        "statusCode": 200,
        "cluster": CLUSTER_NAME,
        "service": SERVICE_NAME,
        "desiredCount": updated_count,
    }
