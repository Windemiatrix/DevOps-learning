resource "aws_instance" "controller" {
  count = 3
  instance_type = "t2.micro"
  ami = data.aws_ami.ubuntu.id
  key_name = aws_key_pair.ssh.key_name
  subnet_id = aws_subnet.kubernetes.id
  private_ip = "10.240.0.1${count.index}"
  security_groups = [
    aws_security_group.kubernetes-the-hard-way.id
  ]
  root_block_device {
    volume_size = "20"
  }
  tags = {
    Name = "Controller ${count.index}"
  }
}

resource "aws_instance" "worker" {
  count = 3
  instance_type = "t2.micro"
  ami = data.aws_ami.ubuntu.id
  key_name = aws_key_pair.ssh.key_name
  subnet_id = aws_subnet.kubernetes.id
  private_ip = "10.240.0.2${count.index}"
  security_groups = [
    aws_security_group.kubernetes-the-hard-way.id
  ]
  root_block_device {
    volume_size = "20"
  }
  tags = {
    Name = "Worker ${count.index}"
  }
}
