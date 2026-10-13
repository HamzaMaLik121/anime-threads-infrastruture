# gp3 volumes for Prometheus, Grafana and ArgoCD (not the default class)
resource "kubectl_manifest" "gp3" {
  yaml_body = yamlencode({
    apiVersion           = "storage.k8s.io/v1"
    kind                 = "StorageClass"
    metadata             = { name = "gp3" }
    provisioner          = "ebs.csi.aws.com"
    volumeBindingMode    = "WaitForFirstConsumer"
    reclaimPolicy        = "Delete"
    allowVolumeExpansion = true
    parameters           = { type = "gp3", encrypted = "true" }
  })

  depends_on = [module.eks]
}

# ---------- AWS Load Balancer Controller (creates the ALB from your Ingress) ----------
data "http" "lbc_policy" {
  url = "https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/main/docs/install/iam_policy.json"
}

resource "aws_iam_policy" "lbc" {
  name   = "${local.cluster_name}-lbc"
  policy = data.http.lbc_policy.response_body
}

resource "aws_iam_role" "lbc" {
  name               = "${local.cluster_name}-lbc"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_trust.json
}

resource "aws_iam_role_policy_attachment" "lbc" {
  role       = aws_iam_role.lbc.name
  policy_arn = aws_iam_policy.lbc.arn
}

resource "aws_eks_pod_identity_association" "lbc" {
  cluster_name    = module.eks.cluster_name
  namespace       = "kube-system"
  service_account = "aws-load-balancer-controller"
  role_arn        = aws_iam_role.lbc.arn
}

resource "helm_release" "lbc" {
  name       = "aws-load-balancer-controller"
  namespace  = "kube-system"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  timeout    = 900

  values = [yamlencode({
    clusterName    = module.eks.cluster_name
    region         = var.region
    vpcId          = aws_vpc.main.id
    serviceAccount = { create = true, name = "aws-load-balancer-controller" }
  })]

  depends_on = [kubectl_manifest.nodepool, aws_eks_pod_identity_association.lbc]
}

# ---------- metrics-server (needed by your HPAs; no kind-only TLS flag on EKS) ----------
resource "helm_release" "metrics_server" {
  name       = "metrics-server"
  namespace  = "kube-system"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  timeout    = 900

  depends_on = [kubectl_manifest.nodepool]
}