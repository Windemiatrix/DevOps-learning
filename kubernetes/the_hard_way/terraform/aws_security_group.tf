resource "aws_security_group" "kubernetes-the-hard-way" {
  description = "K8s master security group"
  vpc_id = aws_vpc.kubernetes-the-hard-way.id
  ingress {
    cidr_blocks = ["0.0.0.0/0"]
    from_port = 22
    to_port = 22
    protocol = "tcp"
  }
  ingress {
    cidr_blocks = ["0.0.0.0/0"]
    from_port = 6443
    to_port = 6443
    protocol = "tcp"
  }
  ingress {
    cidr_blocks = ["0.0.0.0/0"]
    from_port = 8
    to_port = 0
    protocol = "icmp"
  }
  egress {
    cidr_blocks = ["0.0.0.0/0"]
    from_port = 0
    to_port = 0
    protocol = "-1"
  }
}
