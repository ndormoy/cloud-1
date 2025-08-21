# ---------------------------------------------------------------------------- #
#                                WP SALTS                                      #
# ---------------------------------------------------------------------------- #

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

  depends_on = [aws_iam_role.ssm_role]
}

# ---------------------------------------------------------------------------- #
#                                WP PASSWORD                                   #
# ---------------------------------------------------------------------------- #

resource "random_password" "wp_admin" {
  length           = 20
  special          = true
  override_special = "!#$%&"
}

resource "aws_secretsmanager_secret" "wp_admin_password" {
  provider = aws.default

  name        = "wp-admin-password-${local.project_name}"
  description = "WordPress admin password"

  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "wp_admin_password_v1" {
  provider = aws.default

  secret_id     = aws_secretsmanager_secret.wp_admin_password.id
  secret_string = random_password.wp_admin.result
}
