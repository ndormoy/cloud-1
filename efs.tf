# module "efs" {
#   providers = {
#     aws = aws.default
#   }

#   source  = "terraform-aws-modules/efs/aws"
#   version = "1.8.0"

#   name           = "example"
#   creation_token = "example-token"
#   encrypted      = true
#   kms_key_arn    = module.kms.key_arn

#   lifecycle_policy = {
#     transition_to_ia = "AFTER_30_DAYS"
#   }

#   attach_policy                      = true
#   bypass_policy_lockout_safety_check = false
# policy_statements = [
#   {
#     sid     = "Example"
#     actions = ["elasticfilesystem:ClientMount"]
#     principals = [
#       {
#         type        = "AWS"
#         identifiers = ["arn:aws:iam::111122223333:role/EfsReadOnly"]
#       }
#     ]
#   }
# ]

#   mount_targets = {
#     for k, v in module.vpc.private_subnets : k => { subnet_id = v }
#   }

#   security_group_description = "Example EFS security group"
#   security_group_vpc_id      = "vpc-1234556abcdef"
#   security_group_rules = {
#     vpc = {
#       description = "NFS ingress from VPC private subnets"
#       cidr_blocks = ["10.99.3.0/24", "10.99.4.0/24"]
#     }
#   }

#   access_points = {
#     posix_example = {
#       name = "posix-example"
#       posix_user = {
#         gid            = 1001
#         uid            = 1001
#         secondary_gids = [1002]
#       }

#       tags = {
#         Additionl = "yes"
#       }
#     }
#     root_example = {
#       root_directory = {
#         path = "/example"
#         creation_info = {
#           owner_gid   = 1001
#           owner_uid   = 1001
#           permissions = "755"
#         }
#       }
#     }
#   }
# }














module "efs" {
  providers = { aws = aws.default }

  source  = "terraform-aws-modules/efs/aws"
  version = "1.8.0"

  name        = "efs-${local.project_name}"
  encrypted   = true
  kms_key_arn = module.kms.key_arn

  lifecycle_policy = {
    transition_to_ia = "AFTER_30_DAYS"
  }

  attach_policy                      = true
  bypass_policy_lockout_safety_check = false

  mount_targets = {
    for idx, az in local.azs :
    az => {
      subnet_id = module.vpc.private_subnets[idx]
    }
  }

  security_group_description = "EFS security group for ${local.project_name}"
  security_group_vpc_id      = module.vpc.vpc_id

  security_group_rules = {
    web_nfs = {
      rule                     = "nfs-tcp"
      description              = "Allow NFS (2049/tcp) from web tier"
      source_security_group_id = module.sg_web.security_group_id
    }
    # egress_none = {
    #   type        = "egress"
    #   from_port   = 0
    #   to_port     = 0
    #   protocol    = "-1"
    #   cidr_blocks = []
    #   description = "No outbound traffic from EFS SG"
    # }
  }

  tags = {
    Project = local.project_name
    Purpose = "wordpress-efs"
  }
}
