resource "random_password" "auth_key" {
  length  = 64
  special = false
}

resource "random_password" "secure_auth_key" {
  length  = 64
  special = false
}

resource "random_password" "logged_in_key" {
  length  = 64
  special = false
}

resource "random_password" "nonce_key" {
  length  = 64
  special = false
}

resource "random_password" "auth_salt" {
  length  = 64
  special = false
}

resource "random_password" "secure_auth_salt" {
  length  = 64
  special = false
}

resource "random_password" "logged_in_salt" {
  length  = 64
  special = false
}

resource "random_password" "nonce_salt" {
  length  = 64
  special = false
}


resource "aws_ssm_parameter" "wp_salts" {
  provider = aws.default
  name     = var.wp_salts_ssm_parameter_name
  type     = "SecureString"
  value    = <<EOT
    define('AUTH_KEY',         '${random_password.auth_key.result}');
    define('SECURE_AUTH_KEY',  '${random_password.secure_auth_key.result}');
    define('LOGGED_IN_KEY',    '${random_password.logged_in_key.result}');
    define('NONCE_KEY',        '${random_password.nonce_key.result}');
    define('AUTH_SALT',        '${random_password.auth_salt.result}');
    define('SECURE_AUTH_SALT', '${random_password.secure_auth_salt.result}');
    define('LOGGED_IN_SALT',   '${random_password.logged_in_salt.result}');
    define('NONCE_SALT',       '${random_password.nonce_salt.result}');
  EOT

  # On s'assure que le rôle IAM a le temps d'être créé avant que la policy n'essaie de l'utiliser
  # (Ceci est une dépendance implicite qui peut être rendue explicite si nécessaire)
  depends_on = [aws_iam_role.ssm_role]
}
