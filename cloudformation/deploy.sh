#!/usr/bin/env bash
# ==============================================================================
# Production Deployment Script for AWS Invoice Processor Pipeline (CloudFormation)
# ==============================================================================
set -euo pipefail

# Default configuration values
STACK_NAME="invoice-processor"
REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-1}}"
ENVIRONMENT="prod"
NOTIFICATION_EMAIL=""
ARTIFACT_BUCKET=""
ENABLE_VPC="false"
INVOICES_BUCKET_NAME=""
PROFILE_FLAG=""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TEMPLATE_FILE="${SCRIPT_DIR}/template.yaml"

usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Required Options:
  -e, --email <email>             Notification email address for failure alerts.
  -b, --bucket <bucket-name>      S3 bucket to store Lambda deployment packages (.zip).

Optional Options:
  -s, --stack-name <name>         CloudFormation stack name (default: "invoice-processor").
  -r, --region <region>           AWS region (default: "us-east-1").
  -p, --profile <profile>         AWS CLI credentials profile.
  --env <environment>             Environment: dev, staging, prod (default: "prod").
  --invoices-bucket <name>        Custom name for uploaded invoices bucket.
  --enable-vpc                    Enable supporting VPC deployment (default: false).
  -h, --help                      Show this help message.

Example:
  $(basename "$0") -e alerts@example.com -b my-deployment-bucket-12345 --env prod
EOF
    exit 1
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -e|--email)
            NOTIFICATION_EMAIL="$2"
            shift 2
            ;;
        -b|--bucket)
            ARTIFACT_BUCKET="$2"
            shift 2
            ;;
        -s|--stack-name)
            STACK_NAME="$2"
            shift 2
            ;;
        -r|--region)
            REGION="$2"
            shift 2
            ;;
        -p|--profile)
            PROFILE_FLAG="--profile $2"
            shift 2
            ;;
        --env)
            ENVIRONMENT="$2"
            shift 2
            ;;
        --invoices-bucket)
            INVOICES_BUCKET_NAME="$2"
            shift 2
            ;;
        --enable-vpc)
            ENABLE_VPC="true"
            shift 1
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Error: Unknown argument: $1" >&2
            usage
            ;;
    esac
done

# Validation
if [[ -z "${NOTIFICATION_EMAIL}" ]]; then
    echo "Error: --email is required." >&2
    usage
fi

if [[ -z "${ARTIFACT_BUCKET}" ]]; then
    echo "Error: --bucket is required." >&2
    usage
fi

command -v aws >/dev/null 2>&1 || { echo "Error: 'aws' CLI is required but not installed." >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "Error: 'python3' is required but not installed." >&2; exit 1; }

echo "======================================================================"
echo " Starting CloudFormation Deployment: ${STACK_NAME} (${ENVIRONMENT})"
echo " Region: ${REGION}"
echo " Artifact Bucket: ${ARTIFACT_BUCKET}"
echo " Notification Email: ${NOTIFICATION_EMAIL}"
echo "======================================================================"

# 1. Ensure artifact bucket exists or create it
echo "==> Verifying artifact S3 bucket: ${ARTIFACT_BUCKET}..."
if ! aws s3api head-bucket --bucket "${ARTIFACT_BUCKET}" ${PROFILE_FLAG} --region "${REGION}" 2>/dev/null; then
    echo "==> Artifact bucket does not exist. Creating s3://${ARTIFACT_BUCKET}..."
    if [[ "${REGION}" == "us-east-1" ]]; then
        aws s3api create-bucket --bucket "${ARTIFACT_BUCKET}" ${PROFILE_FLAG} --region "${REGION}"
    else
        aws s3api create-bucket --bucket "${ARTIFACT_BUCKET}" ${PROFILE_FLAG} --region "${REGION}" \
            --create-bucket-configuration LocationConstraint="${REGION}"
    fi
    aws s3api put-bucket-encryption --bucket "${ARTIFACT_BUCKET}" ${PROFILE_FLAG} \
        --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
    aws s3api put-public-access-block --bucket "${ARTIFACT_BUCKET}" ${PROFILE_FLAG} \
        --public-access-block-configuration "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
