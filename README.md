# Weather App Project Notes

This document summarizes the AWS resources and key configurations for the Weather App project.

## Architecture:
- Frontend: Static HTML/CSS/JS hosted on AWS S3.
- Backend: Python Lambda function triggered by AWS API Gateway.
- Database: AWS DynamoDB for user data and preferences.
- IaC: Terraform for provisioning all AWS resources.
- CI/CD: GitHub Actions for automated deployments.

## Key AWS Resources:
- **Lambda Function:** `weatherFetcherLambda` (Python 3.9)
  - Environment Variables: `RAPIDAPI_KEY`, `RAPIDAPI_HOST`, `WEATHER_API_URL`, `DYNAMODB_TABLE_NAME`
  - IAM Role: `weather_app_lambda_exec_role` with `AWSLambdaBasicExecutionRole` and `weather_app_lambda_dynamodb_policy`.
- **API Gateway:** `WeatherAppAPI`
  - Endpoint: `/weather` supporting `POST`, `GET`, and `OPTIONS` (for CORS).
  - Stage: `v1`
- **DynamoDB Table:** `weather-app-users`
  - Primary Key: `userId` (String)
  - Billing Mode: `PAY_PER_REQUEST`
- **S3 Bucket (Frontend):** `weather-app-frontend-<region>-<random_suffix>`
  - Configured for static website hosting.
  - Public access enabled via bucket policy.

## External Integrations:
- **RapidAPI:** Used for fetching weather data. Requires `RAPIDAPI_KEY`, `RAPIDAPI_HOST`, `WEATHER_API_URL`.

## Deployment Process:
1.  **Local Setup:**
    - `pip install -r backend/requirements.txt -t backend/`
    - `zip -r backend_lambda.zip backend/*` (from project root)
2.  **Terraform Deployment (from `terraform/` directory):**
    - `terraform init`
    - `terraform plan`
    - `terraform apply`
    - Outputs: `api_gateway_url`, `frontend_website_url`, `frontend_bucket_id`
3.  **Frontend Update & Upload:**
    - Manually update `frontend/index.html` with `API_GATEWAY_URL` output.
    - `aws s3 cp frontend/index.html s3://<frontend_bucket_id>/ --acl public-read`
4.  **CI/CD (GitHub Actions):**
    - AWS credentials and RapidAPI keys stored as GitHub Secrets.
    - Workflow in `.github/workflows/main.yml` automates packaging, Terraform apply, and S3 sync on `main` branch pushes.

## Troubleshooting Tips:
- **"Access Denied" on Frontend:** Check S3 bucket public access blocks and bucket policy. Ensure `block_public_acls`, `block_public_policy`, `ignore_public_acls`, `restrict_public_buckets` are all `false` in `aws_s3_bucket_public_access_block`.
- **"Could not connect to weather service" (Frontend):**
    - Verify `API_GATEWAY_URL` in `index.html` matches `terraform output api_gateway_url` exactly.
    - Ensure `index.html` is re-uploaded to S3 after updating the URL.
    - Check browser console for CORS errors. API Gateway needs explicit CORS configuration for `OPTIONS` method.
    - Check Lambda CloudWatch logs for backend errors (e.g., RapidAPI quota exceeded, incorrect API key).
- **Terraform "Undeclared Resource":** Run `terraform apply` to ensure state file is updated with all resource definitions and outputs.

## Cleanup:
- To destroy all AWS resources created by Terraform:
  - Navigate to `terraform/` directory.
  - Run `terraform destroy`. Confirm with `yes`.

---
*Last updated: [Current Date, e.g., July 28, 2025]*
