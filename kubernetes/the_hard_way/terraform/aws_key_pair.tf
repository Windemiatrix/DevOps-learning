resource "aws_key_pair" "ssh" {
  key_name   = "ssh"
  public_key = file(var.public_key_path)
}
