import json
import boto3

def lambda_handler(event:, context):
    stepfunctions = boto3.client('stepfunctions')
    execution_arns = []
    
    for record in event.get('Records', []):
        try:
            # Get message body (assuming it's JSON-formatted)
            message_body = record['body']
            
            # Start Step Function execution
            response = stepfunctions.start_execution(
                stateMachineArn='YOUR_STATE_MACHINE_ARN',
                input=message_body
                # Optional: name='unique-execution-name-{}'.format(record['messageId'])
            )
            
            execution_arns.append(response['executionArn'])
            print(f"Started execution: {response['executionArn']}")
            
        except Exception as e:
            print(f"Error processing message {record.get('messageId', 'unknown')}: {str(e)}")
            # You might want to implement custom error handling here
    
    return {
        'statusCode': 200,
        'executionArns': execution_arns
    }