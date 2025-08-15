# ---------------------------------------------------------------------------- #
#                                WEB                                           #
# ---------------------------------------------------------------------------- #
module "sg_web" {
  providers = {
    aws = aws.default
  }

  source  = "terraform-aws-modules/security-group/aws"
  version = "5.3.0"

  name        = "web-sg-${local.project_name}"
  description = "Allow HTTP/HTTPS traffic"
  vpc_id      = module.vpc.vpc_id

  ingress_with_source_security_group_id = [
    {
      from_port                = 80
      to_port                  = 80
      protocol                 = "tcp"
      source_security_group_id = module.alb.security_group_id
      description              = "HTTP from ALB"
    }
  ]

  egress_with_cidr_blocks = [
    { from_port = 0, to_port = 0, protocol = "-1", cidr_blocks = "0.0.0.0/0" }
  ]
}

# ---------------------------------------------------------------------------- #
#                                AURORA + ELASTICACHE                          #
# ---------------------------------------------------------------------------- #

module "sg_db" {
  providers = { aws = aws.default }
  source    = "terraform-aws-modules/security-group/aws"
  version   = "5.3.0"

  name        = "db-sg-${local.project_name}"
  description = "Allow MySQL from web tier"
  vpc_id      = module.vpc.vpc_id

  ingress_with_source_security_group_id = [
    {
      rule                     = "mysql-tcp"
      source_security_group_id = module.sg_web.security_group_id
      description              = "MySQL from web"
    }
  ]

  egress_with_cidr_blocks = []
}

# # ---------------------------------------------------------------------------- #
# #                                EFS                                           #
# # ---------------------------------------------------------------------------- #

# module "sg_efs" {

#   providers = {
#     aws = aws.default
#   }

#   source  = "terraform-aws-modules/security-group/aws"
#   version = "5.3.0"

#   name        = "efs-sg-${local.project_name}"
#   description = "Allow NFS traffic from web servers"
#   vpc_id      = module.vpc.vpc_id

#   ingress_with_source_security_group_id = [
#     { rule = "nfs-tcp", source_security_group_id = module.sg_web.security_group_id },
#   ]
# }
