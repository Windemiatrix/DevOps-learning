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

Уничтожим созданные инстансы командой `terraform destroy`, затем создадим их заново командами `terraform plan` и `terraform apply`.

# Ansible

Создадим директорию `ansible`, а в ней файл `requirements.txt` со следующим содержимым:

```
ansible>=2.4
```

Перейдем в созданную директорию и установим `ansible`:

```
$ pip install -r requirements.txt
```

Официальная документация по установке `ansinle`: https://docs.ansible.com/ansible/latest/intro_installation.html

Запустим виртуальные машины, описанные ранее, с помощью терраформ, используя команду `terraform apply`.

Хосты и группы хостов, которыми Ansible должен управлять, описываются в инвентори-файле. Создадим инвентори файл `ansible/inventory`, в котором укажем информацию о созданном инстансе приложения и параметры подключения к нему по SSH:

```
appserver ansible_host=34.76.39.102 ansible_user=rmartsev ansible_private_key_file=~/.ssh/rmartsev_rsa
```

где `appserver` - краткое имя, которое идентифицирует данный хост.

Убедимся, что Ansible может управлять нашим хостом. Используем команду ansible для вызова модуля ping из командной строки.

```
$ ansible appserver -i ./inventory -m ping
appserver | SUCCESS => {
    "ansible_facts": {
        "discovered_interpreter_python": "/usr/bin/python"
    },
    "changed": false,
    "ping": "pong"
}
```

Ping-модуль позволяет протестировать SSH-соединение, при этом ничего не изменяя на самом хосте.\
`-m ping` - вызываемый модуль\
`-i ./inventory` - путь до файла инвентори appserver - Имя хоста, которое указали в инвентори, откуда Ansible yзнает, как подключаться к хосту вывод команды:

```
$ ansible appserver -i ./inventory -m ping
appserver | SUCCESS => {
"changed": false,
"ping": "pong"
}
```

Добавим в файл `inventory` информацию о сервере базы данных:

```
...
dbserver ansible_host=104.155.107.160 ansible_user=rmartsev ansible_private_key_file=~/.ssh/rmartsev_rsa
```

И проверим доступность сервера:

```
$ ansible dbserver -i inventory -m ping
dbserver | SUCCESS => {
    "ansible_facts": {
        "discovered_interpreter_python": "/usr/bin/python"
    },
    "changed": false,
    "ping": "pong"
}
```

Создадим файл `ansible.cfg` для установки значений по умолчанию для работы `Ansible`, чтобы сократить в дальнейшем количество настроек, в том числе, в файле `inventory`.

```
[defaults]
inventory = ./inventory
remote_user = rmartsev
private_key_file = ~/.ssh/rmartsev_rsa
host_key_checking = False
retry_files_enabled = False
ansible_python_interpreter=auto
interpreter_python=auto
```

Теперь мы можем удалить избыточную информацию из файла inventory и использовать значения по умолчанию:

```
appserver ansible_host=34.76.39.102
dbserver ansible_host=104.155.107.160
```

Ansible может выполнять отдельные команды на инстансах. Например, можно посмотреть uptime следующим образом:

```
$ ansible dbserver -m command -a uptime
dbserver | CHANGED | rc=0 >>
 14:55:29 up 36 min,  1 user,  load average: 0.00, 0.00, 0.00
```

Изменим файл `inventory` для работы с группами хостов:

```
[app] # ⬅ Это название группы
appserver ansible_host=34.76.39.102 # ⬅ Cписок хостов в данной группе
[db]
dbserver ansible_host=104.155.107.160
```

Теперь мы можем управлять не отдельными хостами, а целыми группами, ссылаясь на имя группы:

```
$ ansible app -m ping
appserver | SUCCESS => {
    "ansible_facts": {
        "discovered_interpreter_python": "/usr/bin/python3"
    },
    "changed": false,
    "ping": "pong"
}
```

Перепишем файл `inventory` в формате YML и сохраним в файл `inventory.yml`:

