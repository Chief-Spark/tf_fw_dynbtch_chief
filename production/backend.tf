terraform {
  backend "s3" {
    bucket         = "dto-terraform-324037294240"
    key            = "deploy/fwdynbtch/prod/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "dto-terraform-lock-324037294240"
  }
}
