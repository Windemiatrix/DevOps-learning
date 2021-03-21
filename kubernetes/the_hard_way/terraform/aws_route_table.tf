resource "aws_route_table" "kubernetes" {
  vpc_id = aws_vpc.kubernetes-the-hard-way.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.kubernetes-the-hard-way.id
  }
}
