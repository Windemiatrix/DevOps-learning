resource "aws_key_pair" "rmartsev" {
  key_name   = "rmartsev"
  public_key = file(var.public_key_path)
}
