output "cluster_name" {
  value = var.cluster_name
}

output "base_domain" {
  value = var.base_domain
}

output "remote_dir" {
  value = var.remote_dir
}

output "rancher_host" {
  value = local.rancher_host
}

output "registry_host" {
  value = local.registry_host
}

output "region" {
  value = var.region
}

output "ssh_user" {
  value = var.ssh_user
}

output "instance_id" {
  value = aws_instance.server.id
}

output "availability_zone" {
  value = aws_instance.server.availability_zone
}

output "ami_id" {
  value = aws_instance.server.ami
}

output "public_ip" {
  value = aws_instance.server.public_ip
}

output "private_ip" {
  value = aws_instance.server.private_ip
}

output "public_dns" {
  value = aws_instance.server.public_dns
}

output "vpc_id" {
  value = local.selected_vpc_id
}

output "subnet_id" {
  value = local.selected_subnet_id
}

output "security_group_id" {
  value = aws_security_group.server.id
}
