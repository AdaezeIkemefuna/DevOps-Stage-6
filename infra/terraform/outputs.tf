output "server_public_ip" {
  description = "Public IP of the EC2 instance"
  value       = aws_instance.app_server.public_ip
}

output "instance_id" {
  description = "ID of the EC2 instance"
  value       = aws_instance.app_server.id
}

output "ssh_command" {
  description = "SSH command to connect to the instance"
  value       = "ssh -i ~/.ssh/hamsa-hng-app ubuntu@${aws_instance.app_server.public_ip}"
}

output "elastic_ip" {
  description = "Elastic IP address (static)"
  value       = aws_eip.this.public_ip
}

output "private_key_pem" {
  description = "Private SSH key to connect to the instance"
  value       = tls_private_key.generated.private_key_pem
  sensitive   = true
}