output "inference_endpoint_arn" {
  value       = aws_bedrock_inference_profile.bedrock_inference_profile.arn
  description = "The ARN of the Bedrock Inference Profile"
}

output "guardrail_id" {
  value       = aws_bedrock_guardrail.bedrock_guardrail.guardrail_id
  description = "The ID of the Bedrock Guardrail"
}

output "gurardrail_version_number" {
  value       = aws_bedrock_guardrail.bedrock_guardrail.version
  description = "The version number of the Bedrock Guardrail"
}
