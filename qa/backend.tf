terraform {
  backend "s3" {
    bucket         = "dto-terraform-124355679563"
    key            = "deploy/fwdynbtch/qa/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "dto-terraform-lock-124355679563"
  }
}
