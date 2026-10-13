# Trust policy shared by every EKS Pod Identity role
data "aws_iam_policy_document" "pod_identity_trust" {
  statement {
    actions = ["sts:AssumeRole", "sts:TagSession"]

    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

# One small system node per AZ. They run Karpenter and CoreDNS, and nothing else.
locals {
  system_node_group = {
    ami_type       = "AL2023_x86_64_STANDARD"
    instance_types = [var.instance_type]
    min_size       = 1
    max_size       = 1
    desired_size   = 1

    labels = { "karpenter.sh/controller" = "true" }

    taints = {
      addons = {
        key    = "CriticalAddonsOnly"
        value  = "true"
        effect = "NO_SCHEDULE"
      }
    }
  }
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.0"

  name               = local.cluster_name
  kubernetes_version = var.kubernetes_version

  vpc_id = aws_vpc.main.id
  # via the route table associations, so nodes only start after the NAT routes exist
  subnet_ids = aws_route_table_association.private[*].subnet_id

  endpoint_public_access       = true
  endpoint_public_access_cidrs = [var.my_ip_cidr]
  endpoint_private_access      = true

  enable_cluster_creator_admin_permissions = true

  addons = {
    coredns                = {}
    kube-proxy             = {}
    vpc-cni                = { before_compute = true }
    eks-pod-identity-agent = { before_compute = true }
    aws-ebs-csi-driver     = {}
  }

  eks_managed_node_groups = {
    system-a = merge(local.system_node_group, { subnet_ids = [aws_route_table_association.private[0].subnet_id] })
    system-b = merge(local.system_node_group, { subnet_ids = [aws_route_table_association.private[1].subnet_id] })
  }

  # Karpenter finds the security group for its nodes by this tag
  node_security_group_tags = {
    "karpenter.sh/discovery" = local.cluster_name
  }
}

# IAM for the EBS CSI driver (lets pods create EBS volumes)
resource "aws_iam_role" "ebs_csi" {
  name               = "${local.cluster_name}-ebs-csi"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_trust.json
}

resource "aws_iam_role_policy_attachment" "ebs_csi" {
  role       = aws_iam_role.ebs_csi.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

resource "aws_eks_pod_identity_association" "ebs_csi" {
  cluster_name    = module.eks.cluster_name
  namespace       = "kube-system"
  service_account = "ebs-csi-controller-sa"
  role_arn        = aws_iam_role.ebs_csi.arn
}