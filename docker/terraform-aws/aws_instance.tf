resource "aws_instance" "docker-1" {
  ami = data.aws_ami.ubuntu.id
  instance_type = "t2.micro"
  key_name = aws_key_pair.rmartsev.key_name
  
  vpc_security_group_ids = [
    aws_security_group.allow_ssh.id
  ]
}
