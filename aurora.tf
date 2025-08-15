# module "aurora" {
#   providers = {
#     aws = aws.default
#   }

#   source  = "terraform-aws-modules/rds-aurora/aws"
#   version = "~> 9.15.0"

#   name = "${var.aurora_cluster_name}-${local.project_name}"

#   engine         = "aurora-mysql"
#   engine_version = var.aurora_engine_version
#   engine_mode    = "provisioned"

#   instances = {
#     instance1 = {
#       instance_class = "db.t3.small"
#     }
#     instance2 = {
#       instance_class = "db.t3.small"
#     }
#   }

#   # security_group_rules = {
#   #   vpc_ingress = {
#   #     cidr_blocks = module.vpc.private_subnets_cidr_blocks
#   #   }
#   # }

#   availability_zones = local.azs

#   database_name               = var.db_name
#   master_username             = var.db_master_username
#   manage_master_user_password = true

#   # create_security_group = true
#   create_security_group  = false
#   vpc_security_group_ids = [module.sg_db.security_group_id]


#   storage_encrypted = true
#   kms_key_id        = module.kms.key_arn

#   # backup_retention_period = 7

#   auto_minor_version_upgrade = true

#   deletion_protection = false
# }











# module "aurora" {
#   providers = {
#     aws = aws.default
#   }

#   source  = "terraform-aws-modules/rds-aurora/aws"
#   version = "~> 9.15.0"

#   name = "${var.aurora_cluster_name}-${local.project_name}"

#   engine         = "aurora-mysql"
#   engine_version = var.aurora_engine_version
#   engine_mode    = "provisioned"

#   instances = {
#     instance1 = {
#       instance_class = "db.t3.small"
#     }
#     instance2 = {
#       instance_class = "db.t3.small"
#     }
#   }



#   availability_zones = local.azs

#   database_name               = var.db_name
#   master_username             = var.db_master_username
#   manage_master_user_password = true

#   create_security_group  = false
#   vpc_security_group_ids = [module.sg_db.security_group_id]


#   storage_encrypted = true
#   kms_key_id        = module.kms.key_arn

#   auto_minor_version_upgrade = true

#   deletion_protection = false
# }







module "aurora" {
  providers = {
    aws = aws.default
  }

  source  = "terraform-aws-modules/rds-aurora/aws"
  version = "~> 9.15.0"

  name = "${var.aurora_cluster_name}-${local.project_name}"

  engine         = "aurora-mysql"
  engine_version = var.aurora_engine_version
  engine_mode    = "provisioned"

  db_subnet_group_name = null
  subnets              = module.vpc.private_subnets

  instances = {
    instance1 = {
      instance_class = "db.t3.small"
    }
    instance2 = {
      instance_class = "db.t3.small"
    }
  }

  availability_zones = local.azs

  database_name               = var.db_name
  master_username             = var.db_master_username
  manage_master_user_password = true

  create_security_group  = false
  vpc_security_group_ids = [module.sg_db.security_group_id]


  storage_encrypted = true
  kms_key_id        = module.kms.key_arn

  auto_minor_version_upgrade = true

  deletion_protection = false
}
