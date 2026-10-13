resource "helm_release" "argocd" {
  name             = "argocd"
  namespace        = "argocd"
  create_namespace = true
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  timeout          = 900

  values = [yamlencode({
    dex           = { enabled = false }
    notifications = { enabled = false }
    configs       = { params = { "server.insecure" = true } }
  })]

  depends_on = [helm_release.lbc, helm_release.metrics_server]
}

# The next two only appear after you set bootstrap_apps = true
resource "kubectl_manifest" "app_animethreads" {
  count = var.bootstrap_apps ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata   = { name = "animethreads", namespace = "argocd" }
    spec = {
      project = "default"
      source = {
        repoURL        = var.repo_url
        targetRevision = "main"
        path           = "helm/animethreads"
        helm           = { valueFiles = ["values.yaml", "values-eks.yaml"] }
      }
      destination = { server = "https://kubernetes.default.svc", namespace = "animethreads" }
      syncPolicy = {
        automated   = { prune = true, selfHeal = true }
        syncOptions = ["CreateNamespace=true"]
      }
    }
  })

  depends_on = [helm_release.argocd, kubectl_manifest.app_secret, kubectl_manifest.postgres_svc]
}

# Reuses the Application file already in git, read from GitHub so this folder can live anywhere
data "http" "kps_app" {
  count = var.bootstrap_apps ? 1 : 0
  url   = "${replace(trimsuffix(var.repo_url, ".git"), "github.com", "raw.githubusercontent.com")}/main/argocd/kube-prometheus-stack.yaml"

  lifecycle {
    postcondition {
      condition     = !strcontains(self.response_body, "__VERSION__")
      error_message = "argocd/kube-prometheus-stack.yaml on GitHub still contains __VERSION__. Put a real chart version there and push."
    }
  }
}

resource "kubectl_manifest" "app_monitoring" {
  count     = var.bootstrap_apps ? 1 : 0
  yaml_body = data.http.kps_app[0].response_body

  depends_on = [helm_release.argocd]
}