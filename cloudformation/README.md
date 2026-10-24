# 🚀 Production-Grade CloudFormation Configuration

This directory contains the production-grade AWS CloudFormation templates and deployment tooling for the **Serverless Invoice Processing Pipeline**, mirroring and enhancing the Terraform infrastructure.

---

## 🏗 Architecture Overview

```ascii
[1] Upload PDF/Image
       │
       ▼
[2] S3 Bucket ("invoices-<random-id>")
       │ (s3:ObjectCreated:*)
       ▼
[3] SQS Queue ("document-event-queue") ──[3 retries failed]──► SQS DLQ ("document-event-dlq")
       │
       ▼
[4] Lambda ("start-step-function")
       │ (Filters test events, starts execution)
       ▼
[5] Step Functions Workflow ("InvoiceProcessingWorkflow")
       ├── Step A: "Validate Table Information" (Lambda: table-sanity-check)
       │           • Uses ResultPath: $.validation_result (preserves S3 metadata)
       │           • Calls AWS Textract analyze_document
       │
       ├── Step B: "If validated" Choice State
       │           • Valid: statusCode == 200 and tables_count == 1
       │           • Invalid / Error ──────────────────────────► SNS ("invalid-invoice-error-topic")
       │                                                                │
       │                                                                ▼ (Email Alert)
       ├── Step C: "Extract and Store Table Data" (Lambda: extract-table-data)
       │           • Reads S3 key from execution state
       │           • Extracts table rows & formats data
       │           • Persists item + TTL to DynamoDB ("invoice-records")
       │
       ├── Step D: "If data stored successfully" Choice State
       │           • Success: statusCode == 200
       │           • Failure ──────────────────────────────────► SNS ("data-storage-failure-topic")
       │                                                                │
       │                                                                ▼ (Email Alert)
       └── Step E: "Success" (Succeed state)
```

---

## 📁 Directory Structure

```
cloudformation/
├── template.yaml            # Main production CloudFormation stack (App + Serverless Pipeline)
├── vpc.yaml                # Standalone modular VPC stack (Optional foundation networking)
├── parameters-dev.json      # Sample parameter values for development
├── parameters-prod.json     # Production parameters with high durability & retention
├── deploy.sh               # Automated build, package, upload, and deployment bash script
└── README.md               # Architecture, parameters, and deployment documentation
```

---

## 🔒 Production-Grade Features & Best Practices

1. **Circular Dependency Prevention**:
   - S3-to-SQS bucket notifications are decoupled from queue policy creation using account-scoped condition checks (`aws:SourceAccount`) and `DependsOn: DocumentEventQueuePolicy`.
2. **State & Metadata Preservation**:
   - Step Functions states utilize `ResultPath: $.validation_result` and `ResultPath: $.extraction_result` so initial S3 event payloads are never lost.
3. **Data Protection & Encryption**:
   - **S3**: Default SSE-AES256 encryption, public access block enforced, and object versioning enabled.
   - **SQS**: SQS-managed server-side encryption enabled on both primary and dead letter queues.
   - **DynamoDB**: Server-side encryption enabled, Point-in-Time Recovery (PITR) enabled by default in production.
   - **SNS**: Server-side KMS encryption enabled.
4. **Resilience & Error Handling**:
   - SQS Dead Letter Queue (DLQ) configured with 14-day message retention for failed events.
   - Step Functions automatic retries with full jitter backoff on transient Lambda errors.
   - SNS topics configured with dual authorization allowing both the AWS account owner and `states.amazonaws.com` (Step Functions).
5. **Observability & Logging**:
   - Dedicated CloudWatch Log Groups for each Lambda function with configurable retention (default: 30 days in prod).
   - Step Functions execution logging enabled to CloudWatch (`/aws/vendedlogs/states/...`).
   - AWS X-Ray Active Tracing enabled on Step Functions state machine.
6. **Least Privilege IAM**:
   - Distinct, scoped IAM roles for each pipeline component with exact resource ARNs.

---

## 🚀 Quick Deployment Guide

### Prerequisites
- AWS CLI configured (`aws configure`) with administrative permissions.
- Python 3.8+ installed locally.

---

### Method 1: Using the Automated Script (`deploy.sh`) — Recommended

The included `deploy.sh` script automatically packages the Lambda source code from `../src/`, uploads the zip artifacts to your S3 deployment bucket, and deploys the CloudFormation stack:

```bash
cd cloudformation

# Make executable (already done)
chmod +x deploy.sh

# Deploy to production
./deploy.sh \
  --email "your-email@example.com" \
  --bucket "your-lambda-artifacts-bucket" \
  --stack-name "invoice-processor-prod" \
  --region "us-east-1" \
  --env prod
```

To also deploy the optional VPC:
```bash
./deploy.sh \
  --email "your-email@example.com" \
  --bucket "your-lambda-artifacts-bucket" \
  --enable-vpc
```

---

### Method 2: Manual AWS CLI Deployment

If you prefer deploying step-by-step using standard AWS CLI commands:

#### 1. Package the Lambda functions
```bash
cd ../src
zip -r ../cloudformation/start_step_function.zip start_step_function.py
zip -r ../cloudformation/table_sanity_check.zip table_sanity_check.py
zip -r ../cloudformation/extract_table_data.zip extract_table_data.py
cd ../cloudformation
```

