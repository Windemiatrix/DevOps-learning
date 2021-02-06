terraform {
    # Версия terraform
    required_version = "0.14.5"
}
provider "google" {
    #ID проекта
    project = var.project

    region = var.region
}

resource "google_compute_instance" "gitlab" {
    name = "gitlab-ci"
    machine_type = "e2-medium"
    zone = "europe-west1-d"
    boot_disk {
        initialize_params {
            image = var.disk_image
            size  = "100"
        }
    }
    network_interface {
        network = "default"
        access_config {}
    }
        metadata = {
        # Путь до публичного ключа
        ssh-keys = "rmartsev:${file(var.public_key_path)}"
    }
    tags = ["allow-http", "allow-https"]
}

resource "google_compute_firewall" "firewall_http" {
    name = "allow-http"
    # Название сети, в которой действует правило
    network = "default"
    # Какой доступ разрешить
    allow {
        protocol = "tcp"
        ports = ["80"]
    }
    # Каким адресам разрешаем доступ
    source_ranges = ["0.0.0.0/0"]
    # Правило применимо для инстансов с перечисленными тэгами
    target_tags = ["allow-http"]
}

resource "google_compute_firewall" "firewall_https" {
    name = "allow-https"
    # Название сети, в которой действует правило
    network = "default"
    # Какой доступ разрешить
    allow {
        protocol = "tcp"
        ports = ["443"]
    }
    # Каким адресам разрешаем доступ
    source_ranges = ["0.0.0.0/0"]
    # Правило применимо для инстансов с перечисленными тэгами
    target_tags = ["allow-https"]
}

resource "local_file" "AnsibleInventory" {
    content = templatefile(
        "ansible/inventory.tmpl",
        {
            gitlab_public = google_compute_instance.gitlab.network_interface.0.access_config.0.nat_ip
            gitlab_internal = google_compute_instance.gitlab.network_interface.0.network_ip
        }
    )
    filename = "ansible/inventory"
    depends_on = [
        google_compute_instance.gitlab
    ]
}

resource "null_resource" "example" {
  provisioner "remote-exec" {
    connection {
      host = google_compute_instance.gitlab.network_interface.0.access_config.0.nat_ip
      user = "rmartsev"
      private_key = file(var.private_key_path)
    }

    inline = ["echo 'connected!'"]
  }

  provisioner "local-exec" {
    command = "ansible-playbook ansible/install-docker.yml"
  }
}
