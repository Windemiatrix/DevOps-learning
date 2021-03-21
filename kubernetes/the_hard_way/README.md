# kubernetes the hard way

<https://github.com/kelseyhightower/kubernetes-the-hard-way>

## Installing the Client Tools

In this lab you will install the command line utilities required to complete this tutorial: `cfssl`, `cfssljson`, and `kubectl`.

### Install CFSSL

The `cfssl` and `cfssljson` command line utilities will be used to provision a PKI Infrastructure and generate TLS certificates.

``` bash
wget -q --show-progress --https-only --timestamping \
  https://storage.googleapis.com/kubernetes-the-hard-way/cfssl/1.4.1/linux/cfssl \
  https://storage.googleapis.com/kubernetes-the-hard-way/cfssl/1.4.1/linux/cfssljson
```

``` bash
chmod +x cfssl cfssljson
```

``` bash
sudo mv cfssl cfssljson /usr/local/bin/
```

``` bash
$ cfssl version
Version: 1.4.1
Runtime: go1.12.12
```

``` bash
$ cfssljson --version
Version: 1.4.1
Runtime: go1.12.12
```

### Install kubectl

The kubectl command line utility is used to interact with the Kubernetes API Server. Download and install kubectl from the official release binaries:

``` bash
wget https://storage.googleapis.com/kubernetes-release/release/v1.18.6/bin/linux/amd64/kubectl
```

``` bash
chmod +x kubectl
```

``` bash
sudo mv kubectl /usr/local/bin/
```

``` bash
$ kubectl version --client
Client Version: version.Info{Major:"1", Minor:"18", GitVersion:"v1.18.6", GitCommit:"dff82dc0de47299ab66c83c626e08b245ab19037", GitTreeState:"clean", BuildDate:"2020-07-15T16:58:53Z", GoVersion:"go1.13.9", Compiler:"gc", Platform:"linux/amd64"}
```

## Provisioning Compute Resources

Kubernetes requires a set of machines to host the Kubernetes control plane and the worker nodes where containers are ultimately run. In this lab you will provision the compute resources required for running a secure and highly available Kubernetes cluster across a single compute zone.

### Networking

The Kubernetes networking model assumes a flat network in which containers and nodes can communicate with each other. In cases where this is not desired network policies can limit how groups of containers are allowed to communicate with each other and external network endpoints.

Create the `kubernetes-the-hard-way` VPC network:

``` terraform
resource "aws_vpc" "kubernetes-the-hard-way" {
  cidr_block = "10.0.0.0/16"
  instance_tenancy = "default"
    # default - your instance runs on shared hardware - free
    # dedicated - your instance runs on single-tenant hardware - 2$ per hour
    # host - your instance runs on a Dedicated Host, which is an isolated server with configurations that you can control - 2$ per hour
}
```

Create the `kubernetes` subnet in the `kubernetes-the-hard-way` VPC network

``` terraform
resource "aws_subnet" "kubernetes" {
  vpc_id = aws_vpc.kubernetes-the-hard-way.id
  cidr_block = "10.240.0.0/24"
}
```

### Firewall rules (security groups)

Create a security groups that allows internal communication across all protocols and allows external SSH, ICMP, and HTTPS

``` terraform
resource "aws_security_group" "kubernetes-the-hard-way" {
  description = "K8s master security group"
  vpc_id = aws_vpc.kubernetes-the-hard-way.id
  ingress {
    cidr_blocks = ["0.0.0.0/0"]
    from_port = 22
    to_port = 22
    protocol = "tcp"
  }
  ingress {
    cidr_blocks = ["0.0.0.0/0"]
    from_port = 6443
    to_port = 6443
    protocol = "tcp"
  }
  ingress {
    cidr_blocks = ["0.0.0.0/0"]
    from_port = 8
    to_port = 0
    protocol = "icmp"
  }
  egress {
    cidr_blocks = ["0.0.0.0/0"]
    from_port = 0
    to_port = 0
    protocol = "-1"
  }
}
```

### Compute Instances

The compute instances in this lab will be provisioned using Ubuntu Server 20.04, which has good support for the containerd container runtime. Each compute instance will be provisioned with a fixed private IP address to simplify the Kubernetes bootstrapping process.

#### Preparing

SSH key for access:

``` terraform
resource "aws_key_pair" "ssh" {
  key_name   = "ssh"
  public_key = file(var.public_key_path)
}
```

