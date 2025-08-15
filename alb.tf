module "alb" {
  providers = {
    aws = aws.default
  }

  source  = "terraform-aws-modules/alb/aws"
  version = "9.17.0"

  name    = "alb-${local.project_name}"
  vpc_id  = module.vpc.vpc_id
  subnets = module.vpc.public_subnets

  security_group_ingress_rules = {
    all_http = {
      from_port   = 80
      to_port     = 80
      ip_protocol = "tcp"
      description = "HTTP web traffic"
      cidr_ipv4   = "0.0.0.0/0"
    }
  }

  security_group_egress_rules = {
    all = {
      ip_protocol = "-1"
      cidr_ipv4   = var.vpc_cidr
    }
  }

  listeners = {
    http_forward = {
      port     = 80
      protocol = "HTTP"
      forward = {
        target_group_key = "asg_web_targets"
      }
    }
  }

  target_groups = {
    asg_web_targets = {
      name_prefix       = "web"
      target_type       = "instance"
      protocol          = "HTTP"
      port              = 80
      create_attachment = false
    }
  }
}
