module "asg" {
  providers = {
    aws = aws.default
  }

  source  = "terraform-aws-modules/autoscaling/aws"
  version = "9.0.1"

  name = "asg-web-${local.project_name}"

  vpc_zone_identifier = module.vpc.private_subnets
  security_groups     = [module.sg_web.security_group_id]

  launch_template_name        = "lt-web-${local.project_name}"
  launch_template_description = "Launch template for web servers"

  image_id      = var.ami_id
  instance_type = var.asg_instance_type

  iam_instance_profile_name = aws_iam_instance_profile.ssm_instance_profile.name

  user_data = base64encode(templatefile("${path.module}/userdata/init_ec2.sh.tpl", {
    efs_fs_id              = module.efs.id
    aurora_writer_endpoint = module.aurora.cluster_endpoint
    aurora_db_name         = var.db_name
    aurora_db_user         = var.db_master_username
    db_password_secret_arn = module.aurora.cluster_master_user_secret[0].secret_arn
    memcached_host         = module.elasticache.cluster_address
    memcached_port         = 11211
    wp_home                = "https://${module.cdn.cloudfront_distribution_domain_name}"
    wp_siteurl             = "https://${module.cdn.cloudfront_distribution_domain_name}"
    wp_salts_param_name    = var.wp_salts_ssm_parameter_name

    docker_compose_content = file("${path.module}/templates/docker-compose.yaml.tpl")
    nginx_conf_content     = file("${path.module}/templates/nginx.conf.tpl")
    wp_init_script_content = file("${path.module}/templates/10-wp-config.sh.tpl")
  }))

  traffic_source_attachments = {
    alb = {
      traffic_source_identifier = module.alb.target_groups["asg_web_targets"].arn
      traffic_source_type       = "elbv2"
    }
  }

  desired_capacity = var.asg_desired_capacity
  min_size         = var.asg_min_size
  max_size         = var.asg_max_size

  instance_refresh = {
    strategy = "Rolling"
    triggers = ["launch_template"]
    preferences = {
      min_healthy_percentage = 50
    }
  }

  depends_on = [
    module.aurora,
    module.elasticache,
    module.efs,
    module.alb
  ]
}

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
          # "secretsmanager:DescribeSecret"
        ]
        Effect   = "Allow"
        Resource = module.aurora.cluster_master_user_secret[0].secret_arn
      },
      {
        Action   = ["ssm:GetParameter"]
        Effect   = "Allow"
        Resource = aws_ssm_parameter.wp_salts.arn
      }
    ]
  })
}


resource "aws_iam_role_policy_attachment" "ec2_app_read_secrets_attach" {
  provider = aws.default

  role       = aws_iam_role.ssm_role.name
  policy_arn = aws_iam_policy.read_secrets_policy.arn
}