AWS AMI for specify instance distributive:

``` terraform
data "aws_ami" "ubuntu" {
  most_recent = true
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
  owners = ["099720109477"] # Canonical
}
```

#### Kubernetes Controllers

Create three compute instances which will host the Kubernetes control plane:

``` terraform
resource "aws_instance" "controller" {
  count = 3
  instance_type = "t2.micro"
  ami = data.aws_ami.ubuntu.id
  key_name = aws_key_pair.ssh.key_name
  subnet_id = aws_subnet.kubernetes.id
  private_ip = "10.240.0.1${count.index}"
  security_groups = [
    aws_security_group.kubernetes-the-hard-way.id
  ]
  root_block_device {
    volume_size = "20"
  }
  tags = {
    Name = "Server ${count.index}"
  }
}
```

#### Kubernetes workers

Create three compute instances which will host the Kubernetes control plane:

``` terraform
resource "aws_instance" "worker" {
  count = 3
  instance_type = "t2.micro"
  ami = data.aws_ami.ubuntu.id
  key_name = aws_key_pair.ssh.key_name
  subnet_id = aws_subnet.kubernetes.id
  private_ip = "10.240.0.2${count.index}"
  security_groups = [
    aws_security_group.kubernetes-the-hard-way.id
  ]
  root_block_device {
    volume_size = "20"
  }
  tags = {
    Name = "Worker ${count.index}"
  }
}
```

### Kubernetes Public IP Address

Allocate a static IP address that will be attached to the external load balancer fronting the Kubernetes API Servers:

``` terraform
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
```

### Kubernetes internet access

Create internet gateway for internet access

``` terraform
resource "aws_internet_gateway" "kubernetes-the-hard-way" {
  vpc_id = aws_vpc.kubernetes-the-hard-way.id
}
```

Route table:

``` terraform
resource "aws_route_table" "kubernetes" {
  vpc_id = aws_vpc.kubernetes-the-hard-way.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.kubernetes-the-hard-way.id
  }
}
```

Attach route table to subnet:

``` terraform
resource "aws_route_table_association" "kubernetes" {
  subnet_id = aws_subnet.kubernetes.id
  route_table_id = aws_route_table.kubernetes.id
}
```

## Provisioning a CA and Generating TLS Certificates

In this lab you will provision a PKI Infrastructure using CloudFlare's PKI toolkit, cfssl, then use it to bootstrap a Certificate Authority, and generate TLS certificates for the following components: etcd, kube-apiserver, kube-controller-manager, kube-scheduler, kubelet, and kube-proxy.

### Certificate Authority

In this section you will provision a Certificate Authority that can be used to generate additional TLS certificates.

Generate the CA configuration file, certificate, and private key:

``` bash
mkdir kubernetes/the_hard_way/tls
cd kubernetes/the_hard_way/tls
```

``` bash
{

cat > ca-config.json <<EOF
{
  "signing": {
    "default": {
      "expiry": "8760h"
    },
    "profiles": {
      "kubernetes": {
        "usages": ["signing", "key encipherment", "server auth", "client auth"],
        "expiry": "8760h"
      }
    }
  }
}
EOF

cat > ca-csr.json <<EOF
{
  "CN": "Kubernetes",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "RU",
      "L": "Vladimir",
      "O": "Kubernetes",
      "OU": "CA",
      "ST": "CFO"
    }
  ]
}
EOF

cfssl gencert -initca ca-csr.json | cfssljson -bare ca

}
```

Results:

``` bash
$ ls
ca-config.json  ca.csr  ca-csr.json  ca-key.pem  ca.pem
```

### Client and Server Certificates

In this section you will generate client and server certificates for each Kubernetes component and a client certificate for the Kubernetes admin user.

#### The Admin Client Certificate

Generate the admin client certificate and private key:

``` bash
{

cat > admin-csr.json <<EOF
{
  "CN": "admin",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "RU",
      "L": "Vladimir",
      "O": "system:masters",
      "OU": "Kubernetes The Hard Way",
      "ST": "CFO"
    }
  ]
}
EOF

cfssl gencert \
  -ca=ca.pem \
  -ca-key=ca-key.pem \
  -config=ca-config.json \
  -profile=kubernetes \
  admin-csr.json | cfssljson -bare admin

}
```

Results:

