# Self-hosted GitHub Actions runner on EC2.
# Replaces GitHub-hosted runners — self-hosted runners have zero GitHub billing.
# You only pay for the EC2 instance (~$8/month t3.micro, ~$2/month spot).
#
# One-time setup before terraform apply:
#   1. Create a GitHub Fine-grained PAT:
#      GitHub → Settings → Developer settings → Personal access tokens
#      Repository permissions: Actions = Read & write
#
#   2. Store the PAT in SSM:
#      aws ssm put-parameter \
#        --name  /github-runner/pat \
#        --value "github_pat_xxxxxxxxxxxx" \
#        --type  SecureString \
#        --region <your-region>
#
#   3. Run: cd scripts && terraform apply
#
#   4. In GitHub repo Settings → Variables, add: RUNNER = self-hosted

# ─── Runner-specific variables ────────────────────────────────────────────────
# (aws_region, project_name, github_org, github_repo are shared with bootstrap.tf)

variable "runner_version" {
  description = "GitHub Actions runner version (https://github.com/actions/runner/releases)"
  type        = string
  default     = "2.322.0"
}

variable "runner_instance_type" {
  description = "EC2 instance type for the runner"
  type        = string
  default     = "t3.micro"
}

variable "runner_use_spot" {
  description = "Use a Spot instance (~75% cheaper; builds cancel if instance is reclaimed)"
  type        = bool
  default     = false
}

# ─── Latest Amazon Linux 2023 AMI (via SSM parameter) ────────────────────────

data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

# ─── IAM: runner only needs SSM read for the PAT ─────────────────────────────
# AWS deployment credentials come from OIDC at runtime — no keys on the instance.

resource "aws_iam_role" "runner" {
  name = "${var.project_name}-github-runner"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = { Name = "${var.project_name}-github-runner" }
}

resource "aws_iam_role_policy_attachment" "runner_ssm" {
  role       = aws_iam_role.runner.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy" "runner_pat" {
  name = "read-github-pat"
  role = aws_iam_role.runner.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["ssm:GetParameter"]
      Resource = "arn:aws:ssm:${var.aws_region}:*:parameter/github-runner/pat"
    }]
  })
}

resource "aws_iam_instance_profile" "runner" {
  name = "${var.project_name}-github-runner"
  role = aws_iam_role.runner.name
}

# ─── Security group — outbound only ─────────────────────────────────────────
# Runner polls GitHub over HTTPS; no inbound traffic needed.

resource "aws_security_group" "runner" {
  name        = "${var.project_name}-github-runner"
  description = "GitHub Actions self-hosted runner - outbound only"
  vpc_id      = data.aws_vpc.default.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All outbound (GitHub API, ECR, STS, package downloads)"
  }

  tags = { Name = "${var.project_name}-github-runner" }
}

data "aws_vpc" "default" {
  default = true
}

# ─── User data — installs runner + Terraform + Docker on first boot ───────────

locals {
  runner_user_data = <<-SHELL
    #!/bin/bash
    set -euxo pipefail

    REGION="${var.aws_region}"
    GITHUB_ORG="${var.github_org}"
    GITHUB_REPO="${var.github_repo}"
    RUNNER_VERSION="${var.runner_version}"

    # ── System packages ────────────────────────────────────────────────────────
    dnf update -y
    dnf install -y --allowerasing git jq curl unzip docker libicu

    systemctl enable --now docker

    # ── Terraform ──────────────────────────────────────────────────────────────
    TF_VERSION="1.10.5"
    curl -fsSLo /tmp/tf.zip \
      "https://releases.hashicorp.com/terraform/$${TF_VERSION}/terraform_$${TF_VERSION}_linux_amd64.zip"
    unzip -o /tmp/tf.zip -d /usr/local/bin/
    chmod +x /usr/local/bin/terraform

    # ── GitHub Actions runner ─────────────────────────────────────────────────
    useradd -m -s /bin/bash runner || true
    usermod -aG docker runner

    RUNNER_DIR=/home/runner/actions-runner
    mkdir -p "$RUNNER_DIR"

    curl -fsSLo /tmp/runner.tar.gz \
      "https://github.com/actions/runner/releases/download/v$${RUNNER_VERSION}/actions-runner-linux-x64-$${RUNNER_VERSION}.tar.gz"
    tar xzf /tmp/runner.tar.gz -C "$RUNNER_DIR"
    chown -R runner:runner /home/runner

    "$RUNNER_DIR/bin/installdependencies.sh" || true

    # ── Registration token from PAT stored in SSM ──────────────────────────────
    PAT=$(aws ssm get-parameter \
      --name  /github-runner/pat \
      --with-decryption \
      --region "$REGION" \
      --query  Parameter.Value \
      --output text)

    REG_TOKEN=$(curl -fsSX POST \
      -H "Authorization: token $${PAT}" \
      -H "Accept: application/vnd.github.v3+json" \
      "https://api.github.com/repos/$${GITHUB_ORG}/$${GITHUB_REPO}/actions/runners/registration-token" \
      | jq -r .token)

    # ── Configure runner ───────────────────────────────────────────────────────
    sudo -u runner bash -c "
      cd $RUNNER_DIR
      ./config.sh \
        --url   https://github.com/$${GITHUB_ORG}/$${GITHUB_REPO} \
        --token $${REG_TOKEN} \
        --name  ec2-\$(hostname)-$${RANDOM} \
        --labels self-hosted,linux,x64,ec2 \
        --unattended \
        --replace
    "

    # ── Systemd service ────────────────────────────────────────────────────────
    cd "$RUNNER_DIR"
    ./svc.sh install runner
    ./svc.sh start runner

    echo "Runner ready."
  SHELL
}

# ─── On-demand instance ───────────────────────────────────────────────────────

resource "aws_instance" "runner" {
  count = var.runner_use_spot ? 0 : 1

  ami                    = data.aws_ssm_parameter.al2023.value
  instance_type          = var.runner_instance_type
  iam_instance_profile   = aws_iam_instance_profile.runner.name
  vpc_security_group_ids = [aws_security_group.runner.id]

  user_data                   = base64encode(local.runner_user_data)
  user_data_replace_on_change = true

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
    encrypted   = true
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  tags = { Name = "${var.project_name}-github-runner" }
}

# ─── Spot instance ────────────────────────────────────────────────────────────

resource "aws_spot_instance_request" "runner" {
  count = var.runner_use_spot ? 1 : 0

  ami                    = data.aws_ssm_parameter.al2023.value
  instance_type          = var.runner_instance_type
  iam_instance_profile   = aws_iam_instance_profile.runner.name
  vpc_security_group_ids = [aws_security_group.runner.id]
  spot_type              = "persistent"
  wait_for_fulfillment   = true

  user_data                   = base64encode(local.runner_user_data)
  user_data_replace_on_change = true

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
    encrypted   = true
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  tags = { Name = "${var.project_name}-github-runner-spot" }
}

# ─── Outputs ──────────────────────────────────────────────────────────────────

output "runner_instance_id" {
  description = "EC2 runner instance ID"
  value       = var.runner_use_spot ? try(aws_spot_instance_request.runner[0].spot_instance_id, "") : try(aws_instance.runner[0].id, "")
}

output "runner_next_step" {
  description = "Final setup step"
  value       = "In GitHub repo Settings → Variables → add: RUNNER = self-hosted"
}
