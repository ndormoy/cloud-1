# ---------------------------------------------------------------------------- #
#                                VPC                                           #
# ---------------------------------------------------------------------------- #

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "subnet_size_private" {
  type    = number
  default = 24
}

variable "subnet_size_public" {
  type    = number
  default = 24
}

variable "az_count" {
  type    = number
  default = 2
}

# ---------------------------------------------------------------------------- #
#                                AURORA                                        #
# ---------------------------------------------------------------------------- #

variable "aurora_db" {
  type    = string
  default = "aurora-db"
}

variable "aurora_cluster_name" {
  type    = string
  default = "aurora-cluster"
}

variable "aurora_engine_version" {
  type    = string
  default = "8.0"
}

variable "db_name" {
  type    = string
  default = "wordpressdb"
}

variable "db_master_username" {
  type    = string
  default = "admin"
}

# ---------------------------------------------------------------------------- #
#                                ELASTICACHE                                   #
# ---------------------------------------------------------------------------- #  

variable "elasticache_cluster_id" {
  type    = string
  default = "cluster"
}

variable "elasticache_node_type" {
  type    = string
  default = "cache.t4g.small"
}

variable "elasticache_name" {
  type    = string
  default = "elasticache"
}

# ---------------------------------------------------------------------------- #
#                                ASG                                           #
# ---------------------------------------------------------------------------- #

variable "ami_id" {
  description = "AMI ID for the EC2 instances"
  type        = string
  default     = "ami-0a8e052d7bc893af0"
}

variable "asg_instance_type" {
  type    = string
  default = "t3.micro"
}

variable "asg_desired_capacity" {
  type    = number
  default = 2
}

variable "asg_min_size" {
  type    = number
  default = 2
}

variable "asg_max_size" {
  type    = number
  default = 4
}
