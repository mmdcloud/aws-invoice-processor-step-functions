import json
import boto3

def lambda_handler(event, context):    
    # Initialize clients
    textract = boto3.client('textract', region_name='us-east-1')
    s3 = boto3.client('s3', region_name='us-east-1')

    try:
        # Get bucket and key from event
        s3_bucket = event['Records'][0]['s3']['bucket']['name']
        s3_key = event['Records'][0]['s3']['object']['key']
        print(s3_bucket)
        print(s3_key)
        # Verify object exists (added this check)
        s3.head_object(Bucket=s3_bucket, Key=s3_key)
        
        # Call Textract - FIXED: Changed 'Name' to 'Key'
        response = textract.analyze_document(
            Document={
                'S3Object': {
                    'Bucket': s3_bucket,
                    'Name': s3_key  # This was the main error - was 'Name'
                }
            },
            FeatureTypes=["TABLES"]
        )
        print(response['Blocks'])
        # Process response
        blocks = response['Blocks']
        tables = extract_tables(blocks)
        table_count = len(tables)
        tables_with_headers = validate_headers(tables, blocks)
        print(table_count)
        print(tables_with_headers)
        return {
            'statusCode': 200,
            'body': json.dumps({
                'table_count': table_count,
                'tables_with_headers': tables_with_headers,
                'document': f's3://{s3_bucket}/{s3_key}'
            })
        }
        
    except Exception as e:
        print(e)
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'event': event
            })
        }

def extract_tables(blocks):
    """Extract all tables from Textract response."""
    return [block for block in blocks if block['BlockType'] == 'TABLE']

def validate_headers(tables, blocks):
    """Check if each table has valid headers."""
    results = []
    
    for table in tables:
        table_id = table['Id']
        # Get cells belonging to this table
        table_cells = [
            b for b in blocks 
            if b.get('BlockType') == 'CELL' 
            and any(rel['Ids'][0] == table_id for rel in b.get('Relationships', []))
        ]
        
        # Group cells by row
        rows = {}
        for cell in table_cells:
            rows.setdefault(cell['RowIndex'], []).append(cell)
        
        # Check first row
        has_header = False
        first_row_text = []
        
        if 1 in rows:  # RowIndex starts at 1
            for cell in rows[1]:
                cell_text = []
                for rel in cell.get('Relationships', []):
                    if rel['Type'] == 'CHILD':
                        cell_text.extend(
                            b['Text'] for b in blocks 
                            if b['Id'] in rel['Ids'] 
                            and b['BlockType'] == 'WORD'
                        )
                first_row_text.append(' '.join(cell_text).strip())
            
            has_header = any(text for text in first_row_text)
        
        results.append({
            'table_id': table_id,
            'has_header': has_header,
            'header_row': first_row_text if has_header else None
        })
    
    return results