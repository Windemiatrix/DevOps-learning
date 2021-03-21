resource "aws_vpc" "kubernetes-the-hard-way" {
  cidr_block = "10.240.0.0/16"
  instance_tenancy = "default"
    # default - your instance runs on shared hardware - free
    # dedicated - your instance runs on single-tenant hardware - 2$ per hour
    # host - your instance runs on a Dedicated Host, which is an isolated server with configurations that you can control - 2$ per hour
}
