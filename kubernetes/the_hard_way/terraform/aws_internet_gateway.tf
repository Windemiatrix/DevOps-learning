resource "aws_internet_gateway" "kubernetes-the-hard-way" {
  vpc_id = aws_vpc.kubernetes-the-hard-way.id
}
