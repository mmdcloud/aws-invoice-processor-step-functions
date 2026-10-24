import json
import os
import boto3

region = os.getenv("AWS_REGION", os.getenv("AWS_DEFAULT_REGION", "ap-southeast-2"))
stepfunctions = boto3.client("stepfunctions", region_name=region)
step_function_arn = os.getenv("STEP_FUNCTION_ARN")


def lambda_handler(event, context):
    execution_arns = []
    batch_item_failures = []

    for record in event.get("Records", []):
        record_id = record.get("messageId")
        try:
            message_body = record["body"]
            print(f"SQS Event Body: {message_body}")

            # Parse message to validate and filter
            body_json = json.loads(message_body) if isinstance(message_body, str) else message_body

            # Skip S3 test notifications
            if body_json.get("Event") == "s3:TestEvent":
                print("Skipping s3:TestEvent notification.")
                continue

            if not body_json.get("Records"):
                print(f"No S3 Records found in message: {message_body}")
                continue

            # Start Step Function execution
            payload_input = message_body if isinstance(message_body, str) else json.dumps(message_body)
            response = stepfunctions.start_execution(
                stateMachineArn=step_function_arn,
                input=payload_input,
            )
            execution_arns.append(response["executionArn"])
            print(f"Started Step Function execution: {response['executionArn']}")

        except Exception as e:
            print(f"Error processing record {record_id or 'unknown'}: {str(e)}")
            if record_id:
                batch_item_failures.append({"itemIdentifier": record_id})

    return {
        "statusCode": 200,
        "batchItemFailures": batch_item_failures,
        "executionArns": execution_arns,
    }
