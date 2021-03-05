resource "aws_eip" "docker-1" {
  vpc      = true
  instance = aws_instance.docker-1.id
}
