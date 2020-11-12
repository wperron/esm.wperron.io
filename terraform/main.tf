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

data "aws_route53_zone" "this" {
  name = "${var.hosted_zone}."
}

data "aws_acm_certificate" "this" {
  provider    = aws.useast
  domain      = "*.${var.hosted_zone}"
  types       = ["AMAZON_ISSUED"]
  most_recent = true
}

locals {
  distro_domain = trimsuffix("deno.${data.aws_route53_zone.this.name}", ".")
}

resource "aws_route53_record" "A" {
  zone_id = data.aws_route53_zone.this.zone_id
  name    = local.distro_domain
  type    = "A"
  alias {
    name                   = aws_cloudfront_distribution.modules.domain_name
    zone_id                = aws_cloudfront_distribution.modules.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "AAAA" {
  zone_id = data.aws_route53_zone.this.zone_id
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
    acm_certificate_arn      = data.aws_acm_certificate.this.arn
    minimum_protocol_version = "TLSv1.2_2019"
    ssl_support_method       = "sni-only"
  }

  enabled             = true
  is_ipv6_enabled     = true
  aliases             = [local.distro_domain]
  price_class         = "PriceClass_100"
  default_root_object = "index.html"

  custom_error_response {
    error_caching_min_ttl = 10
    error_code            = 404
    response_code         = 200
    response_page_path    = "/index.html"
  }

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

# Cognito Config
resource "aws_cognito_identity_pool" "main" {
  identity_pool_name               = "deno_${replace(var.hosted_zone, ".", "_")}_${local.suffix}"
  allow_unauthenticated_identities = true
  tags                             = local.tags
}

resource "aws_cognito_identity_pool_roles_attachment" "main" {
  identity_pool_id = aws_cognito_identity_pool.main.id
  roles = {
    "authenticated"   = aws_iam_role.auth.arn
    "unauthenticated" = aws_iam_role.unauth.arn
  }
}

data "aws_iam_policy_document" "unauth" {
  statement {
    actions = [
      "mobileanalytics:PutEvents",
      "cognito-sync:*",
    ]
    resources = ["*"]
  }

  statement {
    actions = [
      "s3:ListBucket",
      "s3:GetObject",
    ]
    resources = [aws_s3_bucket.modules.arn]
  }
}

data "aws_iam_policy_document" "cognito_identity_unauth" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = ["cognito-identity.amazonaws.com"]
    }

    condition {
      test     = "ForAnyValue:StringLike"
      variable = "cognito-identity.amazonaws.com:amr"
      values   = ["unauthenticated"]
    }

    condition {
      test     = "StringEquals"
      variable = "cognito-identity.amazonaws.com:aud"
      values   = [aws_cognito_identity_pool.main.id]
    }
  }
}

data "aws_iam_policy_document" "cognito_identity_auth" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = ["cognito-identity.amazonaws.com"]
    }

    condition {
      test     = "ForAnyValue:StringLike"
      variable = "cognito-identity.amazonaws.com:amr"
      values   = ["authenticated"]
    }

    condition {
      test     = "StringEquals"
      variable = "cognito-identity.amazonaws.com:aud"
      values   = [aws_cognito_identity_pool.main.id]
    }
  }
}

resource "aws_iam_role" "unauth" {
  name               = "deno-${replace(var.hosted_zone, ".", "-")}-unauth-${local.suffix}"
  assume_role_policy = data.aws_iam_policy_document.cognito_identity_unauth.json
}

resource "aws_iam_role" "auth" {
  name               = "deno-${replace(var.hosted_zone, ".", "-")}-auth-${local.suffix}"
  assume_role_policy = data.aws_iam_policy_document.cognito_identity_auth.json
}

resource "aws_iam_role_policy" "unauth" {
  role   = aws_iam_role.unauth.name
  policy = data.aws_iam_policy_document.unauth.json
}