# Buckets
resource "aws_s3_bucket" "raw-data" {
  bucket = "pipeline-raw-data-tf-2026"

  tags = {
    Name    = "Pipeline Raw Data"
    project = "serverless Data Pipeline"
  }
}

resource "aws_s3_bucket" "results" {
  bucket = "pipeline-results-tf-2026"

  tags = {
    Name    = "Athena Query Results"
    project = "serverless Data Pipeline"
  }
}

# IAM Roles
#lambda Role
data "aws_iam_policy_document" "lambda_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda_role" {
  name               = "LambdaGlueRole-tf"
  assume_role_policy = data.aws_iam_policy_document.lambda_trust.json
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "lambda_glue" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSGlueConsoleFullAccess"
}

#Glue Role
data "aws_iam_policy_document" "glue_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["glue.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "glue_role" {
  name               = "GlueCrawlerRole-tf"
  assume_role_policy = data.aws_iam_policy_document.glue_trust.json
}

resource "aws_iam_role_policy_attachment" "glue_service" {
  role       = aws_iam_role.glue_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

resource "aws_iam_role_policy_attachment" "glue_s3" {
  role       = aws_iam_role.glue_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
}

#Lambda Function
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/lambda.zip"

  source {
    content  = file("${path.module}/lambda_function.py")
    filename = "lambda_function.py"
  }
}

# The Lambda function itself
resource "aws_lambda_function" "start_crawler" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "StartGlueCrawler-tf"
  role             = aws_iam_role.lambda_role.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.12"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  tags = {
    Project = "Serverless Data Pipeline"
  }
}

#Glue Database and Crawler
resource "aws_glue_catalog_database" "pipeline_db" {
  name = "sales-pipeline-db-tf"
}

resource "aws_glue_crawler" "sales_crawler" {
  name = "sales-data-crawler-tf"

  database_name = aws_glue_catalog_database.pipeline_db.name
  role          = aws_iam_role.glue_role.arn

  s3_target {
    path = "s3://${aws_s3_bucket.raw-data.bucket}/"
  }

  tags = {
    Project = "Serverless Data Pipeline"
  }
}

#Trigger
resource "aws_lambda_permission" "allow_s3" {
  statement_id  = "AllowExecutionFromS3"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.start_crawler.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.raw-data.arn
}

resource "aws_s3_bucket_notification" "pipeline_trigger" {
  bucket = aws_s3_bucket.raw-data.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.start_crawler.arn
    events              = ["s3:ObjectCreated:*"]
  }

  depends_on = [aws_lambda_permission.allow_s3]
}


