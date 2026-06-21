# Creating a Bedrock Inference model from Foundation Models using Terraform

provider "aws" {
  region = "ap-south-1"
}


data "aws_caller_identity" "current" {}

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
