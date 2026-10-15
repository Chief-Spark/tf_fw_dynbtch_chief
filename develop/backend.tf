terraform {
  backend "s3" {
    bucket         = "dto-terraform-651706752126"
    key            = "deploy/fwdynbtch/develop/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "dto-terraform-lock-651706752126"
  }
}
