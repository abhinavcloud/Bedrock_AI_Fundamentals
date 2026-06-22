# 🧠 Bedrock AI Fundamentals — Serverless RAG on AWS

> **A production-grade Retrieval-Augmented Generation (RAG) pipeline built entirely on AWS managed services — using Amazon Bedrock Knowledge Bases, S3 Vectors (no OpenSearch!), Titan v2 embeddings, Nova Micro inference, and Bedrock Guardrails. Deployed via Terraform. Costs less than $0.01/month at rest.**

---

## 📋 Table of Contents

- [1. Why this Project](#-why-this-project)
- [2. Architecture Overview](#-architecture-overview)
- [3. Component Breakdown](#-component-breakdown)
- [4. Data Flow](#-data-flow)
- [5. Why These Design Choices](#-why-these-design-choices)
- [6. Project Structure](#-project-structure)
- [7. Prerequisites](#-prerequisites)
- [8. Deployment](#-deployment)
- [9. Usage](#-usage)
- [10. Cost Analysis](#-cost-analysis)
- [11. Security & IAM](#-security--iam)
- [12. Troubleshooting](#-troubleshooting)
- [13. Cleanup](#-cleanup)
- [14. Lessons Learned](#-lessons-learned)
- [15. Future Enhancements](#-future-enhancements)
- [16. References](#-references)


---

## 🎯 Why This Project

Most RAG tutorials in 2026 still default to OpenSearch Serverless as the vector store — which starts at **$350+/month** for the minimum OCU configuration. That's overkill for learning, prototyping, or low-QPS production workloads.

This project demonstrates a **cost-optimized, fully managed RAG stack** using:

- ✅ **Amazon S3 Vectors** — pay-per-use vector storage (~$0.06/GB/month) instead of OpenSearch
- ✅ **Bedrock Knowledge Bases** — fully managed ingestion, chunking, and embedding orchestration
- ✅ **Titan Embed Text v2** — high-quality embeddings at $0.00002/1K tokens
- ✅ **Nova Micro** — cheapest Bedrock inference model for response generation
- ✅ **Bedrock Guardrails** — content moderation, topic filtering, PII protection
- ✅ **Lambda** — serverless ingestion trigger (zero idle cost)

**Total monthly cost at rest: < $0.01.** Per query: ~$0.002.

---

## 🏗️ Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                         INGESTION PIPELINE                          │
│                                                                     │
│   ┌──────────────┐    ┌──────────────┐    ┌────────────────────┐    │
│   │ User Uploads │───▶│   S3 Bucket  │    │  Lambda (Python)   │    │
│   │  Documents   │    │   (docs)     │    │  StartIngestionJob │    │
│   └──────────────┘    └──────┬───────┘    └─────────┬──────────┘    │
│                              │                      │               │
│                              │      manual trigger  │               │
│                              │      (aws lambda     │               │
│                              │       invoke)        │               │
│                              ▼                      ▼               │
│                       ┌─────────────────────────────────────────┐   │
│                       │      Bedrock Knowledge Base             │   │
│                       │   ┌──────────────────────────────────┐  │   │
│                       │   │ 1. Read S3 (via kb_role)         │  │   │
│                       │   │ 2. Chunk documents               │  │   │
│                       │   │ 3. Embed via Titan v2 (256-dim)  │  │   │
│                       │   │ 4. Write to S3 Vectors index     │  │   │
│                       │   └──────────────────────────────────┘  │   │
│                       └─────────────────┬───────────────────────┘   │
│                                         │                           │
│                                         ▼                           │
│                              ┌─────────────────────┐                │
│                              │   S3 Vectors        │                │
│                              │   Bucket + Index    │                │
│                              │   (cosine, 256-dim) │                │
│                              └─────────────────────┘                │
└─────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────┐
│                          QUERY PIPELINE                             │
│                                                                     │
│   ┌──────────────┐    ┌────────────────────────────────────────┐    │
│   │   User       │───▶│ Python Client (RetrieveAndGenerate)    │    │
│   │  Question    │    └─────────────────┬──────────────────────┘    │
│   └──────────────┘                      │                           │
│                                         ▼                           │
│                       ┌──────────────────────────────────────┐      │
│                       │   Bedrock Agent Runtime              │      │
│                       │   ┌───────────────────────────────┐  │      │
│                       │   │ 1. Apply Guardrail (input)    │  │      │
│                       │   │ 2. Retrieve from KB           │  │      │
│                       │   │    (cosine sim on S3 Vectors) │  │      │
│                       │   │ 3. Generate via Nova Micro    │  │      │
│                       │   │    (inference profile)        │  │      │
│                       │   │ 4. Apply Guardrail (output)   │  │      │
│                       │   └───────────────────────────────┘  │      │
│                       └──────────────────┬───────────────────┘      │
│                                          │                          │
│                                          ▼                          │
│                              ┌────────────────────────┐             │
│                              │  Answer + Citations    │             │
│                              │  OR Guardrail Block    │             │
│                              └────────────────────────┘             │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 🧩 Component Breakdown

### 1. **Amazon S3 Bucket** (`bedrock-s3bucket-<account-id>`)
The **source of truth** for raw documents. Dedicated bucket for KB ingestion — no prefix filtering needed.

**Configuration:**
- Bucket-owner preferred object ownership
- Default encryption (SSE-S3)
- Block Public Access enabled by default

### 2. **Amazon S3 Vectors**
The **vector database** replacing traditional options like OpenSearch Serverless or Pinecone.

**Index Configuration:**

| Parameter | Value | Reason |
|---|---|---|
| `data_type` | `float32` | Standard for Titan v2 embeddings |
| `dimension` | `256` | Cost-optimized (Titan v2 supports 256/512/1024) |
| `distance_metric` | `cosine` | Titan v2 produces normalized vectors |

### 3. **Bedrock Knowledge Base** (`knowledge-base`)
The **orchestration layer** that handles document chunking, embedding generation, and vector indexing.

**Configuration:**
- **Type**: VECTOR
- **Embedding Model**: `amazon.titan-embed-text-v2:0`
- **Storage**: S3_VECTORS (not OpenSearch!)
- **Dimensions**: 256 (matches index)

### 4. **Bedrock Data Source** (`bedrock-data-source`)
The **binding** between the KB and the S3 source bucket. KB only ingests from explicitly configured data sources.

### 5. **Bedrock Inference Profile** (`Nova Micro`)
The **inference abstraction layer** that:
- Routes requests across regions (cross-region inference)
- Provides cost allocation tags
- Enables guardrail integration

**Why Nova Micro**: Cheapest Bedrock text model (~$0.000035/1K input tokens) — perfect for learning and most production use cases.

### 6. **Bedrock Guardrail** (`bedrock_guardrail`)
The **safety layer** applied to both input and output of LLM calls.

**Policies configured:**

| Policy Type | Configuration |
|---|---|
| **Content Filters** | HATE, SEXUAL, VIOLENCE, INSULTS, MISCONDUCT, PROMPT_ATTACK |
| **Topic Filters** | Investment advice, Health advice (both DENY) |
| **PII Protection** | NAME (block input, anonymize output) |
| **Regex Filters** | SSN pattern (`^\d{3}-\d{2}-\d{4}$`) |
| **Word Filters** | Profanity managed list + custom words |

### 7. **AWS Lambda** (`lambda_bedrock_function`)
The **ingestion trigger**. Critically, this Lambda **does NOT read S3 or call embeddings** — it only invokes `StartIngestionJob` on the KB. Bedrock does all the heavy lifting asynchronously.

**Key design decision**: Lambda is a **trigger, not a worker**. This avoids:
- Lambda 15-minute timeout for large datasets
- Memory pressure from holding documents
- Custom chunking logic to maintain
- IAM blast radius from S3 + Bedrock permissions in one role

**Features:**
- Single-flight guard via `ListIngestionJobs` check
- Idempotent retries via UUID-based `clientToken`
- Python 3.13 runtime, 256 MB, 30s timeout

### 8. **IAM Roles**
Two distinct roles enforcing least-privilege:

| Role | Trust | Permissions |
|---|---|---|
| `kb-role` | `bedrock.amazonaws.com` (scoped to KB ARN) | S3 read, Bedrock InvokeModel (embedding), S3 Vectors write |
| `lambda_execution_role` | `lambda.amazonaws.com` | `StartIngestionJob`, `GetIngestionJob`, `ListIngestionJobs`, CloudWatch Logs |

---

## 🔄 Data Flow

### Ingestion Flow (One-Time / On Document Update)
1. User uploads documents to S3 (`aws s3 sync` or `cp`)
2. User manually invokes Lambda (or via scheduled trigger)
3. Lambda checks if an ingestion job is already running (single-flight)
4. Lambda calls `bedrock-agent:StartIngestionJob` and returns immediately
5. **Bedrock asynchronously**:
   - Assumes `kb-role`
   - Lists & reads S3 bucket objects
   - Chunks documents (default: 300 tokens with 20% overlap)
   - Calls Titan v2 embedding model
   - Writes vectors + metadata to S3 Vectors index
6. User polls `GetIngestionJob` or checks console for status

### Query Flow (Per User Question)
1. User submits question via Python client
2. Client calls `bedrock-agent-runtime:RetrieveAndGenerate`
3. **Bedrock Agent Runtime**:
   - Applies guardrail to input → blocks if violates policy
   - Embeds question via Titan v2
   - Performs cosine similarity search on S3 Vectors index
   - Sends top-K retrieved chunks + question to Nova Micro (via inference profile)
   - Applies guardrail to output → blocks/anonymizes if violates policy
4. Returns generated answer + source citations OR guardrail block message

---

## 💡 Why These Design Choices

### Lambda as Trigger, Not Worker
**Alternative considered**: Lambda reads S3 → chunks → calls InvokeModel → writes to S3 Vectors directly.

**Why rejected**:
- Lambda would need 4 IAM permission scopes vs. 1
- 15-minute timeout limits dataset size
- Custom chunking logic = maintenance burden
- Bedrock KB already does this asynchronously, in parallel, with retries

### S3 Vectors over OpenSearch Serverless
- **OpenSearch Serverless cost**: ~$350/month minimum (2 OCUs minimum)
- **S3 Vectors cost**: ~$0.06/GB + ~$0.20/M PUT requests = **pennies for small datasets**

For low-QPS workloads (< 10 queries/second), S3 Vectors wins on cost by 100×+.

### Nova Micro over Claude/Anthropic
- **Claude 3.5 Sonnet**: ~$0.003/1K input tokens
- **Nova Micro**: ~$0.000035/1K input tokens — **85× cheaper**

For learning and most chatbot use cases, Nova Micro is more than capable.

### 256 Dimensions over 1024
Titan v2 supports 256, 512, or 1024 dimensions. Smaller dimensions = lower storage costs in S3 Vectors with marginal quality trade-off for general retrieval tasks.

### Inference Profile over Direct Model Invocation
- Enables cross-region routing (resilience)
- Cost allocation tags per profile
- Centralized point to swap models without changing application code

### Manual Lambda Trigger over S3 Event Notification
**Why rejected event-driven**:
- `StartIngestionJob` is a **bucket-level** operation, not per-object
- Batch uploads of N files → N Lambda invocations → N `ConflictException` errors
- Single-flight guard helps but adds complexity for a one-time activity

---

## 📁 Project Structure

```
Bedrock_AI_Fundamentals/
│
├── Code/                                       # Python clients + Lambda code
│   ├── .venv/                                  # Local virtual env (gitignored)
│   │
│   ├── bedrock-examples/                       # Standalone Bedrock learning scripts
│   │   ├── converse_api.py                     # Converse API demo
│   │   ├── guardrails.py                       # Guardrail invocation demo
│   │   ├── knowledge_base_query.py             # KB Retrieve + Generate client
│   │   ├── multi_turn.py                       # Multi-turn conversation example
│   │   ├── strands_agent.py                    # Strands agent demo
│   │   └── tool_use.py                         # Tool use / function calling
│   │
│   ├── knowledge_base_docs/                    # Sample documents for KB ingestion
│   │   ├── 01_academic_calendar.txt
│   │   ├── 02_financial_aid.txt
│   │   ├── 03_computer_science.txt
│   │   ├── 04_admissions.txt
│   │   ├── 05_housing.txt
│   │   ├── 06_dining_services.txt
│   │   ├── 07_registration.txt
│   │   ├── 08_library.txt
│   │   ├── 09_career_services.txt
│   │   └── 10_parking_transportation.txt
│   │
│   ├── lambda_kb_processing/                   # Lambda function source
│   │   └── app.py                              # Bedrock KB ingestion trigger
│   │
│   ├── .env                                    # Local env vars (gitignored)
│   └── requirements.txt                        # Python deps (boto3, python-dotenv)
│
├── Infra/                                      # Terraform IaC
│   ├── .code/                                  # Internal/scratch (gitignored)
│   ├── .terraform/                             # Provider cache (gitignored)
│   ├── .terraform.lock.hcl                     # Provider version lock
│   ├── backend.hcl                             # S3 backend config (gitignored if has secrets)
│   ├── main.tf                                 # All resources (S3, KB, Lambda, IAM, Guardrail)
│   ├── outputs.tf                              # KB ID, DS ID, bucket name, guardrail ID
│   ├── terraform.tf                            # Provider pins + required_version
│   └── .gitignore                              # Excludes state, cache, lambda zips
│
├── CODE_OF_CONDUCT.md                          # Community guidelines
├── CONTRIBUTING.md                             # Contribution guide
├── LICENSE                                     # MIT
└── README.md                                   # You are here
```

### Key Directories Explained

| Path | Purpose |
|---|---|
| `Code/bedrock-examples/` | Standalone learning scripts for individual Bedrock features (Converse, Guardrails, Tool use, etc.) — independent from the RAG pipeline |
| `Code/knowledge_base_docs/` | Sample university-themed documents (academic calendar, admissions, housing, etc.) used as KB ingestion source |
| `Code/lambda_kb_processing/` | Production Lambda code that triggers KB ingestion jobs |
| `Infra/` | All Terraform configuration — single-file design for learning clarity |

---

## ✅ Prerequisites

| Tool | Version | Purpose |
|---|---|---|
| Terraform | ≥ 1.10.0 | IaC deployment |
| AWS CLI | ≥ 2.15 | Authentication & invocation |
| Python | ≥ 3.12 | Local client + Lambda runtime |
| AWS Account | — | Bedrock-enabled in `ap-south-1` |

### Bedrock Model Access
Before deployment, enable model access in the Bedrock console:
1. **Bedrock Console → Model access**
2. Enable:
   - `Amazon Titan Text Embeddings V2`
   - `Amazon Nova Micro`

This is a **one-time manual step** — Bedrock model access cannot be enabled via Terraform.

### AWS CLI Authentication
```powershell
# Configure SSO profile
aws configure sso --profile personal

# Login
aws sso login --profile personal

# Verify
aws sts get-caller-identity --profile personal
```

---

## 🚀 Deployment

### 1. Clone & Configure
```powershell
git clone <your-repo-url>
cd Bedrock_AI_Fundamentals
```

### 2. Deploy Infrastructure
```powershell
cd Infra
terraform init -backend-config=backend.hcl
terraform plan
terraform apply
```

Terraform creates ~20 resources in ~3 minutes. Note the outputs:
```
knowledge_base_id = "ABC123XYZ"
data_source_id    = "DEF456UVW"
s3_bucket_name    = "bedrock-s3bucket-<account-id>"
guardrail_id      = "ghi789rst"
```

### 3. Populate `.env` for Local Client
```powershell
cd ../Code
notepad .env
```

Fill in:
```
KNOWLEDGE_BASE_ID=ABC123XYZ
DATA_SOURCE_ID=DEF456UVW
GUARDRAIL_ID=ghi789rst
GUARDRAIL_VERSION=1
MODEL_ID=arn:aws:bedrock:ap-south-1:<account-id>:inference-profile/<profile-id>
AWS_PROFILE=personal
```

### 4. Set Up Python Environment
```powershell
python -m venv .venv
.venv\Scripts\activate
pip install -r requirements.txt
```

### 5. Upload Documents
```powershell
$bucket = (aws s3 ls --profile personal | Select-String "bedrock-s3bucket").ToString().Split()[-1]
aws s3 sync .\knowledge_base_docs\ s3://$bucket/ --profile personal
```

### 6. Trigger Ingestion
```powershell
aws lambda invoke `
  --function-name lambda_bedrock_function `
  --payload '{}' `
  --cli-binary-format raw-in-base64-out `
  --profile personal `
  response.json

Get-Content response.json
```

### 7. Verify Ingestion Completed
```powershell
aws bedrock-agent list-ingestion-jobs `
  --knowledge-base-id <KB_ID> `
  --data-source-id <DS_ID> `
  --profile personal
```

Wait for `status: COMPLETE`. Small datasets finish in 1–3 minutes.

Alternatively, verify in console:
- **Bedrock Console → Knowledge Bases → `knowledge-base` → Data source → Sync history**

---

## 🎮 Usage

### Query the Knowledge Base
```powershell
cd Code\bedrock-examples
python knowledge_base_query.py
```

### Test Scenarios
Edit the question variable to test:

```python
# ✅ Normal university question (should retrieve from KB)
question = "What programs does the computer science department offer?"

# ✅ Document-grounded question (should cite source docs)
question = "What are the dining service hours?"

# 🚫 Denied topic (should be blocked by guardrail)
question = "Where should I invest my money?"

# 🚫 Health topic (should be blocked)
question = "What medicine should I take for a cold?"

# 🚫 PII in input (should be blocked or anonymized)
question = "My SSN is 123-45-6789, can you help?"
```

### Handling Guardrail Blocks
The client checks `response["guardrailAction"]`:
- `"NONE"` → Normal answer returned
- `"INTERVENED"` → Custom message: *"Sorry, I can't share that information."*

The default block messages are also configurable via Terraform:
```hcl
blocked_input_messaging   = "Sorry, I can't help with that question."
blocked_outputs_messaging = "Sorry, I can't share that information."
```

### Other Bedrock Examples
The `bedrock-examples/` folder contains standalone demos for learning individual Bedrock features:

| Script | Demonstrates |
|---|---|
| `converse_api.py` | Unified Converse API across models |
| `guardrails.py` | Direct guardrail invocation (ApplyGuardrail) |
| `multi_turn.py` | Multi-turn conversation with session state |
| `strands_agent.py` | Strands agent SDK patterns |
| `tool_use.py` | Function calling / tool use |

---

## 💰 Cost Analysis

### One-Time Costs
| Activity | Cost |
|---|---|
| Initial ingestion (small dataset ~50K tokens) | ~$0.001 |
| Embedding generation | ~$0.00002 per 1K tokens |

### Monthly Recurring Costs (At Rest)
| Component | Cost |
|---|---|
| S3 bucket storage (~50 MB) | ~$0.001 |
| S3 Vectors index storage (~100 vectors) | ~$0.005 |
| CloudWatch Logs (small) | ~$0.0005 |
| Lambda / IAM / Guardrail / Inference Profile (idle) | $0 |
| **TOTAL** | **< $0.01/month** |

### Per-Query Costs
| Operation | Cost |
|---|---|
| Vector retrieve (S3 Vectors) | ~$0.0001 |
| Nova Micro generation (~500 input + 200 output tokens) | ~$0.00005 |
| Guardrail evaluation (input + output) | ~$0.0015 |
| **Total per query** | **~$0.002** |

**500 queries/day = ~$1/month.**

### Set Billing Alarm
```powershell
aws cloudwatch put-metric-alarm `
  --alarm-name "bedrock-rag-budget-alert" `
  --alarm-description "Alert if Bedrock RAG exceeds $5" `
  --metric-name EstimatedCharges `
  --namespace AWS/Billing `
  --statistic Maximum `
  --period 21600 `
  --threshold 5 `
  --comparison-operator GreaterThanThreshold `
  --evaluation-periods 1 `
  --profile personal
```

---

## 🔐 Security & IAM

### KB Role (`kb-role`)
**Trust Policy**: Bedrock service, scoped to `aws:SourceAccount` + `aws:SourceArn` (prevents confused deputy attacks).

**Attached Policies**:
- `kb-s3-datasource` — Read S3 bucket (scoped to `aws:ResourceAccount`)
- `kb-bedrock-invoke` — InvokeModel on Titan v2 embedding only
- `kb-s3-vectors` — Read/write specific S3 Vectors index only

### Lambda Role (`lambda_execution_role`)
**Trust Policy**: Lambda service.

**Attached Policy**: `lambda-execution-policy`
- `bedrock:StartIngestionJob`, `GetIngestionJob`, `ListIngestionJobs` — scoped to specific KB + data source ARN
- CloudWatch Logs (`*` resource for log group/stream creation)

### Defense in Depth
| Layer | Mechanism |
|---|---|
| Network | VPC not used (all AWS-internal, no egress) |
| Identity | IAM roles with conditioned trust policies |
| Resource | Bucket policies, KB ARN scoping |
| Data | SSE-S3 encryption (S3), encryption at rest (S3 Vectors) |
| Application | Guardrails for content/topic/PII filtering |

### Secrets Hygiene
- ❌ Never commit AWS account IDs to public repos
- ❌ Never commit `.env` files
- ❌ Never commit `backend.hcl` if it contains state bucket secrets
- ✅ Use placeholders like `<account-id>` in docs
- ✅ Use `aws sts get-caller-identity` to resolve at runtime

---

## 🐛 Troubleshooting

### Lambda returns "Unable to import module 'index'"
**Cause**: Zip structure doesn't match handler.
**Fix**: Ensure your Lambda source file is at `lambda_kb_processing/app.py` and Terraform `handler = "app.handler"`. Re-run:
```powershell
terraform apply -replace="data.archive_file.lambda_bedrock_invocation_code"
```

### Ingestion job status = `FAILED`
**Common causes**:
1. **Embedding model not enabled** → Bedrock Console → Model access → enable Titan v2
2. **Unsupported file format** → KB supports PDF, TXT, MD, HTML, DOC/DOCX, CSV, XLS/XLSX
3. **File > 50 MB** → Split into smaller files
4. **KB role missing permission** → Check `kb-role` attached policies

### Lambda invocation returns `ClientToken length 21 < 33`
**Cause**: Timestamp-based token too short for Bedrock API.
**Fix**: Use `uuid.uuid4()` based token (already implemented in latest `app.py`).

### Guardrail not blocking expected content
**Cause**: Guardrail version is frozen; updates to `aws_bedrock_guardrail` don't auto-version.
**Fix**: Either point at `DRAFT` version or create a new `aws_bedrock_guardrail_version` resource and update `.env`.

### S3 Vectors `list-vectors` returns empty
**Cause**: Ingestion job didn't complete or wrote to wrong index.
**Fix**: Verify `index_arn` in KB `storage_configuration` matches the actual S3 Vectors index.

### Lambda `code_sha256` argument unsupported
**Cause**: AWS provider version < 6.27.0.
**Fix**: Update `terraform.tf` to require `>= 6.27.0` and re-run `terraform init -upgrade`.

### Runtime `nodejs24.x` not supported
**Cause**: AWS provider version < 6.19.0.
**Fix**: Update `terraform.tf` to require `>= 6.19.0` or switch to `python3.13`.

---

## 🧹 Cleanup

### Option 1: Full Destroy (Recommended After Learning)
```powershell
# 1. Empty S3 bucket (Terraform can't delete non-empty buckets)
$bucket = (terraform output -raw s3_bucket_name)
aws s3 rm s3://$bucket/ --recursive --profile personal

# 2. Destroy all infra
cd Infra
terraform destroy
```

### Option 2: Keep Infra, Empty Buckets
For ongoing experimentation at near-zero cost:
```powershell
aws s3 rm s3://$bucket/ --recursive --profile personal
```
Bucket structure stays; re-upload + re-ingest whenever.

### Option 3: Hybrid (Smart Move) ⭐
Empty S3 vectors + S3 bucket but keep all wiring:
```powershell
# Empty source bucket
aws s3 rm s3://$bucket/ --recursive --profile personal

# Optionally empty vectors index
aws s3vectors list-vectors --vector-bucket-name kb-s3-vector --index-name kb-s3-vector-index --profile personal
```
Total cost drops to **<$0.001/month**.

---

## 🎓 Lessons Learned

### What Worked Well
- **Architecture-first thinking**: Chose managed primitives (Bedrock KB) over rolling custom pipeline
- **Cost optimization**: S3 Vectors over OpenSearch saved ~$350/month vs. typical RAG tutorials
- **Separation of concerns**: Lambda = trigger, Bedrock = worker
- **Least-privilege IAM**: Separate roles, conditioned trust policies, ARN-scoped permissions

### Gotchas Encountered
- **Trust policy copy-paste**: Initially used `ec2.amazonaws.com` as KB principal — silent failure waiting to happen
- **`StartIngestionJob` semantics**: Tried to trigger per-object via S3 events; the API is bucket-level
- **`clientToken` length**: Bedrock requires ≥ 33 chars; timestamp-only was too short
- **Provider version assumptions**: `code_sha256` requires AWS provider ≥ 6.27.0, `nodejs24.x` requires ≥ 6.19.0
- **Guardrail versioning**: Updates to guardrail body don't propagate to frozen versions

### Architectural Reflections
- **Trigger ≠ Worker** is a powerful pattern for managed services
- Always read the **resource** side of the API (StartIngestionJob is per-data-source, not per-object) before designing triggers
- Guardrails are evaluated on **versioned** snapshots — bake versioning into the CI/CD loop
- Cost decisions compound: 256-dim + Nova Micro + S3 Vectors = ~1000× cheaper than 1024-dim + Claude + OpenSearch Serverless

---

## 🚧 Future Enhancements

| Enhancement | Effort | Value |
|---|---|---|
| Add EventBridge schedule for periodic re-ingestion | Low | Production readiness |
| Add Step Functions for polling ingestion completion | Medium | Synchronous workflows |
| Add API Gateway + Lambda for HTTP query endpoint | Medium | Web/mobile integration |
| Add DynamoDB session memory for conversational RAG | High | Multi-turn conversations |
| Add OpenTelemetry tracing for KB → LLM latency | Medium | Observability |
| Migrate guardrail to `STANDARD` tier for more languages | Low | Internationalization |
| Add S3 lifecycle policy for old document versions | Low | Cost optimization |
| Add CloudFront + Cognito for secure frontend | High | Productionization |
| Add GitHub Actions CI/CD with OIDC | Medium | DevOps maturity |
| Multi-tenant KB isolation with per-tenant guardrails | High | SaaS readiness |

---

## 📚 References

- https://docs.aws.amazon.com/bedrock/latest/userguide/knowledge-base.html
- https://docs.aws.amazon.com/AmazonS3/latest/userguide/s3-vectors.html
- https://docs.aws.amazon.com/bedrock/latest/userguide/guardrails.html
- https://docs.aws.amazon.com/bedrock/latest/userguide/titan-embedding-models.html
- https://docs.aws.amazon.com/bedrock/latest/userguide/nova-models.html
- https://registry.terraform.io/providers/hashicorp/aws/latest
- https://docs.aws.amazon.com/bedrock/latest/userguide/inference-profiles.html

---

## 🤝 Contributing

See CONTRIBUTING.md for contribution guidelines and CODE_OF_CONDUCT.md for community standards.

---

## 📄 License

MIT — see LICENSE. Fork it, ship it, learn from it.

---

## 👤 Author

**Abhinav Kumar** — Solution Architect | 15+ years | AWS · Bedrock · Serverless

> *Built as part of a hands-on Bedrock learning module — focused on cost-optimized, production-grade RAG patterns.*

---

⭐ **If this helped you understand Bedrock RAG without OpenSearch, star the repo!**