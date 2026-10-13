# IAM, the SQS interruption queue and the node role (created by the module)
module "karpenter" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "~> 21.0"

  cluster_name = module.eks.cluster_name

  enable_inline_policy = true

  node_iam_role_additional_policies = {
    AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }
}

resource "helm_release" "karpenter" {
  name       = "karpenter"
  namespace  = "kube-system"
  repository = "oci://public.ecr.aws/karpenter"
  chart      = "karpenter"
  version    = var.karpenter_version
  timeout    = 600

  values = [yamlencode({
    nodeSelector = { "karpenter.sh/controller" = "true" }
    settings = {
      clusterName       = module.eks.cluster_name
      interruptionQueue = module.karpenter.queue_name
    }
  })]

  depends_on = [module.karpenter]
}

resource "kubectl_manifest" "ec2nodeclass" {
  yaml_body = yamlencode({
    apiVersion = "karpenter.k8s.aws/v1"
    kind       = "EC2NodeClass"
    metadata   = { name = "default" }
    spec = {
      role                       = module.karpenter.node_iam_role_name
      amiSelectorTerms           = [{ alias = "al2023@latest" }]
      subnetSelectorTerms        = [{ tags = { "karpenter.sh/discovery" = local.cluster_name } }]
      securityGroupSelectorTerms = [{ tags = { "karpenter.sh/discovery" = local.cluster_name } }]
      blockDeviceMappings = [{
        deviceName = "/dev/xvda"
        ebs        = { volumeSize = "30Gi", volumeType = "gp3", encrypted = true }
      }]
    }
  })

  depends_on = [helm_release.karpenter]
}

# Two pools. Karpenter tries the higher weight first, so AZ a is active.
# AZ b only gets nodes when AZ a cannot provide them (the failover case).
locals {
  nodepools = {
    primary-a  = { zone = local.azs[0], weight = 100 }
    fallback-b = { zone = local.azs[1], weight = 10 }
  }
}

resource "kubectl_manifest" "nodepool" {
  for_each = local.nodepools

  yaml_body = yamlencode({
    apiVersion = "karpenter.sh/v1"
    kind       = "NodePool"
    metadata   = { name = each.key }
    spec = {
      weight = each.value.weight
      template = {
        spec = {
          nodeClassRef = { group = "karpenter.k8s.aws", kind = "EC2NodeClass", name = "default" }
          requirements = [
            { key = "topology.kubernetes.io/zone", operator = "In", values = [each.value.zone] },
            { key = "node.kubernetes.io/instance-type", operator = "In", values = [var.instance_type] },
            { key = "karpenter.sh/capacity-type", operator = "In", values = ["on-demand"] },
            { key = "kubernetes.io/arch", operator = "In", values = ["amd64"] },
          ]
        }
      }
      limits     = { cpu = "10" }
      disruption = { consolidationPolicy = "WhenEmptyOrUnderutilized", consolidateAfter = "2m" }
    }
  })

  depends_on = [kubectl_manifest.ec2nodeclass]
}