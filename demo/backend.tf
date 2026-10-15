terraform {
  backend "s3" {
    bucket         = "dto-terraform-311141534073"
    key            = "deploy/fwdynbtch/demo/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "dto-terraform-lock-311141534073"
  }
}