```
all:
  children:
    app:
      hosts:
        appserver:
          ansible_host: 34.76.39.102
    db:
      hosts:
        dbserver:
          ansible_host: 104.155.107.160
```

Для проверки выполним например следующую команду. Ключ -i переопределяет путь к инвентори файлу.

```
ansible all -m ping -i inventory.yml
dbserver | SUCCESS => {
    "ansible_facts": {
        "discovered_interpreter_python": "/usr/bin/python3"
    },
    "changed": false,
    "ping": "pong"
}
appserver | SUCCESS => {
    "ansible_facts": {
        "discovered_interpreter_python": "/usr/bin/python3"
    },
    "changed": false,
    "ping": "pong"
}
```

Проверим, что на app сервере установлены компоненты для работы приложения (ruby и bundler):

```
$ ansible app -m command -a 'ruby -v'
appserver | CHANGED | rc=0 >>
ruby 2.3.1p112 (2016-04-26) [x86_64-linux-gnu]
$ ansible app -m command -a 'bundler -v'
appserver | CHANGED | rc=0 >>
Bundler version 1.11.2
```

А теперь попробуем указать две команды модулю command:

```
ansible app -m command -a 'ruby -v; bundler -v'
appserver | FAILED | rc=1 >>
ruby: invalid option -;  (-h will show valid options) (RuntimeError)non-zero return code
```

В то же время модуль shell успешно отработает:

```
ansible app -m shell -a 'ruby -v; bundler -v'
appserver | CHANGED | rc=0 >>
ruby 2.3.1p112 (2016-04-26) [x86_64-linux-gnu]
Bundler version 1.11.2
```

Модуль command выполняет команды, не используя оболочку (sh, bash), поэтому в нем не работают перенаправления потоков и нет доступа к некоторым переменным окружения.

Проверим на хосте с БД статус сервиса MongoDB с помощью модуля command или shell.

```
$ ansible db -m command -a 'systemctl status mongod'
dbserver | CHANGED | rc=0 >>
● mongod.service - High-performance, schema-free document-oriented database
   Loaded: loaded (/lib/systemd/system/mongod.service; enabled; vendor preset: enabled)
   Active: active (running) since Sun 2020-12-06 14:18:53 UTC; 52min ago
     Docs: https://docs.mongodb.org/manual
 Main PID: 1386 (mongod)
    Tasks: 19
   Memory: 52.3M
      CPU: 13.831s
   CGroup: /system.slice/mongod.service
           └─1386 /usr/bin/mongod --quiet --config /etc/mongod.conf

Dec 06 14:18:53 reddit-db systemd[1]: Started High-performance, schema-free document-oriented database.
$ ansible db -m shell -a 'systemctl status mongod'
dbserver | CHANGED | rc=0 >>
● mongod.service - High-performance, schema-free document-oriented database
   Loaded: loaded (/lib/systemd/system/mongod.service; enabled; vendor preset: enabled)
   Active: active (running) since Sun 2020-12-06 14:18:53 UTC; 52min ago
     Docs: https://docs.mongodb.org/manual
 Main PID: 1386 (mongod)
    Tasks: 19
   Memory: 52.3M
      CPU: 13.867s
   CGroup: /system.slice/mongod.service
           └─1386 /usr/bin/mongod --quiet --config /etc/mongod.conf

Dec 06 14:18:53 reddit-db systemd[1]: Started High-performance, schema-free document-oriented database.
```

А можем выполнить ту же операцию используя модуль systemd, который предназначен для управления сервисами:

```
$ ansible db -m systemd -a name=mongod
dbserver | SUCCESS => {
    "ansible_facts": {
        "discovered_interpreter_python": "/usr/bin/python3"
    },
    "changed": false,
    "name": "mongod",
    "status": {
        "ActiveEnterTimestamp": "Sun 2020-12-06 14:18:53 UTC",
        "ActiveEnterTimestampMonotonic": "8283704",
        "ActiveExitTimestampMonotonic": "0",
        "ActiveState": "active",
...
```


