terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.70"
    }
  }

  # Optional: remote state. Create the bucket and lock table first, then
  # uncomment this block and run `terraform init -migrate-state`.
  #
  # backend "s3" {
  #   bucket         = "your-terraform-state-bucket"
  #   key            = "voting-app/eks/terraform.tfstate"
  #   region         = "us-east-1"
  #   dynamodb_table = "terraform-locks"
  #   encrypt        = true
  # }
}
