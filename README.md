# Вступление

Домашнее задание по сборке образов VM при помощи Packer и Terraform

# Настройка авторизации Packer и Terraform в GCP

Создадим ADC:

```
$ gcloud auth application-default login
```

# Создание шаблона Packer

Для шаблона создадим директорию `packer` и создадим пустой файл `ubuntu16.json`, который будет шаблоном для VM.

```
$ mkdir packer
$ touch ./packer/ubuntu16.json
```

Заполним файл информацией о создании виртуальной машины для билда и создании машинного образа (блок `builders`):

```
{
    "builders": [
        {
            "type": "googlecompute",
            "project_id": "infra-296308",
            "image_name": "reddit-base-{{timestamp}}",
            "image_family": "reddit-base",
            "source_image_family": "ubuntu-1604-lts",
            "zone": "europe-west1-b",
            "ssh_username": "rmartsev",
            "machine_type": "f1_micro"
        }
    ]
}
```

где:\
`type` - что будет создавать виртуальную машину для билда образа,\
`project_id` - идентификационный номер проекта,\
`image_family` - семейство образов, к которому будет принадлежать новый образ,\
`image_name` - имя создаваемого образа,\
`source_image_family` - что взать за базовый образ билда,\
`zone` - зона, в которой запускаь VM для билда образа,\
`ssh_username` - временный пользователь, который будет создан для подключения к VM во время билда и выполнения команд провижинера,\
`machine_type` - тим инстанса, который запускается для билда.

Добавим в файл `./packer/ubuntu16.json` информацию об устанавливаемом ПО и производимых настройках системы и конфигурации приложений на созданной VM (блок `provisioners`):

```
...
    "provisioners": [
        {
            "type": "shell",
            "script": "scripts/install_ruby.sh",
            "execute_command": "sudo {{.Path}}"
        },
        {
            "type": "shell",
            "script": "scripts/install_mongodb.sh",
            "execute_command": "sudo {{.Path}}"
        }
    ]
...
```

где\
`type` - \
`script` - скрипт, запускаемый провижинером,\
`execute_command` - способ запуска скрипта.

Создадим директорию для скриптов, которые будут использованы провижинером, и скопируем туда ранее созданные `install_ruby.sh` и `install_mongodb.sh`.

```
$ cp config-scripts/install_mongodb.sh packer/scripts
$ cp config-scripts/install_ruby.sh packer/scripts
```

Проверим на наличие ошибок подготовленную конфигурацию, исправим их при наличии и запустим создание образа

```
$ packer validate ubuntu16.json
$ packer build -var-file=variables.json ubuntu16.json
```

Образ успешно создан.

# Деплой тестового приложения с помощью инстанса

Создадим VM через веб-интерфейс GCP, в качестве образа системы указав созданный образ.

# Установка зависимостей и запуск приложения

```
$ git clone -b monolith https://github.com/express42/reddit.git
$ cd reddit/
$ bundle install
$ puma -d
```

Проверяем, запуск сервера

```
$ ps aux | grep puma
rmartsev  2687  2.1  1.3 515400 26720 ?        Sl   19:43   0:00 puma 3.10.0 (tcp://0.0.0.0:9292) [reddit]
rmartsev  2701  0.0  0.0  12944  1004 pts/0    S+   19:43   0:00 grep --color=auto puma
```

Добавим установку и запуск `puma` в образ. Для этого подготовим файл `immutable.json`:

```
{
    "builders": [
        {
            "type": "googlecompute",
            "project_id": "{{user `project_id`}}",
            "image_name": "reddit-full-{{timestamp}}",
            "image_family": "reddit-full",
            "source_image_family": "{{user `source_image_family`}}",
            "zone": "europe-west1-b",
            "ssh_username": "rmartsev",
            "machine_type": "{{user `machine_type`}}",
            "disk_size": "{{user `disk_size`}}",
            "disk_type": "{{user `disk_type`}}",
            "tags": "{{user `tags`}}"
        }
    ],
    "provisioners": [
        {
            "type": "shell",
            "script": "scripts/install_ruby.sh",
            "execute_command": "sudo {{.Path}}"
        },
        {
            "type": "shell",
            "script": "scripts/install_mongodb.sh",
            "execute_command": "sudo {{.Path}}"
        },
        {
            "type": "shell",
            "script": "scripts/deploy.sh",
            "execute_command": "sudo {{.Path}}"
        },
        {
            "type": "file",
            "source": "files/reddit.service",
            "destination": "/tmp/reddit.service"
        },
        {
            "type": "shell",
            "inline": [
                "sudo mv /tmp/reddit.service /etc/systemd/system/",
                "sudo systemctl daemon-reload",
		        "sudo systemctl start reddit.service",
		        "sudo systemctl enable reddit.service"
            ]
        }
    ]
}
```

