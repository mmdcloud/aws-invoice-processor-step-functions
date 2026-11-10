import json
import os
import urllib.parse
import boto3

region = os.getenv("AWS_REGION", os.getenv("AWS_DEFAULT_REGION", "us-east-1"))
textract = boto3.client("textract", region_name=region)
s3 = boto3.client("s3", region_name=region)


def lambda_handler(event, context):
    try:
        print("Received event:", json.dumps(event, default=str))

        # Extract S3 records from either direct event or wrapped payload
        records = event.get("Records")
        if not records and "Payload" in event and isinstance(event["Payload"], dict):
            records = event["Payload"].get("Records")

        if not records or not isinstance(records, list) or len(records) == 0:
            raise ValueError(f"No valid S3 Records found in event: {event}")

        raw_bucket = records[0]["s3"]["bucket"]["name"]
        raw_key = records[0]["s3"]["object"]["key"]
        s3_bucket = urllib.parse.unquote_plus(raw_bucket)
        s3_key = urllib.parse.unquote_plus(raw_key)

        print(f"Checking object s3://{s3_bucket}/{s3_key}")
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

        tables_count = 0
        total_header_fields = 0
        table_details = []

        blocks = response.get("Blocks", [])
        block_map = {block["Id"]: block for block in blocks}

        # Find all TABLE blocks
        for block in blocks:
            if block.get("BlockType") == "TABLE":
                tables_count += 1
                header_fields_count = 0
                table_info = {
                    "table_id": block.get("Id"),
                    "confidence": block.get("Confidence", 0),
                    "header_fields": [],
                }

                # Get table relationships to find cells
                if "Relationships" in block:
                    for relationship in block["Relationships"]:
                        if relationship.get("Type") == "CHILD":
                            for cell_id in relationship.get("Ids", []):
                                cell_block = block_map.get(cell_id)
                                if cell_block and cell_block.get("BlockType") == "CELL":
                                    if cell_block.get("RowIndex") == 1:
                                        header_fields_count += 1
                                        cell_text = extract_cell_text(cell_block, block_map)
                                        table_info["header_fields"].append(
                                            {
                                                "column_index": cell_block.get("ColumnIndex", 0),
                                                "text": cell_text,
                                                "confidence": cell_block.get("Confidence", 0),
                                            }
                                        )

                table_info["header_fields_count"] = header_fields_count
                total_header_fields += header_fields_count
                table_details.append(table_info)

        result = {
            "tables_count": tables_count,
            "total_header_fields": total_header_fields,
            "table_details": table_details,
            "document": f"s3://{s3_bucket}/{s3_key}",
            "processing_status": "SUCCESS",
        }

        print(f"Sanity check completed. Found {tables_count} table(s).")
        return {
            "statusCode": 200,
            "body": result,
        }

    except Exception as e:
        print(f"Error in table_sanity_check: {str(e)}")
        return {
            "statusCode": 500,
            "body": {
                "error": f"Unexpected error: {str(e)}",
                "tables_count": 0,
                "processing_status": "FAILED",
            },
        }


def extract_cell_text(cell_block, block_map):
    """Extract text from a cell block by following its child relationships."""
    text_parts = []
    if "Relationships" in cell_block:
        for relationship in cell_block["Relationships"]:
            if relationship.get("Type") == "CHILD":
                for child_id in relationship.get("Ids", []):
                    child_block = block_map.get(child_id)
                    if child_block and child_block.get("BlockType") == "WORD":
                        text_parts.append(child_block.get("Text", ""))
    return " ".join(text_parts).strip()