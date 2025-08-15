data "aws_caller_identity" "current" { provider = aws.default }

module "kms" {

  providers = {
    aws = aws.default
  }

  source  = "terraform-aws-modules/kms/aws"
  version = "4.0.0"

  description             = "CMK for Aurora and EFS encryption"
  enable_default_policy   = true
  enable_key_rotation     = true
  deletion_window_in_days = 7
  key_usage               = "ENCRYPT_DECRYPT"

  aliases = [
    "alias/cloud1/aurora-efs"
  ]

  key_statements = [
    {
      sid = "AllowRDSUseOfCMK"
      actions = [
        "kms:Encrypt",
        "kms:Decrypt",
        "kms:ReEncrypt*",
        "kms:GenerateDataKey*",
        "kms:CreateGrant",
        "kms:ListGrants",
        "kms:DescribeKey"
      ]
      resources = ["*"]
      principals = [
        {
          type        = "Service"
          identifiers = ["rds.amazonaws.com"]
        }
      ]
      condition = [
        {
          test     = "StringEquals"
          variable = "kms:CallerAccount"
          values   = [data.aws_caller_identity.current.account_id]
        }
      ]
    },
    {
      sid = "AllowEFSUseOfCMK"
      actions = [
        "kms:Encrypt",
        "kms:Decrypt",
        "kms:ReEncrypt*",
        "kms:GenerateDataKey*",
        "kms:CreateGrant",
        "kms:ListGrants",
        "kms:DescribeKey"
      ]
      resources = ["*"]
      principals = [
        {
          type        = "Service"
          identifiers = ["elasticfilesystem.amazonaws.com"]
        }
      ]
      condition = [
        {
          test     = "StringEquals"
          variable = "kms:CallerAccount"
          values   = [data.aws_caller_identity.current.account_id]
        }
      ]
    }
  ]

  tags = {
    Project = local.project_name
    Purpose = "data-encryption"
  }
}
