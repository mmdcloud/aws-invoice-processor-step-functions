import datetime
import json
import os
import time
import urllib.parse
import uuid
import boto3

region = os.getenv("AWS_REGION", os.getenv("AWS_DEFAULT_REGION", "us-east-1"))
textract = boto3.client("textract", region_name=region)
s3 = boto3.client("s3", region_name=region)
dynamodb = boto3.resource("dynamodb", region_name=region)
table_name = os.getenv("DYNAMODB_TABLE", "invoice-records")


def lambda_handler(event, context):
    s3_bucket = None
    s3_key = None
    try:
        print("Received event:", json.dumps(event, default=str))

        # Extract S3 records from direct event or wrapped payload
        records = event.get("Records")
        if not records and "Payload" in event and isinstance(event["Payload"], dict):
            records = event["Payload"].get("Records")

        if not records or not isinstance(records, list) or len(records) == 0:
            raise ValueError(f"No valid S3 Records found in event: {event}")

        raw_bucket = records[0]["s3"]["bucket"]["name"]
        raw_key = records[0]["s3"]["object"]["key"]
        s3_bucket = urllib.parse.unquote_plus(raw_bucket)
        s3_key = urllib.parse.unquote_plus(raw_key)

        print(f"Processing invoice s3://{s3_bucket}/{s3_key}")

        # Verify object exists in S3
        head_response = s3.head_object(Bucket=s3_bucket, Key=s3_key)
        print("Object metadata:", head_response)

        # Call Textract to detect tables
        response = textract.analyze_document(
            Document={
                "S3Object": {
                    "Bucket": s3_bucket,
                    "Name": s3_key,
                }
            },
            FeatureTypes=["TABLES"],
        )

        # Process the response to extract structured table data
        tables = extract_table_data(response)
        print(f"Extracted {len(tables)} table(s)")

        # Store extracted data in DynamoDB
        record_id = str(uuid.uuid4())
        ttl_timestamp = int(time.time()) + (30 * 24 * 60 * 60)  # 30 days retention
        processed_time = datetime.datetime.now(datetime.timezone.utc).isoformat()

        table = dynamodb.Table(table_name)
        item = {
            "RecordId": record_id,
            "filename": s3_key,
            "bucket": s3_bucket,
            "document": f"s3://{s3_bucket}/{s3_key}",
            "tables_count": len(tables),
            "tables": tables,
            "tables_json": json.dumps(tables),
            "TimeToExist": ttl_timestamp,
            "processed_at": processed_time,
            "status": "COMPLETED",
        }

        table.put_item(Item=item)
        print(f"Successfully saved record {record_id} to DynamoDB table {table_name}")

        return {
            "statusCode": 200,
            "state": "success",
            "body": {
                "record_id": record_id,
                "document": f"s3://{s3_bucket}/{s3_key}",
                "tables_count": len(tables),
                "tables": tables,
                "dynamodb_table": table_name,
            },
        }

    except Exception as e:
        print(f"Error in extract_table_data: {str(e)}")
        return {
            "statusCode": 500,
            "state": "fail",
            "body": {
                "error": str(e),
                "document": f"s3://{s3_bucket}/{s3_key}" if s3_bucket and s3_key else "unknown",
            },
        }


def extract_table_data(textract_response):
    """Extracts and structures table data from Textract response."""
    tables = []
    blocks = textract_response.get("Blocks", [])
    block_map = {b["Id"]: b for b in blocks}

    for block in blocks:
        if block.get("BlockType") == "TABLE":
            # Find cells belonging specifically to THIS table
            table_cells = []
            if "Relationships" in block:
                for rel in block["Relationships"]:
                    if rel.get("Type") == "CHILD":
                        for cell_id in rel.get("Ids", []):
                            cell_block = block_map.get(cell_id)
                            if cell_block and cell_block.get("BlockType") == "CELL":
                                table_cells.append(cell_block)

            # Group cells by row index
            rows_dict = {}
            for cell in table_cells:
                row_idx = cell.get("RowIndex", 1)
                rows_dict.setdefault(row_idx, []).append(cell)

            # Sort cells within each row by column index and extract text
            table_rows = []
            for row_idx in sorted(rows_dict.keys()):
                cells_in_row = sorted(rows_dict[row_idx], key=lambda c: c.get("ColumnIndex", 0))
                row_texts = []
                for cell in cells_in_row:
                    cell_text_parts = []
                    if "Relationships" in cell:
                        for rel in cell["Relationships"]:
                            if rel.get("Type") == "CHILD":
                                for word_id in rel.get("Ids", []):
                                    word_block = block_map.get(word_id)
                                    if word_block and word_block.get("BlockType") == "WORD":
                                        cell_text_parts.append(word_block.get("Text", ""))
                    row_texts.append(" ".join(cell_text_parts).strip())
                table_rows.append(row_texts)

            tables.append(
                {
                    "table_id": block.get("Id"),
                    "confidence": str(round(block.get("Confidence", 0), 2)),
                    "rows": table_rows,
                }
            )

    return tables