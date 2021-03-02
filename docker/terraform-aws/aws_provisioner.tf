resource "local_file" "AnsibleInventory" {
    content = templatefile(
        "../ansible/inventory.tmpl",
        {
            docker_public = aws_eip.docker-1.public_ip
            docker_internal = aws_instance.docker-1.private_ip
        }
    )
    filename = "../ansible/inventory"
    depends_on = [
        aws_instance.docker-1
    ]
}

resource "null_resource" "example" {
  provisioner "remote-exec" {
    connection {
      host = aws_eip.docker-1.public_ip
      user = "ubuntu"
      private_key = file(var.private_key_path)
    }

    inline = ["echo '-= CONNECTED =-'"]
  }

  provisioner "local-exec" {
    command = "ansible-playbook ../ansible/install-docker.yml"
  }
}
