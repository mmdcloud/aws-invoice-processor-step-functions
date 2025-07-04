import json
import boto3
import os

stepfunctions = boto3.client('stepfunctions')
step_function_arn = os.getenv("STEP_FUNCTION_ARN")

def lambda_handler(event, context):
    execution_arns = []    
    for record in event.get('Records', []):
        try:
            # Get message body (assuming it's JSON-formatted)
            message_body = record['body']
            print(f"SQS Event Body : {message_body}")
            # Start Step Function execution
            response = stepfunctions.start_execution(
                stateMachineArn=step_function_arn,
                input=message_body
            )            
            execution_arns.append(response['executionArn'])
            print(f"Started execution: {response['executionArn']}")
            
        except Exception as e:
            print(f"Error processing message {record.get('messageId', 'unknown')}: {str(e)}")
    
    return {
        'statusCode': 200,
        'executionArns': execution_arns
    }