#### 2. Upload packages to an S3 deployment bucket
```bash
ARTIFACT_BUCKET="your-lambda-artifacts-bucket"

aws s3 cp start_step_function.zip s3://${ARTIFACT_BUCKET}/start_step_function.zip
aws s3 cp table_sanity_check.zip s3://${ARTIFACT_BUCKET}/table_sanity_check.zip
aws s3 cp extract_table_data.zip s3://${ARTIFACT_BUCKET}/extract_table_data.zip
```

#### 3. Deploy the CloudFormation stack
```bash
aws cloudformation deploy \
  --template-file template.yaml \
  --stack-name invoice-processor \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides \
      Environment=prod \
      NotificationEmail="alerts@example.com" \
      LambdaCodeBucket="${ARTIFACT_BUCKET}" \
      StartStepFunctionCodeKey="start_step_function.zip" \
      TableSanityCheckCodeKey="table_sanity_check.zip" \
      ExtractTableDataCodeKey="extract_table_data.zip" \
  --tags Project=invoice-processor Environment=prod
```

---

### Method 3: Deploying via AWS Management Console

1. Package and upload the 3 zip files (`start_step_function.zip`, `table_sanity_check.zip`, `extract_table_data.zip`) to an S3 bucket in your account.
2. Open the **AWS CloudFormation Console** at [https://console.aws.amazon.com/cloudformation](https://console.aws.amazon.com/cloudformation).
3. Click **Create stack** -> **With new resources (standard)**.
4. Choose **Upload a template file** and select `template.yaml`.
5. Enter stack name (e.g., `invoice-processor`) and configure the parameters:
   - `NotificationEmail`: Your email for error notifications.
   - `LambdaCodeBucket`: The S3 bucket name from Step 1.
6. Acknowledge that AWS CloudFormation might create IAM resources with custom names (`CAPABILITY_NAMED_IAM`).
7. Click **Submit**.

---

## ⚙️ Parameters Reference

| Parameter Name | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `Environment` | String | `prod` | Deployment environment (`dev`, `staging`, `prod`). |
| `NotificationEmail` | String | *Required* | Email address to receive alerts for invalid invoices or storage failures. |
| `InvoicesBucketName` | String | `""` (Auto-generated) | Optional custom name for the invoices S3 upload bucket. |
| `LambdaCodeBucket` | String | *Required* | S3 bucket containing the zipped Lambda functions. |
| `StartStepFunctionCodeKey` | String | `start_step_function.zip` | S3 object key for start_step_function package. |
| `TableSanityCheckCodeKey` | String | `table_sanity_check.zip` | S3 object key for table_sanity_check package. |
| `ExtractTableDataCodeKey` | String | `extract_table_data.zip` | S3 object key for extract_table_data package. |
| `DynamoDBBillingMode` | String | `PAY_PER_REQUEST` | `PAY_PER_REQUEST` (On-Demand) or `PROVISIONED`. |
| `DynamoDBPointInTimeRecovery` | String | `true` | Enable continuous Point-in-Time Recovery backups (`true`/`false`). |
| `LogRetentionInDays` | Number | `30` | CloudWatch Log Group retention period (7, 14, 30, 60, 90, 180, 365). |
| `SQSVisibilityTimeout` | Number | `180` | SQS visibility timeout in seconds (>= 3x Lambda timeout). |
| `SQSMessageRetentionPeriod`| Number | `345600` | SQS message retention period (seconds, default: 4 days). |
| `EnableVPC` | String | `false` | Deploy supporting VPC and subnets (`true`/`false`). |
| `VpcCidr` | String | `10.0.0.0/16` | CIDR block when `EnableVPC` is true. |
| `AvailabilityZones` | List | *Optional* | List of AZ names for subnets when `EnableVPC` is true. |

---

## 🧪 Post-Deployment Verification & Testing

1. **Confirm SNS Email Subscriptions**:
   - Check the inbox for the email configured in `NotificationEmail`.
   - Click the **"Confirm subscription"** link on both emails (`invalid-invoice-error-topic` and `data-storage-failure-topic`).
2. **Find the Upload Bucket**:
   - Run:
     ```bash
     aws cloudformation describe-stacks \
       --stack-name invoice-processor \
       --query "Stacks[0].Outputs[?OutputKey=='InvoicesBucketName'].OutputValue" \
       --output text
     ```
3. **Upload a Sample Invoice**:
   ```bash
   aws s3 cp sample_invoice.pdf s3://<InvoicesBucketName>/sample_invoice.pdf
   ```
4. **Monitor Workflow**:
   - Navigate to the **AWS Step Functions Console** and select `invoice-processor-InvoiceProcessingWorkflow`.
   - You will see the execution transition through validation, table extraction, and success.
5. **Verify DynamoDB Records**:
   - Check the DynamoDB table `invoice-processor-invoice-records` in the AWS console to inspect the extracted table rows, timestamps, and metadata.

---

## 🧹 Teardown / Deletion

To remove all resources created by this stack:

```bash
# 1. Empty the invoices S3 bucket first (AWS S3 blocks deletion of non-empty buckets)
INVOICES_BUCKET=$(aws cloudformation describe-stacks --stack-name invoice-processor \
  --query "Stacks[0].Outputs[?OutputKey=='InvoicesBucketName'].OutputValue" --output text)
aws s3 rm s3://${INVOICES_BUCKET} --recursive

# 2. Delete the CloudFormation stack
aws cloudformation delete-stack --stack-name invoice-processor

# 3. Wait for deletion to complete
aws cloudformation wait stack-delete-complete --stack-name invoice-processor
```

