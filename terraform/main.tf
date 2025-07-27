# Configure the AWS Provider
provider "aws" {
  region = var.aws_region
}

# --- Backend Lambda Function ---

# IAM Role for Lambda Function
resource "aws_iam_role" "lambda_exec_role" {
  name = "weather_app_lambda_exec_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

# Attach policy for Lambda to write logs to CloudWatch
resource "aws_iam_role_policy_attachment" "lambda_logging" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Lambda Function
resource "aws_lambda_function" "weather_fetcher" {
  function_name    = "weatherFetcherLambda"
  handler          = "lambda_function.lambda_handler" # File.Function
  runtime          = "python3.9" # Or latest stable Python runtime
  role             = aws_iam_role.lambda_exec_role.arn
  timeout          = 30 # seconds
  memory_size      = 128 # MB

  # Path to the zipped Lambda code
  filename         = "../backend_lambda.zip" # Relative path from where terraform is run
  source_code_hash = filebase64sha256("../backend_lambda.zip") # Recalculates hash on file change

  # Environment variables for RapidAPI keys
  environment {
    variables = {
      RAPIDAPI_KEY        = var.rapidapi_key
      RAPIDAPI_HOST       = var.rapidapi_host
      WEATHER_API_URL     = var.weather_api_url
      DYNAMODB_TABLE_NAME = aws_dynamodb_table.weather_app_users.name # Add this line
    }
  }

  tags = {
    Project = "WeatherApp"
    Service = "Backend"
  }
}

# --- API Gateway ---

# API Gateway REST API
resource "aws_api_gateway_rest_api" "weather_api" {
  name        = "WeatherAppAPI"
  description = "API Gateway for Weather App Backend"

  tags = {
    Project = "WeatherApp"
    Service = "API Gateway"
  }
}

# API Gateway Resource (e.g., /weather)
resource "aws_api_gateway_resource" "weather_resource" {
  rest_api_id = aws_api_gateway_rest_api.weather_api.id
  parent_id   = aws_api_gateway_rest_api.weather_api.root_resource_id
  path_part   = "weather" # The path part for your API endpoint (e.g., /weather)
}

# API Gateway Method (POST for fetching weather)
resource "aws_api_gateway_method" "weather_post_method" {
  rest_api_id   = aws_api_gateway_rest_api.weather_api.id
  resource_id   = aws_api_gateway_resource.weather_resource.id
  http_method   = "POST"
  authorization = "NONE" # No authorization for now, can add Cognito later
}

# API Gateway Method (GET for fetching weather - optional, if you want to allow GET /weather?city=London)
resource "aws_api_gateway_method" "weather_get_method" {
  rest_api_id   = aws_api_gateway_rest_api.weather_api.id
  resource_id   = aws_api_gateway_resource.weather_resource.id
  http_method   = "GET"
  authorization = "NONE" # No authorization for now
}

# API Gateway Method (OPTIONS for CORS preflight)
resource "aws_api_gateway_method" "weather_options_method" {
  rest_api_id   = aws_api_gateway_rest_api.weather_api.id
  resource_id   = aws_api_gateway_resource.weather_resource.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

# API Gateway Integration (connecting POST method to Lambda)
resource "aws_api_gateway_integration" "weather_lambda_integration_post" {
  rest_api_id             = aws_api_gateway_rest_api.weather_api.id
  resource_id             = aws_api_gateway_resource.weather_resource.id
  http_method             = aws_api_gateway_method.weather_post_method.http_method
  integration_http_method = "POST" # Lambda expects POST
  type                    = "AWS_PROXY" # Simple proxy integration
  uri                     = aws_lambda_function.weather_fetcher.invoke_arn
}

# API Gateway Integration (connecting GET method to Lambda)
resource "aws_api_gateway_integration" "weather_lambda_integration_get" {
  rest_api_id             = aws_api_gateway_rest_api.weather_api.id
  resource_id             = aws_api_gateway_resource.weather_resource.id
  http_method             = aws_api_gateway_method.weather_get_method.http_method
  integration_http_method = "POST" # Lambda expects POST
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.weather_fetcher.invoke_arn
}

# API Gateway Integration (for OPTIONS method - CORS preflight)
resource "aws_api_gateway_integration" "weather_options_integration" {
  rest_api_id          = aws_api_gateway_rest_api.weather_api.id
  resource_id          = aws_api_gateway_resource.weather_resource.id
  http_method          = aws_api_gateway_method.weather_options_method.http_method
  type                 = "MOCK" # MOCK integration for OPTIONS
  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
}

# API Gateway Method Response (for OPTIONS method - CORS preflight)
resource "aws_api_gateway_method_response" "weather_options_method_response" {
  rest_api_id = aws_api_gateway_rest_api.weather_api.id
  resource_id = aws_api_gateway_resource.weather_resource.id
  http_method = aws_api_gateway_method.weather_options_method.http_method
  status_code = "200"

  response_models = {
    "application/json" = "Empty"
  }
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

# API Gateway Integration Response (for OPTIONS method - CORS preflight)
resource "aws_api_gateway_integration_response" "weather_options_integration_response" {
  rest_api_id = aws_api_gateway_rest_api.weather_api.id
  resource_id = aws_api_gateway_resource.weather_resource.id
  http_method = aws_api_gateway_method.weather_options_method.http_method
  status_code = aws_api_gateway_method_response.weather_options_method_response.status_code

  response_templates = {
    "application/json" = ""
  }
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'"
    "method.response.header.Access-Control-Allow-Methods" = "'GET,POST,OPTIONS'"
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }
  # This needs to match the status code of the method response
  selection_pattern = ""
}


# API Gateway Deployment (to make changes live)
resource "aws_api_gateway_deployment" "weather_api_deployment" {
  rest_api_id = aws_api_gateway_rest_api.weather_api.id

  # Triggers a new deployment when Lambda or API Gateway resources change
  # This ensures the API Gateway is updated when the Lambda function is updated.
  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.weather_resource.id,
      aws_api_gateway_method.weather_post_method.id,
      aws_api_gateway_integration.weather_lambda_integration_post.id,
      aws_api_gateway_method.weather_get_method.id,
      aws_api_gateway_integration.weather_lambda_integration_get.id,
      aws_api_gateway_method.weather_options_method.id, # Add OPTIONS method to triggers
      aws_api_gateway_integration.weather_options_integration.id, # Add OPTIONS integration to triggers
      aws_api_gateway_method_response.weather_options_method_response.id, # Add OPTIONS method response to triggers
      aws_api_gateway_integration_response.weather_options_integration_response.id, # Add OPTIONS integration response to triggers
      aws_lambda_function.weather_fetcher.last_modified, # Trigger deployment on Lambda code change
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }
}

# API Gateway Stage (links a deployment to a URL)
resource "aws_api_gateway_stage" "weather_api_stage" {
  stage_name    = "v1" # Your API stage name
  rest_api_id   = aws_api_gateway_rest_api.weather_api.id
  deployment_id = aws_api_gateway_deployment.weather_api_deployment.id

  tags = {
    Project = "WeatherApp"
    Service = "API Gateway Stage"
  }
}

# Permissions for API Gateway to invoke Lambda function
resource "aws_lambda_permission" "api_gateway_lambda_permission" {
  statement_id  = "AllowAPIGatewayInvokeLambda"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.weather_fetcher.function_name
  principal     = "apigateway.amazonaws.com"
  # The /*/* part allows invocation from any method on any path under the API Gateway.
  # For more restrictive permissions, you can specify the exact path and method.
  source_arn    = "${aws_api_gateway_rest_api.weather_api.execution_arn}/*/*"
}

# --- DynamoDB Table ---

resource "aws_dynamodb_table" "weather_app_users" {
  name             = "weather-app-users"
  billing_mode     = "PAY_PER_REQUEST" # Cost-effective for low/variable usage
  hash_key         = "userId"

  attribute {
    name = "userId"
    type = "S" # String
  }

  tags = {
    Project = "WeatherApp"
    Service = "DynamoDB"
  }
}

# --- Update Lambda IAM Role to allow DynamoDB access ---
# This policy grants the Lambda function permissions to read/write to the DynamoDB table.
resource "aws_iam_policy" "lambda_dynamodb_policy" {
  name        = "weather_app_lambda_dynamodb_policy"
  description = "Allows Lambda to read/write to weather-app-users DynamoDB table"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:Query",
          "dynamodb:Scan"
        ],
        Effect   = "Allow",
        Resource = aws_dynamodb_table.weather_app_users.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_dynamodb_attachment" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = aws_iam_policy.lambda_dynamodb_policy.arn
}

