resource "aws_eip" "kubernetes_controller" {
  count = 3
  vpc = true
  instance = aws_instance.controller[count.index].id
  tags = {
    Name = "Controller ${count.index}"
  }
}

resource "aws_eip" "kubernetes_worker" {
  count = 3
  vpc = true
  instance = aws_instance.worker[count.index].id
  tags = {
    Name = "Worker ${count.index}"
  }
}

#resource "aws_eip" "balancer" {
#  vpc = true
#}
