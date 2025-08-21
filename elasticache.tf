module "elasticache" {
  providers = {
    aws = aws.default
  }

  source  = "terraform-aws-modules/elasticache/aws"
  version = "1.7.0"

  cluster_id               = "${var.elasticache_cluster_id}-${local.project_name}"
  create_cluster           = true
  create_replication_group = false

  engine         = "memcached"
  engine_version = "1.6.17"
  node_type      = var.elasticache_node_type

  num_cache_nodes = 2
  az_mode         = "cross-az"

  maintenance_window = "sun:05:00-sun:09:00"
  apply_immediately  = true

  vpc_id = module.vpc.vpc_id

  security_group_rules = {
    web_memcached = {
      description                  = "Allow Memcached (11211/tcp) from web tier"
      referenced_security_group_id = module.sg_web.security_group_id
      from_port                    = 11211
      to_port                      = 11211
      protocol                     = "tcp"
    }
  }

  subnet_group_name        = "${var.elasticache_name}-${local.project_name}"
  subnet_group_description = "${title("${var.elasticache_name}-${local.project_name}")} subnet group"
  subnet_ids               = module.vpc.private_subnets

  create_parameter_group      = true
  parameter_group_name        = "${var.elasticache_name}-${local.project_name}"
  parameter_group_family      = "memcached1.6"
  parameter_group_description = "${title("${var.elasticache_name}-${local.project_name}")} parameter group"
  parameters = [
    {
      name  = "idle_timeout"
      value = 60
    }
  ]

  tags = {
    Project = local.project_name
    Purpose = "wordpress-memcached"
  }
}