fi

# 2. Package Lambda zip files from src/
DIST_DIR="${SCRIPT_DIR}/build"
mkdir -p "${DIST_DIR}"

echo "==> Packaging Lambda functions from ${PROJECT_ROOT}/src..."
python3 - << PYEOF
import zipfile, os

src_dir = "${PROJECT_ROOT}/src"
dist_dir = "${DIST_DIR}"

lambdas = ["start_step_function", "table_sanity_check", "extract_table_data"]
for name in lambdas:
    py_file = os.path.join(src_dir, f"{name}.py")
    zip_file = os.path.join(dist_dir, f"{name}.zip")
    with zipfile.ZipFile(zip_file, "w", zipfile.ZIP_DEFLATED) as z:
        z.write(py_file, arcname=f"{name}.py")
    print(f"    Packaged {zip_file}")
PYEOF

# 3. Upload packages to artifact S3 bucket
echo "==> Uploading Lambda packages to s3://${ARTIFACT_BUCKET}/..."
aws s3 cp "${DIST_DIR}/start_step_function.zip" "s3://${ARTIFACT_BUCKET}/start_step_function.zip" ${PROFILE_FLAG}
aws s3 cp "${DIST_DIR}/table_sanity_check.zip" "s3://${ARTIFACT_BUCKET}/table_sanity_check.zip" ${PROFILE_FLAG}
aws s3 cp "${DIST_DIR}/extract_table_data.zip" "s3://${ARTIFACT_BUCKET}/extract_table_data.zip" ${PROFILE_FLAG}

# 4. Prepare parameters
PARAMS=(
    "Environment=${ENVIRONMENT}"
    "NotificationEmail=${NOTIFICATION_EMAIL}"
    "LambdaCodeBucket=${ARTIFACT_BUCKET}"
    "StartStepFunctionCodeKey=start_step_function.zip"
    "TableSanityCheckCodeKey=table_sanity_check.zip"
    "ExtractTableDataCodeKey=extract_table_data.zip"
    "EnableVPC=${ENABLE_VPC}"
)

if [[ -n "${INVOICES_BUCKET_NAME}" ]]; then
    PARAMS+=("InvoicesBucketName=${INVOICES_BUCKET_NAME}")
fi

if [[ "${ENABLE_VPC}" == "true" ]]; then
    AZS=$(aws ec2 describe-availability-zones --region "${REGION}" ${PROFILE_FLAG} \
        --query 'AvailabilityZones[?State==`available`].ZoneName' --output text | tr '\t' ',' | cut -d',' -f1,2)
    PARAMS+=("AvailabilityZones=${AZS}")
else
    # Supply dummy AZs since Parameter requires list when template evaluated
    PARAMS+=("AvailabilityZones=${REGION}a,${REGION}b")
fi

# 5. Deploy CloudFormation Stack
echo "==> Deploying CloudFormation Stack '${STACK_NAME}'..."
aws cloudformation deploy \
    --template-file "${TEMPLATE_FILE}" \
    --stack-name "${STACK_NAME}" \
    --capabilities CAPABILITY_NAMED_IAM \
    --parameter-overrides "${PARAMS[@]}" \
    --region "${REGION}" \
    --tags Project=invoice-processor Environment="${ENVIRONMENT}" \
    ${PROFILE_FLAG}

echo "======================================================================"
echo " Stack Deployment Succeeded!"
echo "======================================================================"
echo "Outputs:"
aws cloudformation describe-stacks \
    --stack-name "${STACK_NAME}" \
    --region "${REGION}" \
    ${PROFILE_FLAG} \
    --query "Stacks[0].Outputs[*].[OutputKey,OutputValue]" \
    --output table

echo ""
echo "IMPORTANT NEXT STEPS:"
echo "1. Check your inbox at '${NOTIFICATION_EMAIL}' and click 'Confirm subscription' on the AWS SNS confirmation emails."
echo "2. Upload an invoice PDF to the Invoices S3 Bucket output above to trigger the pipeline."
EOF