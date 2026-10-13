variable "region" {
  type        = string
  description = "AWS region"
}

variable "project" {
  type    = string
  default = "animethreads"
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "kubernetes_version" {
  type    = string
  default = "1.34"
}

variable "instance_type" {
  type    = string
  default = "c7i-flex.large"
}

variable "karpenter_version" {
  type        = string
  default     = "1.12.0"
  description = "Karpenter Helm chart version"
}

variable "my_ip_cidr" {
  type        = string
  description = "Your public IP as x.x.x.x/32, the only address allowed to reach the EKS API"
}

variable "repo_url" {
  type    = string
  default = "https://github.com/HamzaMaLik121/DevOps-Entire-project-A_Z.git"
}

variable "bootstrap_apps" {
  type        = bool
  default     = false
  description = "Create the ArgoCD Applications (turn on after values-eks.yaml is pushed)"
}

locals {
  name         = var.project
  cluster_name = "${var.project}-eks"
  azs          = ["${var.region}a", "${var.region}b"]

  public_cidrs  = ["10.0.0.0/24", "10.0.1.0/24"]
  private_cidrs = ["10.0.16.0/20", "10.0.32.0/20"]
  db_cidrs      = ["10.0.100.0/24", "10.0.101.0/24"]

  schemas = ["auth", "product", "order", "payment", "inventory"]
}