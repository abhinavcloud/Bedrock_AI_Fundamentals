# Creating a Bedrock Inference model from Foundation Models using Terraform

provider "aws" {
  region = "ap-south-1"
}


data "aws_caller_identity" "current" {}

data "aws_region" "current" {}



resource "aws_bedrock_inference_profile" "bedrock_inference_profile" {
  name        = "Nova Micro Bedrock Inference Profile"
  description = "Bedrock Inference Profile for Nova Micro"

  model_source {
    copy_from = "arn:aws:bedrock:ap-south-1:${data.aws_caller_identity.current.account_id}:inference-profile/apac.amazon.nova-micro-v1:0"

    # Include account ID to use inference profiles
    # copy_from = "arn:aws:bedrock:eu-central-1:${data.aws_caller_identity.current.account_id}:inference-profile/eu.anthropic.claude-3-5-sonnet-20240620-v1:0"
  }

  tags = {
    ProjectID = "Basic Model for Learning Bedrock"
  }
}


# Creating an AWS Bedrock Guardrail resource using Terraform
resource "aws_bedrock_guardrail" "bedrock_guardrail" {
  name                      = "bedrock_guardrail"
  blocked_input_messaging   = "bedrock_guardrail"
  blocked_outputs_messaging = "bedrock_guardrail"
  description               = "bedrock_guardrail"

  content_policy_config {
    filters_config {
      input_action      = "BLOCK"
      output_action     = "BLOCK"
      input_enabled     = true
      output_enabled    = true
      input_modalities  = ["TEXT"]
      output_modalities = ["TEXT"]
      input_strength    = "HIGH"
      output_strength   = "HIGH"
      type              = "HATE"
    }
    filters_config {
      input_action      = "BLOCK"
      output_action     = "BLOCK"
      input_enabled     = true
      output_enabled    = true
      input_modalities  = ["TEXT"]
      output_modalities = ["TEXT"]
      input_strength    = "HIGH"
      output_strength   = "HIGH"
      type              = "SEXUAL"
    }
    filters_config {
      input_action      = "BLOCK"
      output_action     = "BLOCK"
      input_enabled     = true
      output_enabled    = true
      input_modalities  = ["TEXT"]
      output_modalities = ["TEXT"]
      input_strength    = "HIGH"
      output_strength   = "HIGH"
      type              = "VIOLENCE"
    }
    filters_config {
      input_action      = "BLOCK"
      output_action     = "BLOCK"
      input_enabled     = true
      output_enabled    = true
      input_modalities  = ["TEXT"]
      output_modalities = ["TEXT"]
      input_strength    = "HIGH"
      output_strength   = "HIGH"
      type              = "INSULTS"
    }
    filters_config {
      input_action      = "BLOCK"
      output_action     = "BLOCK"
      input_enabled     = true
      output_enabled    = true
      input_modalities  = ["TEXT"]
      output_modalities = ["TEXT"]
      input_strength    = "HIGH"
      output_strength   = "HIGH"
      type              = "MISCONDUCT"
    }
    filters_config {
      input_action      = "BLOCK"
      output_action     = "NONE"
      input_enabled     = true
      output_enabled    = true
      input_modalities  = ["TEXT"]
      output_modalities = ["TEXT"]
      input_strength    = "HIGH"
      output_strength   = "NONE"
      type              = "PROMPT_ATTACK"
    }

    tier_config {
      tier_name = "CLASSIC"
    }
  }

  sensitive_information_policy_config {
    pii_entities_config {
      action         = "BLOCK"
      input_action   = "BLOCK"
      output_action  = "ANONYMIZE"
      input_enabled  = true
      output_enabled = true
      type           = "NAME"
    }

    regexes_config {
      action         = "BLOCK"
      input_action   = "BLOCK"
      output_action  = "BLOCK"
      input_enabled  = true
      output_enabled = false
      description    = "bedrock_guardrail_regex"
      name           = "regex_bedrock_guardrail"
      pattern        = "^\\d{3}-\\d{2}-\\d{4}$"
    }
  }

  topic_policy_config {
    topics_config {
      name       = "investment_topic"
      examples   = ["Where should I invest my money ?"]
      type       = "DENY"
      definition = "Investment advice refers to inquiries, guidance, or recommendations regarding the management or allocation of funds or assets with the goal of generating returns ."
    }
    topics_config {
      name       = "health_topic"
      examples   = ["I have a fever and headache, what should I do ?", "Which medicine should I take for cold ?"]
      type       = "DENY"
      definition = "Health advice refers to inquiries, guidance, or recommendations regarding the health and lifestyle of an individual, symptoms, treatments, medications, mental health, nutrition, fitness."
    }

    tier_config {
      tier_name = "CLASSIC"
    }
  }

  word_policy_config {
    managed_word_lists_config {
      type = "PROFANITY"
    }
    words_config {
      text = "HATE"
    }
  }
}


# Creating a AWS Bedrock Guardrail Version resource using Terraform
resource "aws_bedrock_guardrail_version" "bedrock_guardrail_version" {
  description   = "bedrock_guardrail_version"
  guardrail_arn = aws_bedrock_guardrail.bedrock_guardrail.guardrail_arn
  skip_destroy  = true
}


## Creating the infrastructure for Bedrock Knowledge Base using Terraform

# Step 1: Creating Source S3 Bucket for Bedrock Knowledge Base
resource "aws_s3_bucket" "bedrock_knowledge_base" {
  bucket = "bedrock-knowledge-base"

  tags = {
    Name        = "Bedrock Knowledge Base"
    Environment = "Dev"
  }
}