Также добавим директорию `files` для файлов, загружаемых в собираемый образ. В директории подготовим файл `reddit.service`, необходимый для запуска сервиса

```
[Unit]
Description=Puma HTTP Server (Reddit)
After=network.target


[Service]
Type=simple

User=appuser
Group=appuser

WorkingDirectory=/home/appuser/reddit

ExecStart=/usr/local/bin/puma

TimeoutSec=15
Restart=always

[Install]
WantedBy=multi-user.target
```

Команда для сборки образа:

```
packer build -var-file=variables.json immutable.json
```

# Terraform

Создаем директорию `terraform` для создания в ней конфигурации.

Файл `main.tf` содержит основные настройка Terraform.

Секция `Provider` позволяет Terraform управлять ресурсами GCP через API вызовы.

```
terraform {
    # Версия terraform
    required_version = "0.13.5"
}
provider "google" {
    # Версия провайдера
    version = "2.15"

    #ID проекта
    project = "devops-course-1"

    region = "europe-west-1"
}
```

Провайдеры `Terraform` являются загружаемыми модулями начиная с версии 0.10. Для того, чтобы загрузить провайдер и начать его использовать, необходимо выполнить команду инициализации в директории `terraform`:

```
$ terraform init

Initializing the backend...

Initializing provider plugins...
- Finding hashicorp/google versions matching "2.15.*"...
- Installing hashicorp/google v2.15.0...
- Installed hashicorp/google v2.15.0 (signed by HashiCorp)

Terraform has been successfully initialized!

You may now begin working with Terraform. Try running "terraform plan" to see
any changes that are required for your infrastructure. All Terraform commands
should now work.

If you ever set or change modules or backend configuration for Terraform,
rerun this command to reinitialize your working directory. If you forget, other
commands will detect it and remind you to do so if necessary.
```

Для создания инстанса добавим в файл `main.tf` секцию `resource`

```
resource "google_compute_instance" "app" {
    name = "reddit-map"
    machine_type = "g1-small"
    zone = "europe-west1-d"
    boot_disk {
        initialize_params {
            image = "reddit-full-1606586549"
        }
    }
    network_interface {
        network = "default"
        access_config {}
    }
}
```

Для выполнения планирования изменений запустим команду `terraform plan` в директории `terraform`.

Для запуска инстанса , описание характеристик которого было описано в конфигурационном файле `main.cf` команду:

