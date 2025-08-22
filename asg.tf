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
    efs_fs_id = module.efs.id

    aurora_writer_endpoint = module.aurora.cluster_endpoint
    aurora_db_name         = var.db_name
    aurora_db_user         = var.db_master_username

    db_password_secret_arn = module.aurora.cluster_master_user_secret[0].secret_arn
    memcached_host         = module.elasticache.cluster_address
    memcached_port         = 11211

    wp_home                      = "https://${module.cdn.cloudfront_distribution_domain_name}"
    wp_siteurl                   = "https://${module.cdn.cloudfront_distribution_domain_name}"
    wp_salts_param_name          = var.wp_salts_ssm_parameter_name
    wp_admin_user                = var.wp_admin_user
    wp_admin_email               = var.wp_admin_email
    wp_admin_password_secret_arn = aws_secretsmanager_secret.wp_admin_password.arn

    docker_compose_content = file("${path.module}/templates/docker-compose.yaml.tpl")
    nginx_conf_content     = file("${path.module}/templates/nginx.conf.tpl")
    dockerfile_content     = file("${path.module}/templates/Dockerfile")
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

  depends_on = [
    module.aurora,
    module.elasticache,
    module.efs,
    module.alb
  ]
}