``` bash
$ ls
admin.csr  admin-csr.json  admin-key.pem  admin.pem  ca-config.json  ca.csr  ca-csr.json  ca-key.pem  ca.pem
```

#### The Kubelet Client Certificates

Kubernetes uses a special-purpose authorization mode called Node Authorizer, that specifically authorizes API requests made by Kubelets. In order to be authorized by the Node Authorizer, Kubelets must use a credential that identifies them as being in the system:nodes group, with a username of system:node:<nodeName>. In this section you will create a certificate for each Kubernetes worker node that meets the Node Authorizer requirements.

Generate a certificate and private key for each Kubernetes worker node:

``` bash
for instance in i-0ea27d3f0a709e6ff i-00d7634beb596d33c i-020b86c150447c7b9; do
cat > ${instance}-csr.json <<EOF
{
  "CN": "system:node:${instance}",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "RU",
      "L": "Vladimir",
      "O": "system:nodes",
      "OU": "Kubernetes The Hard Way",
      "ST": "CFO"
    }
  ]
}
EOF

EXTERNAL_IP=$(aws ec2 describe-instances --instance-ids ${instance} \
  --query "Reservations[*].Instances[*].PublicIpAddress" \
  --output=text)

INTERNAL_IP=$(aws ec2 describe-instances --instance-ids ${instance} \
  --query "Reservations[*].Instances[*].PrivateIpAddress" \
  --output=text)

cfssl gencert \
  -ca=ca.pem \
  -ca-key=ca-key.pem \
  -config=ca-config.json \
  -hostname=${instance},${EXTERNAL_IP},${INTERNAL_IP} \
  -profile=kubernetes \
  ${instance}-csr.json | cfssljson -bare ${instance}
done
```

Results:

``` bash
$ ls
admin.csr       ca-key.pem                    i-020b86c150447c7b9-csr.json
admin-csr.json  ca.pem                        i-020b86c150447c7b9-key.pem
admin-key.pem   i-00d7634beb596d33c.csr       i-020b86c150447c7b9.pem
admin.pem       i-00d7634beb596d33c-csr.json  i-0ea27d3f0a709e6ff.csr
ca-config.json  i-00d7634beb596d33c-key.pem   i-0ea27d3f0a709e6ff-csr.json
ca.csr          i-00d7634beb596d33c.pem       i-0ea27d3f0a709e6ff-key.pem
ca-csr.json     i-020b86c150447c7b9.csr       i-0ea27d3f0a709e6ff.pem
```

#### The Controller Manager Client Certificate

Generate the kube-controller-manager client certificate and private key:

``` bash
{

cat > kube-controller-manager-csr.json <<EOF
{
  "CN": "system:kube-controller-manager",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "RU",
      "L": "Vladimir",
      "O": "system:kube-controller-manager",
      "OU": "Kubernetes The Hard Way",
      "ST": "CFO"
    }
  ]
}
EOF

cfssl gencert \
  -ca=ca.pem \
  -ca-key=ca-key.pem \
  -config=ca-config.json \
  -profile=kubernetes \
  kube-controller-manager-csr.json | cfssljson -bare kube-controller-manager

}
```

Results:

``` bash
$ ls
admin.csr       i-00d7634beb596d33c.csr       i-0ea27d3f0a709e6ff-csr.json
admin-csr.json  i-00d7634beb596d33c-csr.json  i-0ea27d3f0a709e6ff-key.pem
admin-key.pem   i-00d7634beb596d33c-key.pem   i-0ea27d3f0a709e6ff.pem
admin.pem       i-00d7634beb596d33c.pem       kube-controller-manager.csr
ca-config.json  i-020b86c150447c7b9.csr       kube-controller-manager-csr.json
ca.csr          i-020b86c150447c7b9-csr.json  kube-controller-manager-key.pem
ca-csr.json     i-020b86c150447c7b9-key.pem   kube-controller-manager.pem
ca-key.pem      i-020b86c150447c7b9.pem
ca.pem          i-0ea27d3f0a709e6ff.csr
```

#### The Kube Proxy Client Certificate

Generate the kube-proxy client certificate and private key:

``` bash
{

cat > kube-proxy-csr.json <<EOF
{
  "CN": "system:kube-proxy",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "RU",
      "L": "Vladimir",
      "O": "system:node-proxier",
      "OU": "Kubernetes The Hard Way",
      "ST": "CFO"
    }
  ]
}
EOF

cfssl gencert \
  -ca=ca.pem \
  -ca-key=ca-key.pem \
  -config=ca-config.json \
  -profile=kubernetes \
  kube-proxy-csr.json | cfssljson -bare kube-proxy

}
```