```
$ terraform apply

An execution plan has been generated and is shown below.
Resource actions are indicated with the following symbols:
  + create

Terraform will perform the following actions:

  # google_compute_instance.app will be created
  + resource "google_compute_instance" "app" {
      + can_ip_forward       = false
      + cpu_platform         = (known after apply)
      + deletion_protection  = false
      + guest_accelerator    = (known after apply)
      + id                   = (known after apply)
      + instance_id          = (known after apply)
      + label_fingerprint    = (known after apply)
      + machine_type         = "g1-small"
      + metadata_fingerprint = (known after apply)
      + name                 = "reddit-map"
      + project              = (known after apply)
      + self_link            = (known after apply)
      + tags_fingerprint     = (known after apply)
      + zone                 = "europe-west1-d"

      + boot_disk {
          + auto_delete                = true
          + device_name                = (known after apply)
          + disk_encryption_key_sha256 = (known after apply)
          + kms_key_self_link          = (known after apply)
          + mode                       = "READ_WRITE"
          + source                     = (known after apply)

          + initialize_params {
              + image  = "reddit-full-1606586549"
              + labels = (known after apply)
              + size   = (known after apply)
              + type   = (known after apply)
            }
        }

      + network_interface {
          + address            = (known after apply)
          + name               = (known after apply)
          + network            = "default"
          + network_ip         = (known after apply)
          + subnetwork         = (known after apply)
          + subnetwork_project = (known after apply)

          + access_config {
              + assigned_nat_ip = (known after apply)
              + nat_ip          = (known after apply)
              + network_tier    = (known after apply)
            }
        }

      + scheduling {
          + automatic_restart   = (known after apply)
          + on_host_maintenance = (known after apply)
          + preemptible         = (known after apply)

          + node_affinities {
              + key      = (known after apply)
              + operator = (known after apply)
              + values   = (known after apply)
            }
        }
    }

Plan: 1 to add, 0 to change, 0 to destroy.

Do you want to perform these actions?
  Terraform will perform the actions described above.
  Only 'yes' will be accepted to approve.

  Enter a value: yes

google_compute_instance.app: Creating...
google_compute_instance.app: Still creating... [10s elapsed]
google_compute_instance.app: Still creating... [20s elapsed]
google_compute_instance.app: Creation complete after 29s [id=reddit-map]

Apply complete! Resources: 1 added, 0 changed, 0 destroyed.
```

Для отображения внешнего IP адреса созданного инстанса, выполним команду:

```
$ terraform show | grep nat_ip
            nat_ip       = "35.195.208.148"
```

Добавим ключ SSH для доступа к серверу. Для этого внесем изменения в файл `main.tf`

```
...
    metadata = {
        # Путь до публичного ключа
        ssh-keys = "rmartsev:${file("~/.ssh/rmartsev_rsa.pub")}"
    }
...
```

Применим добавленные изменения командой `terraform apply`. Уже созданный инстанс при этом не будет удален и создан заново.

Для облегчения получения информации об инстансах вынесем интересующую информацию в выходные переменные.

Чтобы не мешать выходные переменные с основной конфигурацией наших ревурсов, создадим их в отдельном файле, который назовем `output.tf`. Добавим в него переменную, содержащую внешний IP адрес инстанса:

```
output "app_external-ip" {
    value="${google_compute_instance.app.network_interface[0].access_config[0].nat_ip}"
}
```

Для присвоения значения переменной выполним команду `terraform refresh`. Значения выводных переменных можно посмотреть командой `terraform output`.

Создадим правило сетевого экрана, для этого добавим ресурс в файл main.tf:

```
resource "google_compute_firewall" "firewall_puma" {
    name = "allow-puma-default"
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
    target_tags = ["reddit-app"]
}
```

Планируем и применяем изменения

```
$ terraform plan
$ terraform apply
```

Правило сетевого экрана применимо к инстансам с тэгом `reddit-app`. Чтобы применить данное правило к созданному инстансу, присвоим ему необходимую метку. Для этого внесем изменения в файл `main.tf`:

```
...
resource "google_compute_instance" "app" {
...
    tags = ["reddit-app"]
...
}
...
```

Выполняем `terraform plan` и `terraform apply`.

Добавим провижинер, позволяющий копировать содержимое файла на удаленную машину

```
provisioner "file" {
    source = "files/puma.service"
    destination = "/tmp/puma.service"
}
```

Данный провижинер копирует файл `files/puma.service` в директорию `/tmp/`.

Сщдержимое файла `files/puma.service`:

```
[Unit]
Description=Puma HTTP Server
After=network.target

[Service]
Type=simple
User=rmartsev
WorkingDirectory=/home/rmartsev/reddit
ExecStart=/usr/bin/ruby -lv '/usr/local/bin/puma'
Restart=always

[Install]
WantedBy=multi-user.target
```

Добавим еще провижинер для удаленного запуска скрипта `files/deploy.sh`

```
provisioner "remote-exec" {
    script = "files/deploy.sh"
}
```

Содержимое файла `files/deploy.sh`:

```
#!/bin/bash
set -e

APP_DIR=${1:-$HOME}

git clone -b monolith https://github.com/express42/reddit.git $APP_DIR/reddit
cd $APP_DIR/reddit
bundle install

sudo mv /tmp/puma.service /etc/systemd/system/puma.service
sudo systemctl start puma
sudo systemctl enable puma
```

