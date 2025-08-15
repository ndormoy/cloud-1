# --- Point d'entrée principal ---
output "website_url" {
  description = "URL publique du site web via CloudFront. C'est l'adresse à visiter."
  value       = "https://${module.cdn.cloudfront_distribution_domain_name}"
}

# --- Variables pour le script user_data ---
output "efs_filesystem_id" {
  description = "[user_data] ID du système de fichiers EFS pour le montage."
  value       = module.efs.id
}

output "aurora_cluster_endpoint" {
  description = "[user_data] Endpoint de connexion pour le cluster Aurora."
  value       = module.aurora.cluster_endpoint
}

output "database_name" {
  description = "[user_data] Nom de la base de données WordPress."
  value       = var.db_name
}

output "database_master_username" {
  description = "[user_data] Nom de l'utilisateur principal de la base de données."
  value       = var.db_master_username
}

output "db_password_secret_arn" {
  description = "[user_data] ARN du secret contenant le mot de passe de la base de données."
  value       = module.aurora.cluster_master_user_secret[0].secret_arn
}

output "wp_salts_ssm_parameter_name" {
  description = "[user_data] Nom du paramètre SSM pour les 'salts' WordPress."
  value       = var.wp_salts_ssm_parameter_name
}

output "elasticache_memcached_endpoint" {
  description = "[user_data] Endpoint de connexion pour le cluster ElastiCache (Memcached)."
  value       = module.elasticache.cluster_address
}

# --- Informations de débogage supplémentaires ---
output "alb_dns_name" {
  description = "Nom DNS du Load Balancer (utile pour tester sans CloudFront)."
  value       = module.alb.dns_name
}

output "web_server_security_group_id" {
  description = "ID du groupe de sécurité des serveurs web (EC2)."
  value       = module.sg_web.security_group_id
}

output "database_security_group_id" {
  description = "ID du groupe de sécurité de la base de données (Aurora)."
  value       = module.sg_db.security_group_id
}
