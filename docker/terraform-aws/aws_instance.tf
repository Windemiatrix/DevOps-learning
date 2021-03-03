resource "aws_instance" "docker-1" {
  ami = data.aws_ami.ubuntu.id
  instance_type = "t2.micro"
  key_name = aws_key_pair.rmartsev.key_name

  root_block_device {
    volume_size           = 20
  }
  
  vpc_security_group_ids = [
    aws_security_group.docker-1-IN.id,
    aws_security_group.docker-1-OUT.id
  ]
}
