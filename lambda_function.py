import boto3
import json

def lambda_handler(event, context):
    glue = boto3.client("glue")
    crawler_name = "sales-data-crawler-tf"
    try:
        glue.start_crawler(Name=crawler_name)
        print("Started crawler: " + crawler_name)
        return {"statusCode": 200, "body": json.dumps("Crawler started")}
    except Exception as e:
        print("Error: " + str(e))
        raise e