Определим параметры подключения провиженеров к VM. Внутрь ресурса VM, перед определением провижинеров, добавbv следующую секцию

```
connection {
  type = "ssh"
  # host = self.network_interface[0].access_config[0].nat_ip
  user = "appuser"
  agent = false
  # путь до приватного ключа
  private_key = file("~/.ssh/appuser")
}
```

По умолчанию провижинеры запускаются сразу после создания ресурса, поэтому чтобы проверить их работу, ресурс необхоидмо пересоздать. Для этого используем команду отметки ресурса для пересоздания, и применим изменения.

```
$ terraform taint google_compute_instance.app
$ terraform plan
$ terraform apply
```

Проверим работоспособность ресурса, перейдя по адресу в браузере: http://<external-ip>:9292

Для параметризации конфигурационного файла есть возможность использовать входные переменные. Для этого созданим конфигурационный файл `variables.tf`:

```
variable project {
  description = "Project ID"
}
variable region {
  description = "Region"
  # Значение по умолчанию
  default = "europe-west1"
}
variable public_key_path {
  # Описание переменной
  description = "Path to the public key used for ssh access"
}
variable disk_image {
  description = "Disk image"
}
```

Внесем изменения в файл `main.tf`, заменив значения переменными:

```
...
provider "google" {
    version = "2.15.0"
    project = var.project
    region = var.region
}
...
...
boot_disk {
    initialize_params {
        image = var.disk_image
    }
}
...
metadata = {
    ssh-keys = "rmartsev:${file(var.public_key_path)}"
}
...
```

Теперь определим переменные в файле `terraform.tfvars`:

```
project = "infra-296308"
public_key_path = "~/.ssh/rmartsev_rsa.pub"
disk_image = "reddit-base-1606657180"
```

# Создание правила для SSH доступа

В файле `main.tf` добавим ресурс сетевого экрана для 22 порта TCP:

```
...
resource "google_compute_firewall" "firewall_ssh" {
  name = "default-allow-ssh"
  network = "default"

  allow {
    protocol = "tcp"
    ports = ["22"]
  }

  source_ranges = ["0.0.0.0/0"]
}
...
```

Т.к terraform ничего не знает о существующем правиле файервола (а всю информацию, об известных ему ресурсах, он хранит в state файле), то при выполнении команды apply terraform пытается создать новое правило файервола. Для того чтобы сказать terraform-у не создавать новое правило, а управлять уже имеющимся, в его "записную книжку" (state файл) о всех ресурсах, которыми он управляет, нужно занести информацию о существующем правиле.

Команда import позволяет добавить информацию о созданном без помощи Terraform ресурсе в state файл. В директории terraform выполните команду:

```
$ terraform import google_compute_firewall.firewall_ssh default-allow-ssh
google_compute_firewall.firewall_ssh: Importing from ID "default-allow-ssh"...
google_compute_firewall.firewall_ssh: Import prepared!
  Prepared google_compute_firewall for import
google_compute_firewall.firewall_ssh: Refreshing state... [id=default-allow-ssh]

Import successful!
```

# Ресурс IP адреса

Зададим IP для инстанса с приложением в виде внешнего ресурса. Для этого определим ресурс google_compute_address в конфигурационном файле main.tf.

```
...
resource "google_compute_address" "app_ip" {
  name = "reddit-app-ip"
}
...
```

Для того чтобы использовать созданный IP адрес в нашем ресурсе VM нам необходимо сослаться на атрибуты ресурса, который этот IP создает, внутри конфигурации ресурса VM. В конфигурации ресурса VM определите, IP адрес для создаваемого инстанса.

```
...
network_interface {
 network = "default"
 access_config {
   nat_ip = google_compute_address.app_ip.address
 }
}
...
```

# Разделение конфигурации для создания двух VM

Создадим файл `app.tf`, куда вынесем конфигурацию для VM с приложением

