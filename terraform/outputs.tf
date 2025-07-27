output "api_gateway_url" {
  description = "The URL of the API Gateway endpoint for the weather service."
  value       = "${aws_api_gateway_stage.weather_api_stage.invoke_url}/${aws_api_gateway_resource.weather_resource.path_part}"
}

output "frontend_website_url" {
  description = "The URL of the S3 static website endpoint."
  value       = aws_s3_bucket_website_configuration.frontend_website_config.website_endpoint
}

output "frontend_bucket_id" {
  description = "The ID of the S3 bucket hosting the frontend."
  value       = aws_s3_bucket.frontend_bucket.id
}