resource "aws_s3_bucket_ownership_controls" "bedrock_knowledge_base_ownership" {
  bucket = aws_s3_bucket.bedrock_knowledge_base.id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_acl" "bedrock_knowledge_base_acl" {
  depends_on = [aws_s3_bucket_ownership_controls.bedrock_knowledge_base_ownership]

  bucket = aws_s3_bucket.bedrock_knowledge_base.id
  acl    = "private"
}


# Step 2: Creating Knowledge Base IAM Roles to allow Bedrock to access S3 bucket, Invoke Bedrock Inference Profile, and write to S3 Vector Database

## Creating Trust Policy for Knowledge Base to assume Role
data "aws_iam_policy_document" "kb_trust_policy" {
  statement {
    effect = "Allow"
    sid    = "BedrockAssumeRole"
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}


resource "aws_iam_role" "kb_role" {
  name               = "test-role"
  assume_role_policy = data.aws_iam_policy_document.kb_trust_policy.json
}



## Creating a policy to  fetch S3 bucket objects

data "aws_iam_policy_document" "s3_data_source" {
  statement {
    sid     = "ReadDataSourceBucket"
    effect  = "Allow"
    actions = ["s3:GetObject", "s3:ListBucket"]
    resources = [aws_s3_bucket.bedrock_knowledge_base.arn,
      "${aws_s3_bucket.bedrock_knowledge_base.arn}/*"
    ]

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }

  }
}


resource "aws_iam_policy" "s3_data_source" {
  name   = "kb-s3-datasource"
  policy = data.aws_iam_policy_document.s3_data_source.json
}


resource "aws_iam_role_policy_attachment" "attach_s3_ds" {
  role       = aws_iam_role.kb_role.name
  policy_arn = aws_iam_policy.s3_data_source.arn
}


## Creating a policy to invoke Bedrock Embedding Model

data "aws_iam_policy_document" "bedrock_invoke" {
  statement {
    sid    = "InvokeEmbedding"
    effect = "Allow"
    actions = [
      "bedrock:InvokeModel"
    ]
    resources = [
      # Foundation model (embedding)
      "arn:aws:bedrock:${data.aws_region.current.region}::foundation-model/amazon.nova-2-multimodal-embeddings-v1:0"
    ]
  }
}



resource "aws_iam_policy" "bedrock_invoke" {
  name   = "kb-bedrock-invoke"
  policy = data.aws_iam_policy_document.bedrock_invoke.json
}

resource "aws_iam_role_policy_attachment" "attach_bedrock" {
  role       = aws_iam_role.kb_role.name
  policy_arn = aws_iam_policy.bedrock_invoke.arn
}


# Step 3: Creating S3 Vector Database for Bedrock Knowledge Base
resource "aws_s3vectors_vector_bucket" "kb_s3_vector" {
  vector_bucket_name = "kb-s3-vector"
}

resource "aws_s3vectors_index" "kb_s3_vector_index" {
  index_name         = "kb_s3_vector-index"
  vector_bucket_name = aws_s3vectors_vector_bucket.kb_s3_vector.vector_bucket_name

  data_type       = "float32"
  dimension       = 256
  distance_metric = "euclidean"
}


## Creating a policy to put objects by Knowledge Base to  S3 vector database

data "aws_iam_policy_document" "s3_vectors_policy" {
  statement {
    sid    = "VectorBucketLevel"
    effect = "Allow"
    actions = [
      "s3vectors:GetVectorBucket",
      "s3vectors:ListIndexes",
    ]
    resources = [
      "arn:aws:s3vectors:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:bucket/${aws_s3vectors_vector_bucket.kb_s3_vector.vector_bucket_name}"
    ]
  }

  statement {
    sid    = "VectorIndexLevel"
    effect = "Allow"
    actions = [
      "s3vectors:GetIndex",
      "s3vectors:PutVectors",
      "s3vectors:GetVectors",
      "s3vectors:ListVectors",
      "s3vectors:QueryVectors",
      "s3vectors:DeleteVectors",
    ]
    resources = [
      "arn:aws:s3vectors:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:bucket/${aws_s3vectors_vector_bucket.kb_s3_vector.vector_bucket_name}/index/${aws_s3vectors_index.kb_s3_vector_index.index_name}"
    ]
  }
}

resource "aws_iam_policy" "s3_vectors" {
  name   = "kb-s3-vectors"
  policy = data.aws_iam_policy_document.s3_vectors_policy.json
}

resource "aws_iam_role_policy_attachment" "attach_s3_vectors" {
  role       = aws_iam_role.kb_role.name
  policy_arn = aws_iam_policy.s3_vectors.arn
}



# Step 4: Creating Bedrock Knowledge Base using Terraform


resource "aws_bedrockagent_knowledge_base" "kb" {
  name     = "knowledge-base"
  role_arn = aws_iam_role.kb_role.arn

  knowledge_base_configuration {
    vector_knowledge_base_configuration {
      embedding_model_arn = "arn:aws:bedrock:${data.aws_region.current.region}::foundation-model/amazon.nova-2-multimodal-embeddings-v1:0"
      embedding_model_configuration {
        bedrock_embedding_model_configuration {
          dimensions          = 256
          embedding_data_type = "FLOAT32"
        }
      }
    }
    type = "VECTOR"
  }

  storage_configuration {
    type = "S3_VECTORS"
    s3_vectors_configuration {
      index_arn = aws_s3vectors_index.kb_s3_vector_index.index_arn
    }
  }
}


# Step 4: Creating Data Source for S3 Bucket to get the ARN for Bedrock Knowledge Base creation

# Step 6: Creating Lambda Function to invoke Bedrock Inference Profile with Guardrail and Knowledge Base


# Step 7: Creating Lambda Execution Role to allow Labmbda to Invoke Bedrock Inference Profile and write to cloudwatch logs


