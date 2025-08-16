
# ---------------------------------------------------------------------------- #
#                                IAM                                           #
# ---------------------------------------------------------------------------- #


resource "aws_iam_role" "ssm_role" {

  provider = aws.default

  name = "ec2-ssm-role-${local.project_name}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect    = "Allow",
        Principal = { Service = "ec2.amazonaws.com" },
        Action    = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ssm_core" {

  provider = aws.default

  role = aws_iam_role.ssm_role.name

  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}


resource "aws_iam_instance_profile" "ssm_instance_profile" {

  provider = aws.default

  name = "ec2-ssm-instance-profile-${local.project_name}"
  role = aws_iam_role.ssm_role.name
}

resource "aws_iam_policy" "read_secrets_policy" {

  provider = aws.default

  name        = "read-db-secret-policy-${local.project_name}"
  description = "Allow reading the database password from Secrets Manager"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "secretsmanager:GetSecretValue",
        ]
        Effect   = "Allow"
        Resource = module.aurora.cluster_master_user_secret[0].secret_arn
      },
      {
        Action   = ["ssm:GetParameter"]
        Effect   = "Allow"
        Resource = aws_ssm_parameter.wp_salts.arn
      },
      {
        Action   = ["secretsmanager:GetSecretValue"]
        Effect   = "Allow"
        Resource = aws_secretsmanager_secret.wp_admin_password.arn
      }
    ]
  })
}


resource "aws_iam_role_policy_attachment" "ec2_app_read_secrets_attach" {
  provider = aws.default

  role       = aws_iam_role.ssm_role.name
  policy_arn = aws_iam_policy.read_secrets_policy.arn
}
