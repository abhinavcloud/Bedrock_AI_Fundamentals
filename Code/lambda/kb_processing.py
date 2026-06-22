"""
Bedrock Knowledge Base Ingestion Trigger
-----------------------------------------
Triggers a StartIngestionJob on a Bedrock Knowledge Base data source.
Skips if an ingestion job is already in progress (single-flight guard).

Environment Variables:
    KNOWLEDGE_BASE_ID : ID of the Bedrock Knowledge Base
    DATA_SOURCE_ID    : ID of the data source within the KB
    LOG_LEVEL         : Logging level (default: INFO)
    AWS_REGION        : Auto-injected by Lambda runtime
"""

import json
import logging
import os
from datetime import datetime, timezone

import boto3
from botocore.exceptions import ClientError

# ---------------------------------------------------------------------------
# Logger setup
# ---------------------------------------------------------------------------
logger = logging.getLogger()
logger.setLevel(os.environ.get("LOG_LEVEL", "INFO").upper())

# ---------------------------------------------------------------------------
# Env vars (fail fast at cold start if missing)
# ---------------------------------------------------------------------------
KNOWLEDGE_BASE_ID = os.environ["KNOWLEDGE_BASE_ID"]
DATA_SOURCE_ID = os.environ["DATA_SOURCE_ID"]
REGION = os.environ.get("AWS_REGION")

# ---------------------------------------------------------------------------
# Boto3 client (reused across warm invocations)
# ---------------------------------------------------------------------------
bedrock_agent = boto3.client("bedrock-agent", region_name=REGION)

# Statuses that mean "a job is already running — don't start another"
ACTIVE_STATUSES = {"STARTING", "IN_PROGRESS"}


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
def _response(status_code: int, body: dict) -> dict:
    """Build a consistent Lambda response envelope."""
    return {
        "statusCode": status_code,
        "body": json.dumps(body, default=str),
    }


def _is_ingestion_in_progress() -> tuple[bool, str | None]:
    """
    Check if an ingestion job is already running for this KB/data-source.
    Returns (is_running, active_job_id_or_None).
    """
    try:
        response = bedrock_agent.list_ingestion_jobs(
            knowledgeBaseId=KNOWLEDGE_BASE_ID,
            dataSourceId=DATA_SOURCE_ID,
            maxResults=10,
            sortBy={"attribute": "STARTED_AT", "order": "DESCENDING"},
        )
    except ClientError as e:
        logger.error("Failed to list ingestion jobs: %s", e)
        raise

    for job in response.get("ingestionJobSummaries", []):
        if job.get("status") in ACTIVE_STATUSES:
            return True, job.get("ingestionJobId")

    return False, None


def _start_ingestion_job() -> dict:
    """Trigger a new ingestion job. Returns the job summary."""
    client_token = f"ingest-{datetime.now(timezone.utc).strftime('%Y%m%d%H%M%S')}"

    try:
        response = bedrock_agent.start_ingestion_job(
            knowledgeBaseId=KNOWLEDGE_BASE_ID,
            dataSourceId=DATA_SOURCE_ID,
            clientToken=client_token,
            description=f"Triggered by Lambda at {client_token}",
        )
    except ClientError as e:
        logger.error("Failed to start ingestion job: %s", e)
        raise

    return response.get("ingestionJob", {})


# ---------------------------------------------------------------------------
# Handler
# ---------------------------------------------------------------------------
def handler(event, context):
    """
    Main Lambda entry point.
    Event payload is ignored — this is a one-shot ingestion trigger.
    """
    logger.info(
        "Ingestion request received | KB=%s | DataSource=%s | RequestId=%s",
        KNOWLEDGE_BASE_ID,
        DATA_SOURCE_ID,
        getattr(context, "aws_request_id", "local"),
    )

    # 1. Single-flight check
    in_progress, active_job_id = _is_ingestion_in_progress()
    if in_progress:
        logger.info("Ingestion already running (jobId=%s). Skipping.", active_job_id)
        return _response(
            200,
            {
                "status": "skipped",
                "reason": "ingestion_in_progress",
                "activeJobId": active_job_id,
            },
        )

    # 2. Start a new ingestion job
    job = _start_ingestion_job()
    job_id = job.get("ingestionJobId")
    job_status = job.get("status")

    logger.info("Ingestion job started | jobId=%s | status=%s", job_id, job_status)

    return _response(
        200,
        {
            "status": "started",
            "ingestionJobId": job_id,
            "ingestionJobStatus": job_status,
            "knowledgeBaseId": KNOWLEDGE_BASE_ID,
            "dataSourceId": DATA_SOURCE_ID,
        },
    )