resource "random_uuid" "this" {}

locals {
  suffix = substr(random_uuid.this.result, 0, 8)
  tags = {
    "${var.hosted_zone}/site"     = "deno.${var.hosted_zone}"
    "${var.hosted_zone}/instance" = local.suffix
    "${var.hosted_zone}/env"      = var.env
  }
}

# Terraform State Management
resource "aws_s3_bucket" "state" {
  bucket = "deno.${var.hosted_zone}-state-${local.suffix}"
  acl    = "private"
  tags   = local.tags
  versioning {
    enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Module storage
resource "aws_s3_bucket" "modules" {
  bucket = "deno.${var.hosted_zone}"
  acl    = "private"
  tags   = local.tags
  versioning {
    enabled = true
  }

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "AES256"
      }
    }
  }

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "HEAD"]
    allowed_origins = ["*"]
    expose_headers  = ["ETag", "X-TypeScript-Types"]
    max_age_seconds = 3000
  }
}

resource "aws_s3_bucket_public_access_block" "modules" {
  bucket                  = aws_s3_bucket.modules.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

data "aws_iam_policy_document" "deno_access" {
  statement {
    actions = [
      "s3:GetObject",
      "s3:ListBucket",
    ]
    resources = [
      aws_s3_bucket.modules.arn,
      "${aws_s3_bucket.modules.arn}/*",
    ]
  }

  statement {
    actions = [
      "firehose:PutRecord",
    ]
    resources = [
      aws_kinesis_firehose_delivery_stream.test_stream.arn,
    ]
  }
}

resource "aws_iam_policy" "deno_access" {
  name   = "deno.${var.hosted_zone}-${local.suffix}"
  policy = data.aws_iam_policy_document.deno_access.json
}

resource "aws_s3_bucket" "firehose_backup" {
  bucket = "firehose-backup-${local.suffix}"
  acl    = "private"
  tags   = local.tags
  versioning {
    enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "firehose_backup" {
  bucket                  = aws_s3_bucket.firehose_backup.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

data "aws_iam_policy_document" "firehose" {
  statement {
    actions = [
      "s3:PutObject",
    ]
    resources = [
      aws_s3_bucket.firehose_backup.arn,
    ]
  }
}

data "aws_iam_policy_document" "firehose_assume" {
  statement {
    actions = [
      "sts:AssumeRole",
    ]
    principals {
      type        = "Service"
      identifiers = ["firehose.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "firehose" {
  name               = "esm.wperron.io-logging-${local.suffix}"
  assume_role_policy = data.aws_iam_policy_document.firehose_assume.json
}

resource "aws_iam_role_policy" "firehose" {
  role   = aws_iam_role.firehose.name
  policy = data.aws_iam_policy_document.firehose.json
}

resource "aws_kinesis_firehose_delivery_stream" "test_stream" {
  name        = "esm.wperron.io-logs-${local.suffix}"
  destination = "http_endpoint"

  s3_configuration {
    role_arn           = aws_iam_role.firehose.arn
    bucket_arn         = aws_s3_bucket.firehose_backup.arn
    buffer_size        = 10
    buffer_interval    = 400
    compression_format = "GZIP"
  }

  http_endpoint_configuration {
    url                = "https://aws-api.newrelic.com/firehose/v1"
    name               = "New Relic"
    access_key         = var.new_relic_api_key
    buffering_size     = 15
    buffering_interval = 600
    role_arn           = aws_iam_role.firehose.arn
    s3_backup_mode     = "AllData"
  }
}
