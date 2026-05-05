provider "aws" {
  region = var.region
}

locals {
  rancher_host        = "rancher.${var.base_domain}"
  registry_host       = "registry.${var.base_domain}"
  server_name         = "${var.cluster_name}-server"
  custom_network_mode = var.vpc_id != "" || var.subnet_id != ""
}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_vpc" "default" {
  count   = local.custom_network_mode ? 0 : 1
  default = true
}

resource "aws_default_subnet" "default" {
  count             = local.custom_network_mode ? 0 : 1
  availability_zone = data.aws_availability_zones.available.names[0]
}

data "aws_ami" "ubuntu_noble" {
  count       = var.ami_id == "" ? 1 : 0
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

locals {
  selected_vpc_id    = local.custom_network_mode ? var.vpc_id : data.aws_vpc.default[0].id
  selected_subnet_id = local.custom_network_mode ? var.subnet_id : aws_default_subnet.default[0].id
  selected_ami_id    = var.ami_id != "" ? var.ami_id : data.aws_ami.ubuntu_noble[0].id
  common_tags = merge(var.tags, {
    Product = "productive-k3s"
    UseCase = "aws-single-node"
  })
}

resource "aws_security_group" "server" {
  name_prefix = "${var.cluster_name}-"
  description = "Basic public Productive K3S single-node access"
  vpc_id      = local.selected_vpc_id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.ssh_allowed_cidr]
  }

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [var.http_allowed_cidr]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.http_allowed_cidr]
  }

  ingress {
    description = "Kubernetes API"
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = [var.api_allowed_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.server_name}-sg"
  })
}

resource "aws_instance" "server" {
  ami                         = local.selected_ami_id
  instance_type               = var.instance_type
  subnet_id                   = local.selected_subnet_id
  key_name                    = var.key_pair_name
  vpc_security_group_ids      = [aws_security_group.server.id]
  associate_public_ip_address = true

  root_block_device {
    volume_size           = var.root_volume_size_gb
    volume_type           = "gp3"
    delete_on_termination = true
  }

  user_data = <<-EOF
    #cloud-config
    package_update: false
    package_upgrade: false
    manage_etc_hosts: true
    write_files:
      - path: /etc/motd
        content: |
          Productive K3S AWS single-node server
  EOF

  tags = merge(local.common_tags, {
    Name = local.server_name
  })

  lifecycle {
    precondition {
      condition     = var.key_pair_name != ""
      error_message = "key_pair_name is required for SSH-based bootstrap."
    }
    precondition {
      condition     = (var.vpc_id == "" && var.subnet_id == "") || (var.vpc_id != "" && var.subnet_id != "")
      error_message = "Set both vpc_id and subnet_id together, or leave both empty to use the default VPC path."
    }
  }
}