```
resource "google_compute_instance" "app" {
  name = "reddit-app"
  machine_type = "g1-small"
  zone = var.zone
  tags = ["reddit-app"]
  boot_disk {
    initialize_params { image = var.app_disk_image }
  }
  network_interface {
    network = "default"
    access_config {
      nat_ip = google_compute_address.app_ip.address
    }
  }
  metadata {
    ssh-keys = "appuser:${file(var.public_key_path)}"
  }
}

resource "google_compute_address" "app_ip" { 
  name = "reddit-app-ip" 
}

resource "google_compute_firewall" "firewall_puma" {
  name = "allow-puma-default"
  network = "default"
  allow {
    protocol = "tcp", ports = ["9292"]
  }
  source_ranges = ["0.0.0.0/0"]
  target_tags = ["reddit-app"]
}
```

а также добавим переменную `app_disk_image` в файл `variables.tf`:

```
...
variable app_disk_image {
  description = "Disk image for reddit app"
  default = "reddit-app-base"
}
...
```

Создадим файл `db.tf` для инстанса базы данных

```
resource "google_compute_instance" "db" {
  name = "reddit-db"
  machine_type = "g1-small"
  zone = var.zone
    tags = ["reddit-db"]
    boot_disk {
    initialize_params {
      image = var.db_disk_image
    }
  }
  network_interface {
    network = "default"
    access_config = {}
  }
  metadata {
    ssh-keys = "appuser:${file(var.public_key_path)}"
  }
}

resource "google_compute_firewall" "firewall_mongo" {
  name = "allow-mongo-default"
  network = "default"
  allow {
    protocol = "tcp"
    ports = ["27017"]
  }
  target_tags = ["reddit-db"]
  source_tags = ["reddit-app"]
}
```

а также добавим переменную `db_disk_image` в файл `variables.tf`

```
...
variable db_disk_image {
description = "Disk image for reddit db"
default = "reddit-db-base"
}
...
```

Вынесем правила сетевого экрана в файл `vpc.tf`

```
resource "google_compute_firewall" "firewall_ssh" {
  name = "default-allow-ssh"
  network = "default"
  allow {
    protocol = "tcp"
    ports = ["22"]
  }
  source_ranges = ["0.0.0.0/0"]
}
```

В итоге в файле `main.tf` должно остаться только определение провайдера:

```
provider "google" {
  version = "~> 2.15"
  project = var.project
  region = var.region
}
```

# Работа с модулями

Создадим директорию `terraform/modules/db`, в которой создадим файлы: `main.tf`, `variables.tf`, `outputs.tf`.

Скопируем файл `terraform/db.tf` в файл `terraform/modules/db/main.tf`.

Файл `terraform/modiles/db/variables.tf` приведем к виду:

```
variable public_key_path {
  description = "Path to the public key used to connect to instance"
}

variable zone {
  description = "Zone"
}

variable db_disk_image {
  description = "Disk image for reddit db"
  default     = "reddit-db-base"
}
```

По аналогии создадим директорию `terraform/modules/app` и необходимые файлы в ней.

Для использования модулей удалим файлы `terraform/app.tf` и `terraform/db.tf` и дополним файл `terraform/main.tf` содержимым:

```
module "app" {
  source          = "./modules/app"
  public_key_path = var.public_key_path
  zone            = var.zone
  app_disk_image  = var.app_disk_image
}

module "db" {
  source          = "./modules/db"
  public_key_path = var.public_key_path
  zone            = var.zone
  db_disk_image   = var.db_disk_image
}
```

После этого необходимо загрузить модули из указанных источников командой

```
$ terraform get
```

Информация о модулях будет загружена в директорию .terraform, в которой уже содержится провайдер.

```
$ tree .terraform 
.terraform
├── modules
│   └── modules.json
└── plugins
    ├── registry.terraform.io
    │   └── hashicorp
    │       └── google
    │           └── 2.15.0
    │               └── darwin_amd64
    │                   └── terraform-provider-google_v2.15.0_x4
    └── selections.json

7 directories, 3 files

$ cat .terraform/modules/modules.json 
{"Modules":[{"Key":"","Source":"","Dir":"."},{"Key":"app","Source":"./modules/app","Dir":"modules/app"},{"Key":"db","Source":"./modules/db","Dir":"modules/db"}]}
```


