# Inside all folder (except the one not linked to this provider file) you will find that resource definitons
# are always Specifying the provider alias to use. And no default provider is defined. This is done to ensure
# that all reasource are correctly created in the account they need to be as well as giving you direct insight
# on where the resource is
#
#
# Define the AWS provider with an alias 'principal'.
provider "aws" {

  # Specify the region for AWS resources.
  # The region is fetched from local variables, ensuring consistency and easy updates.
  region = local.aws_region
  alias  = "default"

  # Define default tags to be applied to all resources managed by this provider.
  default_tags {
    tags = {
      ProjetName = "cloud-1",
    }
  }
}

provider "aws" {
  region = "us-east-1"
  alias  = "us-east-1"
}


terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.9.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "3.7.2"
    }
  }
}
