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
        FeatureTypes=["TABLES"]  # Only extract tables
    )
    
    # Process the response to extract table data
    tables = extract_table_data(response)
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'tables': tables,
            'document': f's3://{s3_bucket}/{s3_key}'
        })
    }

def extract_table_data(textract_response):
    """Extracts and structures table data from Textract response."""
    tables = []
    
    # Get all blocks (cells, words, etc.) from Textract
    blocks = textract_response['Blocks']
    
    # Extract tables
    for block in blocks:
        if block['BlockType'] == 'TABLE':
            table = {'rows': []}
            
            # Get all cells (TABLE_CELL blocks) in this table
            cells = [b for b in blocks if b['BlockType'] == 'CELL' and b.get('Relationships')]
            
            # Group cells by row
            rows = {}
            for cell in cells:
                row_index = cell['RowIndex']
                if row_index not in rows:
                    rows[row_index] = []
                rows[row_index].append(cell)
            
            # Sort cells by column index and extract text
            for row_index, cells_in_row in rows.items():
                cells_in_row_sorted = sorted(cells_in_row, key=lambda x: x['ColumnIndex'])
                row_text = []
                for cell in cells_in_row_sorted:
                    # Extract text from cell (linked WORD blocks)
                    cell_text = []
                    if 'Relationships' in cell:
                        for rel in cell['Relationships']:
                            if rel['Type'] == 'CHILD':
                                for word_id in rel['Ids']:
                                    word_block = next(b for b in blocks if b['Id'] == word_id and b['BlockType'] == 'WORD')
                                    cell_text.append(word_block['Text'])
                    row_text.append(' '.join(cell_text))
                table['rows'].append(row_text)
            
            tables.append(table)
    
    return tables