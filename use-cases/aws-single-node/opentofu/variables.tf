variable "region" {
  description = "AWS region used for the EC2 instance."
  type        = string
}

variable "cluster_name" {
  description = "Prefix used for the AWS single-node resources."
  type        = string
  default     = "productive-k3s-aws"
}

variable "base_domain" {
  description = "Internal DNS suffix used for Rancher and registry hostnames."
  type        = string
  default     = "k3s.lab.internal"
}

variable "remote_dir" {
  description = "Path inside the EC2 instance where productive-k3s will be copied."
  type        = string
  default     = "/home/ubuntu/productive-k3s"
}

variable "instance_type" {
  description = "AWS EC2 instance type."
  type        = string
  default     = "t3a.xlarge"
}

variable "root_volume_size_gb" {
  description = "Root EBS volume size in GiB."
  type        = number
  default     = 80
}

variable "key_pair_name" {
  description = "Existing AWS key pair name used for SSH access."
  type        = string
  default     = ""
}

variable "ssh_user" {
  description = "Remote SSH user expected on the instance."
  type        = string
  default     = "ubuntu"
}

variable "ssh_allowed_cidr" {
  description = "CIDR allowed to reach TCP/22."
  type        = string
  default     = "0.0.0.0/0"
}

variable "http_allowed_cidr" {
  description = "CIDR allowed to reach TCP/80 and TCP/443."
  type        = string
  default     = "0.0.0.0/0"
}

variable "api_allowed_cidr" {
  description = "CIDR allowed to reach TCP/6443."
  type        = string
  default     = "0.0.0.0/0"
}

variable "ami_id" {
  description = "Optional explicit AMI id. Leave blank to resolve the latest Ubuntu 24.04 LTS AMI."
  type        = string
  default     = ""
}

variable "vpc_id" {
  description = "Optional existing VPC id. If set, subnet_id must also be set."
  type        = string
  default     = ""
}

variable "subnet_id" {
  description = "Optional existing subnet id. If set, vpc_id must also be set."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Extra AWS tags applied to the created resources."
  type        = map(string)
  default     = {}
}
