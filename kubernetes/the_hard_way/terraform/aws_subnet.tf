#resource "aws_subnet" "front_end" {
#  vpc_id     = aws_vpc.kubernetes-the-hard-way.id
#  cidr_block = "10.0.1.0/24"
#}

#resource "aws_subnet" "back_end" {
#  vpc_id = aws_vpc.kubernetes-the-hard-way.id
#  cidr_block = "10.0.2.0/24"
#}

resource "aws_subnet" "kubernetes" {
  vpc_id = aws_vpc.kubernetes-the-hard-way.id
  cidr_block = "10.240.0.0/24"
}