Result:

``` bash
$ ls
admin.csr                i-00d7634beb596d33c-csr.json  i-0ea27d3f0a709e6ff.pem
admin-csr.json           i-00d7634beb596d33c-key.pem   kube-controller-manager.csr
admin-key.pem            i-00d7634beb596d33c.pem       kube-controller-manager-csr.json
admin.pem                i-020b86c150447c7b9.csr       kube-controller-manager-key.pem
ca-config.json           i-020b86c150447c7b9-csr.json  kube-controller-manager.pem
ca.csr                   i-020b86c150447c7b9-key.pem   kube-proxy.csr
ca-csr.json              i-020b86c150447c7b9.pem       kube-proxy-csr.json
ca-key.pem               i-0ea27d3f0a709e6ff.csr       kube-proxy-key.pem
ca.pem                   i-0ea27d3f0a709e6ff-csr.json  kube-proxy.pem
i-00d7634beb596d33c.csr  i-0ea27d3f0a709e6ff-key.pem
```

#### The Scheduler Client Certificate

Generate the kube-scheduler client certificate and private key:

``` bash
{

cat > kube-scheduler-csr.json <<EOF
{
  "CN": "system:kube-scheduler",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "RU",
      "L": "Vladimir",
      "O": "system:kube-scheduler",
      "OU": "Kubernetes The Hard Way",
      "ST": "CFO"
    }
  ]
}
EOF

cfssl gencert \
  -ca=ca.pem \
  -ca-key=ca-key.pem \
  -config=ca-config.json \
  -profile=kubernetes \
  kube-scheduler-csr.json | cfssljson -bare kube-scheduler

}
```

Result:

``` bash
$ ls
admin.csr                     i-00d7634beb596d33c-key.pem   kube-controller-manager-csr.json
admin-csr.json                i-00d7634beb596d33c.pem       kube-controller-manager-key.pem
admin-key.pem                 i-020b86c150447c7b9.csr       kube-controller-manager.pem
admin.pem                     i-020b86c150447c7b9-csr.json  kube-proxy.csr
ca-config.json                i-020b86c150447c7b9-key.pem   kube-proxy-csr.json
ca.csr                        i-020b86c150447c7b9.pem       kube-proxy-key.pem
ca-csr.json                   i-0ea27d3f0a709e6ff.csr       kube-proxy.pem
ca-key.pem                    i-0ea27d3f0a709e6ff-csr.json  kube-scheduler.csr
ca.pem                        i-0ea27d3f0a709e6ff-key.pem   kube-scheduler-csr.json
i-00d7634beb596d33c.csr       i-0ea27d3f0a709e6ff.pem       kube-scheduler-key.pem
i-00d7634beb596d33c-csr.json  kube-controller-manager.csr   kube-scheduler.pem
```

#### The Kubernetes API Server Certificate

The kubernetes-the-hard-way static IP address will be included in the list of subject alternative names for the Kubernetes API Server certificate. This will ensure the certificate can be validated by remote clients.

Generate the Kubernetes API Server certificate and private key:

``` bash
{

KUBERNETES_PUBLIC_ADDRESS=$(gcloud compute addresses describe kubernetes-the-hard-way \
  --region $(gcloud config get-value compute/region) \
  --format 'value(address)')

KUBERNETES_HOSTNAMES=kubernetes,kubernetes.default,kubernetes.default.svc,kubernetes.default.svc.cluster,kubernetes.svc.cluster.local

cat > kubernetes-csr.json <<EOF
{
  "CN": "kubernetes",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "US",
      "L": "Portland",
      "O": "Kubernetes",
      "OU": "Kubernetes The Hard Way",
      "ST": "Oregon"
    }
  ]
}
EOF

cfssl gencert \
  -ca=ca.pem \
  -ca-key=ca-key.pem \
  -config=ca-config.json \
  -hostname=10.32.0.1,10.240.0.10,10.240.0.11,10.240.0.12,${KUBERNETES_PUBLIC_ADDRESS},127.0.0.1,${KUBERNETES_HOSTNAMES} \
  -profile=kubernetes \
  kubernetes-csr.json | cfssljson -bare kubernetes

}
```
