# ---------------------------------------------------------------------------- #
#                                SUBNETS                                       #
# ---------------------------------------------------------------------------- #

data "aws_availability_zones" "available" { provider = aws.default }

locals {
  azs        = slice(data.aws_availability_zones.available.names, 0, var.az_count)
  azs_length = length(local.azs)
  cidr       = var.vpc_cidr

  subnets_mask_newbit = {
    private = var.subnet_size_private - tonumber(split("/", var.vpc_cidr)[1] == "" ? 16 : tonumber(split("/", var.vpc_cidr)[1]))
    public  = var.subnet_size_public - tonumber(split("/", var.vpc_cidr)[1] == "" ? 16 : tonumber(split("/", var.vpc_cidr)[1]))
  }

  private_subnet_offset  = 0
  public_subnet_offset   = local.azs_length
  database_subnet_offset = local.azs_length * 2
}

locals {
  private_subnets = [
    for idx, az in local.azs :
    cidrsubnet(local.cidr, local.subnets_mask_newbit.private, idx + local.private_subnet_offset)
  ]
  public_subnets = [
    for idx, az in local.azs :
    cidrsubnet(local.cidr, local.subnets_mask_newbit.public, idx + local.public_subnet_offset)
  ]
  database_subnets = [
    for idx, az in local.azs :
    cidrsubnet(local.cidr, 8, idx + local.database_subnet_offset)
  ]
}


# ---------------------------------------------------------------------------- #
#                                VPC                                           #
# ---------------------------------------------------------------------------- #

module "vpc" {

  providers = {
    aws = aws.default
  }

  source  = "terraform-aws-modules/vpc/aws"
  version = "6.0.1"

  name = "vpc-${local.project_name}"
  cidr = local.cidr
  azs  = local.azs

  private_subnets  = local.private_subnets
  public_subnets   = local.public_subnets
  database_subnets = local.database_subnets

  enable_nat_gateway = true
  single_nat_gateway = true
  create_igw         = true
}
