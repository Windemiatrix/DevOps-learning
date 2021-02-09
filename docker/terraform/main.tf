terraform {
    # Версия terraform
    required_version = "0.14.5"
}
provider "google" {
    #ID проекта
    project = var.project

    region = var.region
}

resource "google_compute_instance" "docker" {
    name = "docker"
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
    tags = ["allow-http", "allow-https", "allow-tcp-8080", "allow-tcp-9090", "allow-tcp-9292", "allow-tcp-3000"]
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

resource "google_compute_firewall" "firewall_tcp_8080" {
    name = "allow-tcp-8080"
    # Название сети, в которой действует правило
    network = "default"
    # Какой доступ разрешить
    allow {
        protocol = "tcp"
        ports = ["8080"]
    }
    # Каким адресам разрешаем доступ
    source_ranges = ["0.0.0.0/0"]
    # Правило применимо для инстансов с перечисленными тэгами
    target_tags = ["allow-tcp-8080"]
}

resource "google_compute_firewall" "firewall_tcp_9090" {
    name = "allow-tcp-9090"
    # Название сети, в которой действует правило
    network = "default"
    # Какой доступ разрешить
    allow {
        protocol = "tcp"
        ports = ["9090"]
    }
    # Каким адресам разрешаем доступ
    source_ranges = ["0.0.0.0/0"]
    # Правило применимо для инстансов с перечисленными тэгами
    target_tags = ["allow-tcp-9090"]
}

resource "google_compute_firewall" "firewall_tcp_9292" {
    name = "allow-tcp-9292"
    # Название сети, в которой действует правило
    network = "default"
    # Какой доступ разрешить
    allow {
        protocol = "tcp"
        ports = ["9292"]
    }
    # Каким адресам разрешаем доступ
    source_ranges = ["0.0.0.0/0"]
    # Правило применимо для инстансов с перечисленными тэгами
    target_tags = ["allow-tcp-9292"]
}

resource "google_compute_firewall" "firewall_tcp_3000" {
    name = "allow-tcp-3000"
    # Название сети, в которой действует правило
    network = "default"
    # Какой доступ разрешить
    allow {
        protocol = "tcp"
        ports = ["3000"]
    }
    # Каким адресам разрешаем доступ
    source_ranges = ["0.0.0.0/0"]
    # Правило применимо для инстансов с перечисленными тэгами
    target_tags = ["allow-tcp-3000"]
}

resource "local_file" "AnsibleInventory" {
    content = templatefile(
        "../ansible/inventory.tmpl",
        {
            docker_public = google_compute_instance.docker.network_interface.0.access_config.0.nat_ip
            docker_internal = google_compute_instance.docker.network_interface.0.network_ip
        }
    )
    filename = "../ansible/inventory"
    depends_on = [
        google_compute_instance.docker
    ]
}

resource "null_resource" "example" {
  provisioner "remote-exec" {
    connection {
      host = google_compute_instance.docker.network_interface.0.access_config.0.nat_ip
      user = "rmartsev"
      private_key = file(var.private_key_path)
    }

    inline = ["echo 'connected!'"]
  }

  provisioner "local-exec" {
    command = "ansible-playbook ../ansible/install-docker.yml"
  }
}