# --- Frontend S3 Bucket for Static Website Hosting ---

# Generate a random suffix for the S3 bucket name to ensure uniqueness
resource "random_string" "bucket_suffix" {
  length  = 8
  special = false
  upper   = false
  numeric = true
}

resource "aws_s3_bucket" "frontend_bucket" {
  bucket = "weather-app-frontend-${var.aws_region}-${random_string.bucket_suffix.result}" # Unique bucket name

  tags = {
    Project = "WeatherApp"
    Service = "Frontend"
  }
}

resource "aws_s3_bucket_website_configuration" "frontend_website_config" {
  bucket = aws_s3_bucket.frontend_bucket.id

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "index.html" # Simple error page, redirects to index
  }
}

# Block public access to the bucket (best practice, then use bucket policy for specific public access)
resource "aws_s3_bucket_public_access_block" "frontend_public_access_block" {
  bucket = aws_s3_bucket.frontend_bucket.id

  block_public_acls       = false # Set to false
  block_public_policy     = false # Set to false
  ignore_public_acls      = false # Set to false
  restrict_public_buckets = false # Set to false
}


# S3 Bucket Policy to allow public read access for static website hosting
resource "aws_s3_bucket_policy" "frontend_bucket_policy" {
  bucket = aws_s3_bucket.frontend_bucket.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid       = "PublicReadGetObject",
        Effect    = "Allow",
        Principal = "*",
        Action    = "s3:GetObject",
        Resource  = "${aws_s3_bucket.frontend_bucket.arn}/*"
      }
    ]
  })
}
