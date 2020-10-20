resource "random_uuid" "this" {}

locals {
  suffix = substr(random_uuid.this.result, 0, 8)
  tags = {
    "wperron.io/site"     = "deno.wperron.io"
    "wperron.io/instance" = local.suffix
    "wperron.io/env"      = var.env
  }
}

# Terraform State Management
resource "aws_s3_bucket" "state" {
  bucket = "deno.wperron.io-state-${local.suffix}"
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
  bucket = "deno.wperron.io"
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

data "aws_iam_policy_document" "cloudfront_access" {
  statement {
    actions = [
      "s3:GetObject",
      "s3:ListBucket",
    ]
    resources = [
      aws_s3_bucket.modules.arn,
      "${aws_s3_bucket.modules.arn}/*",
    ]
    principals {
      type        = "AWS"
      identifiers = [aws_cloudfront_origin_access_identity.modules_origin_access_identity.iam_arn]
    }
  }
}

resource "aws_s3_bucket_policy" "modules_origin_access_identity" {
  bucket = aws_s3_bucket.modules.id
  policy = data.aws_iam_policy_document.cloudfront_access.json
}

# CDN configurations
resource "aws_cloudfront_origin_access_identity" "modules_origin_access_identity" {
  comment = "Allows access to the modules bucket from the modules distribution."
}

data "aws_route53_zone" "wperron_io" {
  name = "wperron.io."
}

data "aws_acm_certificate" "wildcard_wperron_io" {
  provider    = aws.useast
  domain      = "*.wperron.io"
  types       = ["AMAZON_ISSUED"]
  most_recent = true
}

locals {
  distro_domain = trimsuffix("deno.${data.aws_route53_zone.wperron_io.name}", ".")
}

resource "aws_route53_record" "A_deno_wperron_io" {
  zone_id = data.aws_route53_zone.wperron_io.zone_id
  name    = local.distro_domain
  type    = "A"
  alias {
    name                   = aws_cloudfront_distribution.modules.domain_name
    zone_id                = aws_cloudfront_distribution.modules.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "AAAA_deno_wperron_io" {
  zone_id = data.aws_route53_zone.wperron_io.zone_id
  name    = local.distro_domain
  type    = "AAAA"
  alias {
    name                   = aws_cloudfront_distribution.modules.domain_name
    zone_id                = aws_cloudfront_distribution.modules.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_cloudfront_distribution" "modules" {
  origin {
    domain_name = aws_s3_bucket.modules.bucket_regional_domain_name
    origin_id   = "S3-${aws_s3_bucket.modules.id}"

    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.modules_origin_access_identity.cloudfront_access_identity_path
    }
  }

  viewer_certificate {
    acm_certificate_arn      = data.aws_acm_certificate.wildcard_wperron_io.arn
    minimum_protocol_version = "TLSv1.2_2019"
    ssl_support_method       = "sni-only"
  }

  enabled             = true
  is_ipv6_enabled     = true
  aliases             = [local.distro_domain]
  price_class         = "PriceClass_100"
  default_root_object = "index.html"

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3-${aws_s3_bucket.modules.id}"

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "allow-all"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  tags = local.tags
}