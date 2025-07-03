import json
import boto3

def lambda_handler(event, context):
    # Initialize Textract client
    textract = boto3.client('textract')
    
    # Get S3 bucket and file from the event (triggered by S3 upload)
    s3_bucket = event['Records'][0]['s3']['bucket']['name']
    s3_key = event['Records'][0]['s3']['object']['key']
    
    # Call Textract to detect tables
    response = textract.analyze_document(
        Document={
            'S3Object': {
                'Bucket': s3_bucket,
                'Name': s3_key
            }
        },
        FeatureTypes=["TABLES"]  # Focus only on tables
    )
    
    # Process the response
    tables = extract_tables(response)
    table_count = len(tables)
    tables_with_headers = validate_headers(tables, response['Blocks'])  # Pass blocks as parameter
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'table_count': table_count,
            'tables_with_headers': tables_with_headers,
            'document': f's3://{s3_bucket}/{s3_key}'
        })
    }

def extract_tables(textract_response):
    """Extract all tables from Textract response."""
    tables = []
    blocks = textract_response['Blocks']
    
    for block in blocks:
        if block['BlockType'] == 'TABLE':
            tables.append(block)
    
    return tables

def validate_headers(tables, blocks):  # Added blocks parameter
    """Check if each table has valid headers (non-empty first row)."""
    results = []
    
    for table in tables:
        table_id = table['Id']
        # Get all cells in this table
        cells = [b for b in blocks if b.get('BlockType') == 'CELL' and b.get('Relationships')]
        # Filter cells belonging to this table
        table_cells = [c for c in cells if any(rel['Ids'][0] == table_id for rel in c.get('Relationships', []))]
        
        # Group cells by row
        rows = {}
        for cell in table_cells:
            row_index = cell['RowIndex']
            if row_index not in rows:
                rows[row_index] = []
            rows[row_index].append(cell)
        
        # Check if the first row exists and has non-empty cells
        has_header = False
        first_row_text = []
        if 1 in rows:
            first_row_cells = rows[1]
            for cell in first_row_cells:
                cell_text = []
                for rel in cell.get('Relationships', []):
                    if rel['Type'] == 'CHILD':
                        for word_id in rel['Ids']:
                            word_block = next((b for b in blocks if b['Id'] == word_id and b['BlockType'] == 'WORD'), None)
                            if word_block:
                                cell_text.append(word_block['Text'])
                first_row_text.append(' '.join(cell_text).strip())
            
            has_header = any(text for text in first_row_text)
        
        results.append({
            'table_id': table_id,
            'has_header': has_header,
            'header_row': first_row_text if has_header else None
        })
    print(results)
    return results