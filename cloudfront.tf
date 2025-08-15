module "cdn" {
  providers = {
    aws = aws.default
  }

  source  = "terraform-aws-modules/cloudfront/aws"
  version = "5.0.0"

  comment             = "CDN for ${local.project_name}"
  enabled             = true
  is_ipv6_enabled     = true
  price_class         = "PriceClass_All"
  retain_on_delete    = false
  wait_for_deployment = false

  create_origin_access_identity = false
  origin_access_identities      = {}

  origin = {
    alb = {
      domain_name = module.alb.dns_name

      custom_origin_config = {
        http_port              = 80
        https_port             = 443
        origin_protocol_policy = "http-only"
        origin_ssl_protocols   = ["TLSv1.2"]
      }
    }
  }

  default_cache_behavior = {
    target_origin_id       = "alb"
    viewer_protocol_policy = "redirect-to-https"

    allowed_methods = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods  = ["GET", "HEAD"]
    compress        = true

    query_string    = true
    cookies_forward = "all"

    default_ttl = 60
    min_ttl     = 0
    max_ttl     = 300
  }

  ordered_cache_behavior = []

  viewer_certificate = {
    cloudfront_default_certificate = true
    minimum_protocol_version       = "TLSv1.2_2021"
  }
}
