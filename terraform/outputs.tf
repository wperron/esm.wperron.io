output "state_bucket" {
  value = aws_s3_bucket.state.id
}

output "modules_bucket" {
  value = aws_s3_bucket.modules.id
}