module "efs" {
  providers = { aws = aws.default }

  source  = "terraform-aws-modules/efs/aws"
  version = "1.8.0"

  name        = "efs-${local.project_name}"
  encrypted   = true
  # kms_key_arn = module.kms.key_arn

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
  }

  tags = {
    Project = local.project_name
    Purpose = "wordpress-efs"
  }
}
