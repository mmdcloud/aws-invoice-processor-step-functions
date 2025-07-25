import json
import boto3

# Initialize Textract client
textract = boto3.client('textract', region_name='us-east-1')
s3 = boto3.client('s3', region_name='us-east-1')

def lambda_handler(event, context):
    try:
        print(event)
        # Get S3 bucket and file from the event (triggered by S3 upload)
        s3_bucket = event['Payload']['Records'][0]['s3']['bucket']['name']
        s3_key = event['Payload']['Records'][0]['s3']['object']['key']
        # Verify object exists (added this check)
        head_response = s3.head_object(Bucket=s3_bucket, Key=s3_key)
        print("Object metadata:", head_response)
        print(event)
        # Call Textract to detect tables
        response = textract.analyze_document(
            Document={
                'S3Object': {
                    'Bucket': s3_bucket,
                    'Name': s3_key
                }
            },
            FeatureTypes=["TABLES"]  # Only extract tables
        )
        # Process the response to count tables and header fields
        tables_count = 0
        total_header_fields = 0
        table_details = []
        
        # Extract blocks from response
        blocks = response['Blocks']
        
        # Create a map of block IDs to blocks for easy lookup
        block_map = {block['Id']: block for block in blocks}
        
        # Find all TABLE blocks
        for block in blocks:
            if block['BlockType'] == 'TABLE':
                tables_count += 1
                header_fields_count = 0
                table_info = {
                    'table_id': block['Id'],
                    'confidence': block.get('Confidence', 0),
                    'header_fields': []
                }
                
                # Get table relationships to find cells
                if 'Relationships' in block:
                    for relationship in block['Relationships']:
                        if relationship['Type'] == 'CHILD':
                            # Process each cell in the table
                            for cell_id in relationship['Ids']:
                                cell_block = block_map.get(cell_id)
                                if cell_block and cell_block['BlockType'] == 'CELL':
                                    # Check if this cell is in the header row (RowIndex = 1)
                                    if cell_block.get('RowIndex') == 1:
                                        header_fields_count += 1
                                        cell_text = extract_cell_text(cell_block, block_map)
                                        table_info['header_fields'].append({
                                            'column_index': cell_block.get('ColumnIndex', 0),
                                            'text': cell_text,
                                            'confidence': cell_block.get('Confidence', 0)
                                        })
                
                table_info['header_fields_count'] = header_fields_count
                total_header_fields += header_fields_count
                table_details.append(table_info)
        
        # Prepare response
        result = {
            'tables_count': tables_count,
            'total_header_fields': total_header_fields,
            'table_details': table_details,
            'processing_status': 'SUCCESS'
        }
        
        return {
            'statusCode': 200,
            'body': result
        }    
    except Exception as e:
        print(e)
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': f'Unexpected error: {str(e)}',
                'processing_status': 'FAILED'
            })
        }

def extract_cell_text(cell_block, block_map):
    """
    Extract text from a cell block by following its relationships
    """
    text = ""
    if 'Relationships' in cell_block:
        for relationship in cell_block['Relationships']:
            if relationship['Type'] == 'CHILD':
                for child_id in relationship['Ids']:
                    child_block = block_map.get(child_id)
                    if child_block and child_block['BlockType'] == 'WORD':
                        text += child_block.get('Text', '') + " "
    return text.strip()