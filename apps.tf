resource "random_password" "jwt" {
  length  = 48
  special = false
}

resource "kubectl_manifest" "ns_app" {
  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "Namespace"
    metadata   = { name = "animethreads" }
  })

  depends_on = [module.eks]
}

resource "kubectl_manifest" "postgres_svc" {
  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "Service"
    metadata   = { name = "postgres", namespace = "animethreads" }
    spec       = { type = "ExternalName", externalName = aws_db_instance.main.address }
  })

  depends_on = [kubectl_manifest.ns_app]
}

resource "kubectl_manifest" "app_secret" {
  sensitive_fields = ["stringData"]

  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "Secret"
    metadata   = { name = "animethreads-secrets", namespace = "animethreads" }
    type       = "Opaque"
    stringData = merge(
      {
        JWT_SECRET        = random_password.jwt.result
        POSTGRES_PASSWORD = random_password.db.result
      },
      {
        for s in local.schemas :
        "DATABASE_URL_${upper(s)}" => "postgresql://postgres:${random_password.db.result}@postgres:5432/animethreads?schema=${s}"
      }
    )
  })

  depends_on = [kubectl_manifest.ns_app]
}