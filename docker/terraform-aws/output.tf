output "docker-1_private-ip" {
    value = aws_instance.docker-1.private_ip
}
output "docker-1_public-ip" {
    value = aws_eip.docker-1.public_ip
}
