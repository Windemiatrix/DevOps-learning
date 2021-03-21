resource "aws_route_table_association" "kubernetes" {
  subnet_id = aws_subnet.kubernetes.id
  route_table_id = aws_route_table.kubernetes.id
}
