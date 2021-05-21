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
}

resource "aws_iam_policy" "deno_access" {
  name   = "deno.${var.hosted_zone}-${local.suffix}"
  policy = data.aws_iam_policy_document.deno_access.json
}

data "aws_vpc" "default" {
  default = true
}

data "aws_ami" "vector" {
  most_recent = true

  filter {
    name   = "name"
    values = ["vector-custom-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = [data.aws_caller_identity.this.id]
}

resource "aws_security_group" "ssh" {
  name        = "ssh-${local.suffix}"
  description = "Inbound SSH access"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "ingress from ssh"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = local.tags
}

resource "aws_security_group" "outbound" {
  name        = "outbound-${local.suffix}"
  description = "Allow all outbound traffic"
  vpc_id      = data.aws_vpc.default.id

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = local.tags
}

resource "aws_instance" "vector" {
  ami           = data.aws_ami.vector.id
  instance_type = "t3a.micro"
  user_data     = filebase64("./vector/startup.sh")
  security_groups = [
    aws_security_group.ssh.name,
    aws_security_group.outbound.name,
  ]

  tags = local.tags
}
