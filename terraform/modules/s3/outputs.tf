output "bucket" {
  value = aws_s3_bucket.bucket.id
}
output "arn" {
  value = aws_s3_bucket.bucket.arn
}
output "objects" {
  value = aws_s3_object.object[*]
}
