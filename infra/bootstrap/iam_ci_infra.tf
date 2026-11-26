data "aws_iam_policy_document" "ci_infra_read" {
  statement {
    sid       = "Ec2Read"
    actions   = ["ec2:Describe*"]
    resources = ["*"] # EC2 Describe* has no resource-level permissions; "*" is required

    condition {
      values   = [var.region]
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
    }
  }

  statement {
    sid       = "EcrRead"
    actions   = ["ecr:DescribeRepositories", "ecr:ListTagsForResource", "ecr:GetLifecyclePolicy"]
    resources = [local.ecr_repo_arn_pattern]

    condition {
      values   = [var.region]
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
    }
  }
}

data "aws_iam_policy_document" "ci_infra_write" {
  source_policy_documents = [data.aws_iam_policy_document.ci_infra_read.json]

  statement {
    sid = "Ec2Write"
    actions = [
      # VPC
      "ec2:CreateVpc", "ec2:DeleteVpc", "ec2:ModifyVpcAttribute",
      # Subnets
      "ec2:CreateSubnet", "ec2:DeleteSubnet", "ec2:ModifySubnetAttribute",
      # Internet gateway
      "ec2:CreateInternetGateway", "ec2:DeleteInternetGateway",
      "ec2:AttachInternetGateway", "ec2:DetachInternetGateway",
      # Routing
      "ec2:CreateRouteTable", "ec2:DeleteRouteTable",
      "ec2:CreateRoute", "ec2:DeleteRoute", "ec2:ReplaceRoute",
      "ec2:AssociateRouteTable", "ec2:DisassociateRouteTable",
      # Security groups
      "ec2:CreateSecurityGroup", "ec2:DeleteSecurityGroup",
      "ec2:AuthorizeSecurityGroupIngress", "ec2:AuthorizeSecurityGroupEgress",
      "ec2:RevokeSecurityGroupIngress", "ec2:RevokeSecurityGroupEgress",
      "ec2:ModifySecurityGroupRules",
      "ec2:UpdateSecurityGroupRuleDescriptionsIngress",
      "ec2:UpdateSecurityGroupRuleDescriptionsEgress",
      # Tags (default_tags are applied on create and on update)
      "ec2:CreateTags", "ec2:DeleteTags",
    ]
    resources = ["*"] # Network actions touch several ARNs per call (e.g. CreateSubnet: subnet + vpc); scoped by action list + Region. ABAC tag conditions are the hardening path.

    condition {
      values   = [var.region]
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
    }
  }

  statement {
    sid = "EcrWrite"
    actions = [
      # Repositories
      "ecr:CreateRepository", "ecr:DeleteRepository",
      # Images
      "ecr:PutImageScanningConfiguration", "ecr:PutImageTagMutability",
      # Lifecycle policies
      "ecr:PutLifecyclePolicy", "ecr:DeleteLifecyclePolicy",
      # Tagging
      "ecr:TagResource", "ecr:UntagResource"
    ]
    resources = [local.ecr_repo_arn_pattern]

    condition {
      values   = [var.region]
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
    }
  }
}

resource "aws_iam_policy" "ci_infra_read" {
  name        = "shipit-ci-infra-read"
  policy      = data.aws_iam_policy_document.ci_infra_read.json
  path        = "/ci/"
  description = "Read-only access to EC2 and ECR resources for CI jobs"
}

resource "aws_iam_policy" "ci_infra_write" {
  name        = "shipit-ci-infra-write"
  policy      = data.aws_iam_policy_document.ci_infra_write.json
  path        = "/ci/"
  description = "Write access to EC2 and ECR resources for CI jobs"
}

resource "aws_iam_role_policy_attachment" "ci_infra_read_attach" {
  role       = aws_iam_role.plan.name
  policy_arn = aws_iam_policy.ci_infra_read.arn
}

resource "aws_iam_role_policy_attachment" "ci_infra_write_attach" {
  role       = aws_iam_role.apply.name
  policy_arn = aws_iam_policy.ci_infra_write.arn
}
