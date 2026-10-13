terraform {
  required_version = ">= 1.6"

  required_providers {
    aws     = { source = "hashicorp/aws", version = ">= 6.0" }
    helm    = { source = "hashicorp/helm", version = "~> 2.17" }
    kubectl = { source = "alekc/kubectl", version = "~> 2.1" }
    random  = { source = "hashicorp/random", version = "~> 3.6" }
    http    = { source = "hashicorp/http", version = "~> 3.4" }
  }
}