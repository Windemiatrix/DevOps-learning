# Вступление

Домашнее задание по сборке образов VM при помощи Packer и Terraform

# Настройка авторизации Packer и Terraform в GCP

Создадим ADC:

``` bash
gcloud auth application-default login
```

# Создание шаблона Packer

Для шаблона создадим директорию `packer` и создадим пустой файл `ubuntu16.json`, который будет шаблоном для VM.

``` bash
mkdir packer
touch ./packer/ubuntu16.json
```

Заполним файл информацией о создании виртуальной машины для билда и создании машинного образа (блок `builders`):

``` json
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

``` json
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

``` bash
cp config-scripts/install_mongodb.sh packer/scripts
cp config-scripts/install_ruby.sh packer/scripts
```

Проверим на наличие ошибок подготовленную конфигурацию, исправим их при наличии и запустим создание образа

``` bash
packer validate ubuntu16.json
packer build -var-file=variables.json ubuntu16.json
```

Образ успешно создан.

# Деплой тестового приложения с помощью инстанса

Создадим VM через веб-интерфейс GCP, в качестве образа системы указав созданный образ.

# Установка зависимостей и запуск приложения

``` bash
git clone -b monolith https://github.com/express42/reddit.git
cd reddit/
bundle install
puma -d
```

Проверяем, запуск сервера

``` bash
$ ps aux | grep puma
rmartsev  2687  2.1  1.3 515400 26720 ?        Sl   19:43   0:00 puma 3.10.0 (tcp://0.0.0.0:9292) [reddit]
rmartsev  2701  0.0  0.0  12944  1004 pts/0    S+   19:43   0:00 grep --color=auto puma
```

Добавим установку и запуск `puma` в образ. Для этого подготовим файл `immutable.json`:

``` json
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

``` ini
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

``` bash
packer build -var-file=variables.json immutable.json
```

# Terraform

Создаем директорию `terraform` для создания в ней конфигурации.

Файл `main.tf` содержит основные настройка Terraform.

Секция `Provider` позволяет Terraform управлять ресурсами GCP через API вызовы.

``` terraform
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

``` bash
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

``` terraform
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

``` bash
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

``` bash
$ terraform show | grep nat_ip
            nat_ip       = "35.195.208.148"
```

Добавим ключ SSH для доступа к серверу. Для этого внесем изменения в файл `main.tf`

``` terraform
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

``` terraform
output "app_external-ip" {
    value="${google_compute_instance.app.network_interface[0].access_config[0].nat_ip}"
}
```

Для присвоения значения переменной выполним команду `terraform refresh`. Значения выводных переменных можно посмотреть командой `terraform output`.

Создадим правило сетевого экрана, для этого добавим ресурс в файл main.tf:

``` terraform
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

``` bash
terraform plan
terraform apply
```

Правило сетевого экрана применимо к инстансам с тэгом `reddit-app`. Чтобы применить данное правило к созданному инстансу, присвоим ему необходимую метку. Для этого внесем изменения в файл `main.tf`:

``` terraform
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

``` terraform
provisioner "file" {
    source = "files/puma.service"
    destination = "/tmp/puma.service"
}
```

Данный провижинер копирует файл `files/puma.service` в директорию `/tmp/`.

Сщдержимое файла `files/puma.service`:

``` ini
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

``` terraform
provisioner "remote-exec" {
    script = "files/deploy.sh"
}
```

Содержимое файла `files/deploy.sh`:

``` bash
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

``` terraform
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

``` bash
terraform taint google_compute_instance.app
terraform plan
terraform apply
```

Проверим работоспособность ресурса, перейдя по адресу в браузере: http://<external-ip>:9292

Для параметризации конфигурационного файла есть возможность использовать входные переменные. Для этого созданим конфигурационный файл `variables.tf`:

``` terraform
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

``` terraform
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

``` terraform
project = "infra-296308"
public_key_path = "~/.ssh/rmartsev_rsa.pub"
disk_image = "reddit-base-1606657180"
```

Уничтожим созданные инстансы командой `terraform destroy`, затем создадим их заново командами `terraform plan` и `terraform apply`.

# Ansible

Создадим директорию `ansible`, а в ней файл `requirements.txt` со следующим содержимым:

``` ansible
ansible>=2.4
```

Перейдем в созданную директорию и установим `ansible`:

``` bash
pip install -r requirements.txt
```

Официальная документация по установке `ansinle`: https://docs.ansible.com/ansible/latest/intro_installation.html

Запустим виртуальные машины, описанные ранее, с помощью терраформ, используя команду `terraform apply`.

Хосты и группы хостов, которыми Ansible должен управлять, описываются в инвентори-файле. Создадим инвентори файл `ansible/inventory`, в котором укажем информацию о созданном инстансе приложения и параметры подключения к нему по SSH:

``` bash
appserver ansible_host=34.76.39.102 ansible_user=rmartsev ansible_private_key_file=~/.ssh/rmartsev_rsa
```

где `appserver` - краткое имя, которое идентифицирует данный хост.

Убедимся, что Ansible может управлять нашим хостом. Используем команду ansible для вызова модуля ping из командной строки.

``` bash
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

``` bash
$ ansible appserver -i ./inventory -m ping
appserver | SUCCESS => {
"changed": false,
"ping": "pong"
}
```

Добавим в файл `inventory` информацию о сервере базы данных:

``` bash
...
dbserver ansible_host=104.155.107.160 ansible_user=rmartsev ansible_private_key_file=~/.ssh/rmartsev_rsa
```

И проверим доступность сервера:

``` bash
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

``` ini
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

``` bash
appserver ansible_host=34.76.39.102
dbserver ansible_host=104.155.107.160
```

Ansible может выполнять отдельные команды на инстансах. Например, можно посмотреть uptime следующим образом:

``` bash
$ ansible dbserver -m command -a uptime
dbserver | CHANGED | rc=0 >>
 14:55:29 up 36 min,  1 user,  load average: 0.00, 0.00, 0.00
```

Изменим файл `inventory` для работы с группами хостов:

``` ini
[app] # ⬅ Это название группы
appserver ansible_host=34.76.39.102 # ⬅ Cписок хостов в данной группе
[db]
dbserver ansible_host=104.155.107.160
```

Теперь мы можем управлять не отдельными хостами, а целыми группами, ссылаясь на имя группы:

``` bash
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

``` yml
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

``` bash
$ ansible all -m ping -i inventory.yml
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

``` bash
$ ansible app -m command -a 'ruby -v'
appserver | CHANGED | rc=0 >>
ruby 2.3.1p112 (2016-04-26) [x86_64-linux-gnu]
$ ansible app -m command -a 'bundler -v'
appserver | CHANGED | rc=0 >>
Bundler version 1.11.2
```

А теперь попробуем указать две команды модулю command:

``` bash
$ ansible app -m command -a 'ruby -v; bundler -v'
appserver | FAILED | rc=1 >>
ruby: invalid option -;  (-h will show valid options) (RuntimeError)non-zero return code
```

В то же время модуль shell успешно отработает:

``` bash
$ ansible app -m shell -a 'ruby -v; bundler -v'
appserver | CHANGED | rc=0 >>
ruby 2.3.1p112 (2016-04-26) [x86_64-linux-gnu]
Bundler version 1.11.2
```

Модуль command выполняет команды, не используя оболочку (sh, bash), поэтому в нем не работают перенаправления потоков и нет доступа к некоторым переменным окружения.

Проверим на хосте с БД статус сервиса MongoDB с помощью модуля command или shell.

``` bash
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

``` bash
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

# Ansible 2

## Один плейбук, один сценарий

Создадим файл `ansible/reddit_app.yml`:

``` yml
---
- name: Configure hosts & deploy application # <-- Словесное описание сценария (name)
  hosts: all # <-- Для каких хостов будут выполняться описанные ниже таски (hosts)

  tasks: # <-- Блок тасков (заданий), которые будут выполняться для данных хостов
  - name: Change mongo config file
    become: true # <-- Выполнить задание от root
    template:
      src: templates/mongod.conf.j2 # <-- Путь до локального файла-шаблона
      dest: /etc/mongod.conf # <-- Путь на удаленном хосте
      mode: 0644 # <-- Права на файл, которые нужно установить
    tags: db-tag # <-- Список тэгов для задачи
```

Создадим файл `ansible/templates/mongod.conf.j2`:

``` jinja2
# Where and how to store data.
storage:
  dbPath: /var/lib/mongodb
  journal:
    enabled: true

# where to write logging data.
systemLog:
  destination: file
  logAppend: true
  path: /var/log/mongodb/mongod.log

# network interfaces
net:
  port: {{ mongo_port | default('27017') }}
  bindIp: {{ mongo_bind_ip }}
```

Проверим корректность составления плейбука командой

``` bash
$ ansible-playbook reddit_app.yml --check --limit db

PLAY [Configure hosts & deploy application] *************************************************************************************************************************************************************************************

TASK [Gathering Facts] **********************************************************************************************************************************************************************************************************
ok: [dbserver]

TASK [Change mongo config file] *************************************************************************************************************************************************************************************************
fatal: [dbserver]: FAILED! => {"changed": false, "msg": "AnsibleUndefinedVariable: 'mongo_bind_ip' is undefined"}

PLAY RECAP **********************************************************************************************************************************************************************************************************************
dbserver                   : ok=1    changed=0    unreachable=0    failed=1    skipped=0    rescued=0    ignored=0   
```

Не определена переменная, исправим ошибку. Внесем изменения в файл `ansible/reddit_app.yml`:

``` yml
---
- name: Configure hosts & deploy application # <-- Словесное описание сценария (name)
  hosts: all # <-- Для каких хостов будут выполняться описанные ниже таски (hosts)
  vars:
    mongo_bind_ip: 0.0.0.0 # <-- Переменная задается в блоке vars

  tasks: # <-- Блок тасков (заданий), которые будут выполняться для данных хостов
  - name: Change mongo config file
    become: true # <-- Выполнить задание от root
    template:
      src: templates/mongod.conf.j2 # <-- Путь до локального файла-шаблона
      dest: /etc/mongod.conf # <-- Путь на удаленном хосте
      mode: 0644 # <-- Права на файл, которые нужно установить
    tags: db-tag # <-- Список тэгов для задачи
```

Повторим проверку:

``` bash
ansible-playbook reddit_app.yml --check --limit db

PLAY [Configure hosts & deploy application] *************************************************************************************************************************************************************************************

TASK [Gathering Facts] **********************************************************************************************************************************************************************************************************
ok: [dbserver]

TASK [Change mongo config file] *************************************************************************************************************************************************************************************************
changed: [dbserver]

PLAY RECAP **********************************************************************************************************************************************************************************************************************
dbserver                   : ok=2    changed=1    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0   
```

Определим handler для рестарта БД и добавим вызов handler-а в созданный нами таск. Файл `ansible/reddit_app.yml`:

``` yml
---
- name: Configure hosts & deploy application # <-- Словесное описание сценария (name)
  hosts: all # <-- Для каких хостов будут выполняться описанные ниже таски (hosts)
  vars:
    mongo_bind_ip: 0.0.0.0 # <-- Переменная задается в блоке vars

  tasks: # <-- Блок тасков (заданий), которые будут выполняться для данных хостов
  - name: Change mongo config file
    become: true # <-- Выполнить задание от root
    template:
      src: templates/mongod.conf.j2 # <-- Путь до локального файла-шаблона
      dest: /etc/mongod.conf # <-- Путь на удаленном хосте
      mode: 0644 # <-- Права на файл, которые нужно установить
    tags: db-tag # <-- Список тэгов для задачи
    notify: restart mongod

  handlers: # <-- Добавим блок handlers и задачу
  - name: restart mongod
    become: true
    service: name=mongod state=restarted
```

Сделаем проверку изменений:

``` bash
ansible-playbook reddit_app.yml --check --limit db

PLAY [Configure hosts & deploy application] **********************************************************************

TASK [Gathering Facts] *******************************************************************************************
ok: [dbserver]

TASK [Change mongo config file] **********************************************************************************
changed: [dbserver]

RUNNING HANDLER [restart mongod] *********************************************************************************
changed: [dbserver]

PLAY RECAP *******************************************************************************************************
dbserver                   : ok=3    changed=2    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0   
```

Запустим плейбук:

``` bash
$ ansible-playbook reddit_app.yml --limit db

PLAY [Configure hosts & deploy application] **********************************************************************

TASK [Gathering Facts] *******************************************************************************************
ok: [dbserver]

TASK [Change mongo config file] **********************************************************************************
changed: [dbserver]

RUNNING HANDLER [restart mongod] *********************************************************************************
changed: [dbserver]

PLAY RECAP *******************************************************************************************************
dbserver                   : ok=3    changed=2    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0   
```

Созддим файл `ansible/files/puma.service`:

``` ini
[Unit]
Description=Puma HTTP Server
After=network.target

[Service]
Type=simple
EnvironmentFile=/home/appuser/db_config
User=appuser
WorkingDirectory=/home/appuser/reddit
ExecStart=/bin/bash -lc 'puma'
Restart=always

[Install]
WantedBy=multi-user.target
```

Добавим в наш сценарий таск для копирования unit-файла на хост приложения. Для копирования простого файла на удаленный хост, используем модуль copy, а для настройки автостарта Puma-сервера используем модуль systemd.

Добавим новый handler, который укажет systemd, что unit для сервиса изменился и его следует перечитать:

Файл `ansible/reddit_app.yml`:

``` yml
---
- name: Configure hosts & deploy application # <-- Словесное описание сценария (name)
  hosts: all # <-- Для каких хостов будут выполняться описанные ниже таски (hosts)
  vars:
    mongo_bind_ip: 0.0.0.0 # <-- Переменная задается в блоке vars

  tasks: # <-- Блок тасков (заданий), которые будут выполняться для данных хостов
  - name: Change mongo config file
    become: true # <-- Выполнить задание от root
    template:
      src: templates/mongod.conf.j2 # <-- Путь до локального файла-шаблона
      dest: /etc/mongod.conf # <-- Путь на удаленном хосте
      mode: 0644 # <-- Права на файл, которые нужно установить
    tags: db-tag # <-- Список тэгов для задачи
    notify: restart mongod

  - name: Add unit file for Puma
    become: true
    copy:
      src: files/puma.service
      dest: /etc/systemd/system/puma.service
    tags: app-tag
    notify: reload puma

  - name: enable puma
    become: true
    systemd: name=puma enabled=yes
    tags: app-tag

  handlers: # <-- Добавим блок handlers и задачу
  - name: restart mongod
    become: true
    service: name=mongod state=restarted

  - name: reload puma
    become: true
    systemd: name=puma state=restarted
```

unit-файл для вебсервера изменился. В него добавилась строка чтения переменных окружения из файла:

``` ini
EnvironmentFile=/home/appuser/db_config
```

Через переменную окружения мы будем передавать адрес инстанса БД, чтобы приложение знало, куда ему обращаться для хранения данных.

Создадим шаблон в директории `templates/db_config.j2` куда добавим следующую строку:

``` jinja2
DATABASE_URL={{ db_host }}
```

Как видим, данный шаблон содержит присвоение переменной `DATABASE_URL` значения, которое мы передаем через Ansible переменную `db_host`.

Добавим таск для копирования созданного шаблона и определим переменную. Файл `ansible/reddit_app.yml`:

IP адрес базы данных можно подсмотреть в `terraform` командой

``` bash
$ terraform show
...
Outputs:

app_external_ip = "34.76.39.102"
db_external_ip = "104.155.107.160"
```

``` yml
---
- name: Configure hosts & deploy application # <-- Словесное описание сценария (name)
  hosts: all # <-- Для каких хостов будут выполняться описанные ниже таски (hosts)
  vars:
    mongo_bind_ip: 0.0.0.0 # <-- Переменная задается в блоке vars
    db_host: 104.155.107.160 # <-- подставьте сюда ваш IP

  tasks: # <-- Блок тасков (заданий), которые будут выполняться для данных хостов
  - name: Change mongo config file
    become: true # <-- Выполнить задание от root
    template:
      src: templates/mongod.conf.j2 # <-- Путь до локального файла-шаблона
      dest: /etc/mongod.conf # <-- Путь на удаленном хосте
      mode: 0644 # <-- Права на файл, которые нужно установить
    tags: db-tag # <-- Список тэгов для задачи
    notify: restart mongod

  - name: Add unit file for Puma
    become: true
    copy:
      src: files/puma.service
      dest: /etc/systemd/system/puma.service
    tags: app-tag
    notify: reload puma

  - name: Add config for DB connection
    template:
      src: templates/db_config.j2
      dest: /home/rmartsev/db_config
    tags: app-tag

  - name: enable puma
    become: true
    systemd: name=puma enabled=yes
    tags: app-tag

  handlers: # <-- Добавим блок handlers и задачу
  - name: restart mongod
    become: true
    service: name=mongod state=restarted

  - name: reload puma
    become: true
    systemd: name=puma state=restarted
```

Сделаем проверку конфигурации:

``` bash
$ ansible-playbook reddit_app.yml --check --limit app --tags app-tag

PLAY [Configure hosts & deploy application] **********************************************************************

TASK [Gathering Facts] *******************************************************************************************
ok: [appserver]

TASK [Add unit file for Puma] ************************************************************************************
changed: [appserver]

TASK [Add config for DB connection] ******************************************************************************
changed: [appserver]

TASK [enable puma] ***********************************************************************************************
ok: [appserver]

RUNNING HANDLER [reload puma] ************************************************************************************
changed: [appserver]

PLAY RECAP *******************************************************************************************************
appserver                  : ok=5    changed=3    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0   
```

Выполним плейбук:

``` bash
ansible-playbook reddit_app.yml --limit app --tags app-tag

PLAY [Configure hosts & deploy application] **********************************************************************

TASK [Gathering Facts] *******************************************************************************************
ok: [appserver]

TASK [Add unit file for Puma] ************************************************************************************
ok: [appserver]

TASK [Add config for DB connection] ******************************************************************************
changed: [appserver]

TASK [enable puma] ***********************************************************************************************
ok: [appserver]

PLAY RECAP *******************************************************************************************************
appserver                  : ok=4    changed=1    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0   
```

Добавим еще несколько тасков в сценарий нашего плейбука. Используем модули git и bundle для клонирования последней версии кода нашего приложения и установки зависимых Ruby Gems через bundle.

Файл `ansible/reddit_app.yml`:

``` yml
---
- name: Configure hosts & deploy application # <-- Словесное описание сценария (name)
  hosts: all # <-- Для каких хостов будут выполняться описанные ниже таски (hosts)
  vars:
    mongo_bind_ip: 0.0.0.0 # <-- Переменная задается в блоке vars
    db_host: 104.155.107.160 # <-- подставьте сюда ваш IP

  tasks: # <-- Блок тасков (заданий), которые будут выполняться для данных хостов
  
  - name: Change mongo config file
    become: true # <-- Выполнить задание от root
    template:
      src: templates/mongod.conf.j2 # <-- Путь до локального файла-шаблона
      dest: /etc/mongod.conf # <-- Путь на удаленном хосте
      mode: 0644 # <-- Права на файл, которые нужно установить
    tags: db-tag # <-- Список тэгов для задачи
    notify: restart mongod

  - name: Add unit file for Puma
    become: true
    copy:
      src: files/puma.service
      dest: /etc/systemd/system/puma.service
    tags: app-tag
    notify: reload puma

  - name: Add config for DB connection
    template:
      src: templates/db_config.j2
      dest: /home/rmartsev/db_config
    tags: app-tag

  - name: enable puma
    become: true
    systemd: name=puma enabled=yes
    tags: app-tag

  - name: Fetch the latest version of application code
    git:
      repo: 'https://github.com/express42/reddit.git'
      dest: /home/appuser/reddit
      version: monolith # <-- Указываем нужную ветку
    tags: deploy-tag
    notify: reload puma
    
  - name: Bundle install
    bundler:
      state: present
      chdir: /home/appuser/reddit # <-- В какой директории выполнить команду bundle
    tags: deploy-tag

  handlers: # <-- Добавим блок handlers и задачу

  - name: restart mongod
    become: true
    service: name=mongod state=restarted

  - name: reload puma
    become: true
    systemd: name=puma state=restarted
```

Проверяем плейбук и запускаем его:

``` bash
ansible-playbook reddit_app.yml --check --limit app --tags deploy-tag
ansible-playbook reddit_app.yml --limit app --tags deploy-tag
```

Мы создали один плейбук, в котором определили один сценарий (play) и, как помним, для запуска нужных тасков на заданной группе хостов мы использовали опцию --limit для указания группы хостов и --tags для указания нужных тасков.

Очевидна проблема такого подхода, которая состоит в том, что мы должны помнить при каждом запуске плейбука, на каком хосте какие таски мы хотим применить, и передавать это в опциях командной строки.

## Один плейбук, несколько сценариев

Скопируем определение сценария из `reddit_app.yml` в `reddit_app2.yml` и всю информацию, относящуюся к настройке MongoDB, которая будет включать в себя таски, хендлеры и переменные.

Помним, что таски для настройки MongoDB приложения мы помечали тегом db-tag.

``` yml
---
- name: Configure hosts & deploy application
  hosts: all
  vars:
    mongo_bind_ip: 0.0.0.0
  tasks:
    - name: Change mongo config file
      become: true
      template:
        src: templates/mongod.conf.j2
        dest: /etc/mongod.conf
        mode: 0644
      tags: db-tag
      notify: restart mongod

  handlers:
  - name: restart mongod
    become: true
    service: name=mongod state=restarted
```

Внесем изменения в файл:

* Изменим словесное описание
* Укажем нужную группу хостов
* Уберем теги из тасков и определим тег на уровне сценария, чтобы мы могли запускать сценарий, используя тег.

Также заметим, что все наши таски требуют выполнения изпод пользователя root, поэтому нет смысла их указывать для каждого task.

* Вынесем become: true на уровень сценария.

``` yml
---
- name: Configure MongoDB
  hosts: db
  tags: db-tag
  become: true
  vars:
    mongo_bind_ip: 0.0.0.0
  tasks:
    - name: Change mongo config file
      template:
        src: templates/mongod.conf.j2
        dest: /etc/mongod.conf
        mode: 0644
      notify: restart mongod

  handlers:
  - name: restart mongod
    service: name=mongod state=restarted
```

Аналогичным образом определим еще один сценарий для настройки инстанса приложения.

``` yml
---
- name: Configure MongoDB
  hosts: db
  tags: db-tag
  become: true
  vars:
    mongo_bind_ip: 0.0.0.0
  tasks:
    - name: Change mongo config file
      template:
        src: templates/mongod.conf.j2
        dest: /etc/mongod.conf
        mode: 0644
      notify: restart mongod

  handlers:
  - name: restart mongod
    service: name=mongod state=restarted

- name: Configure hosts & deploy application
  hosts: all
  vars:
   db_host: 10.132.0.2
  tasks:
    - name: Add unit file for Puma
      become: true
      copy:
        src: files/puma.service
        dest: /etc/systemd/system/puma.service
      tags: app-tag
      notify: reload puma

    - name: Add config for DB connection
      template:
        src: templates/db_config.j2
        dest: /home/appuser/db_config
      tags: app-tag

    - name: enable puma
      become: true
      systemd: name=puma enabled=yes
      tags: app-tag

  handlers:
  - name: reload puma
    become: true
    systemd: name=puma state=restarted
```

Внесем изменения в файл:

* Изменим словесное описание
* Укажем нужную группу хостов
* Уберем теги из тасков и определим тег на уровне сценария, чтобы мы запускать сценарий, используя тег.
* Также заметим, что большинство из наших тасков требуют выполнения из-под пользователя root, поэтому вынесем become: true на уровень сценария.
* В таске, который копирует конфиг-файл в домашнюю директорию пользователя appuser, явно укажем пользователя и владельца файла.

``` yml
---
- name: Configure MongoDB
  hosts: db
  tags: db-tag
  become: true
  vars:
    mongo_bind_ip: 0.0.0.0
  tasks:
    - name: Change mongo config file
      template:
        src: templates/mongod.conf.j2
        dest: /etc/mongod.conf
        mode: 0644
      notify: restart mongod

  handlers:
  - name: restart mongod
    service: name=mongod state=restarted

- name: Configure App
  hosts: app
  tags: app-tag
  become: true
  vars:
   db_host: 35.195.123.178
  tasks:
    - name: Add unit file for Puma
      copy:
        src: files/puma.service
        dest: /etc/systemd/system/puma.service
      notify: reload puma

    - name: Add config for DB connection
      template:
        src: templates/db_config.j2
        dest: /home/appuser/db_config
        owner: appuser
        group: appuser

    - name: enable puma
      systemd: name=puma enabled=yes

  handlers:
  - name: reload puma
    systemd: name=puma state=restarted
```

Для чистоты проверки наших плейбуков пересоздадим инфраструктуру окружения stage, используя команды

``` bash
terraform destroy
terraform apply -auto-approve=false
```

Изменим IP адреса в соответствии с предоставленным `terraform` в файлах `ansible/reddit_app2.yml` и `ansible/inventory`. Результат:

``` yml
---
- name: Configure MongoDB
  hosts: db
  tags: db-tag
  become: true
  vars:
    mongo_bind_ip: 0.0.0.0
  tasks:
    - name: Change mongo config file
      template:
        src: templates/mongod.conf.j2
        dest: /etc/mongod.conf
        mode: 0644
      notify: restart mongod

  handlers:
  - name: restart mongod
    service: name=mongod state=restarted

- name: Configure App
  hosts: app
  tags: app-tag
  become: true
  vars:
   db_host: 35.195.123.178
  tasks:
    - name: Add unit file for Puma
      copy:
        src: files/puma.service
        dest: /etc/systemd/system/puma.service
      notify: reload puma

    - name: Add config for DB connection
      template:
        src: templates/db_config.j2
        dest: /home/rmartsev/db_config
        owner: rmartsev
        group: rmartsev

    - name: enable puma
      systemd: name=puma enabled=yes

  handlers:
  - name: reload puma
    systemd: name=puma state=restarted
```

Проверим корректность плейбука и запустим его

``` bash
ansible-playbook reddit_app2.yml --tags db-tag --check
ansible-playbook reddit_app2.yml --tags db-tag
ansible-playbook reddit_app2.yml --tags app-tag --check
ansible-playbook reddit_app2.yml --tags app-tag
```

Добавим также таски для деплоя. Результат:

``` yml
---
- name: Configure MongoDB
  hosts: db
  tags: db-tag
  become: true
  vars:
    mongo_bind_ip: 0.0.0.0

  tasks:

    - name: Change mongo config file
      template:
        src: templates/mongod.conf.j2
        dest: /etc/mongod.conf
        mode: 0644
      notify: restart mongod

  handlers:
  - name: restart mongod
    service: name=mongod state=restarted

- name: Configure App
  hosts: app
  tags: app-tag
  become: true
  vars:
    db_host: 35.195.123.178
  
  tasks:

    - name: Add unit file for Puma
      copy:
        src: files/puma.service
        dest: /etc/systemd/system/puma.service
      notify: reload puma

    - name: Add config for DB connection
      template:
        src: templates/db_config.j2
        dest: /home/rmartsev/db_config
        owner: rmartsev
        group: rmartsev

    - name: enable puma
      systemd: name=puma enabled=yes

  handlers:
  - name: reload puma
    systemd: name=puma state=restarted

- name: Deploy
  hosts: app
  tags: deploy-tag

  tasks:

    - name: Fetch the latest version of application code
      git:
        repo: 'https://github.com/express42/reddit.git'
        dest: /home/rmartsev/reddit
        version: monolith # <-- Указываем нужную ветку
      notify: reload puma

    - name: Bundle install
      bundler:
        state: present
        chdir: /home/rmartsev/reddit # <-- В какой директории выполнить команду bundle

  handlers:
  - name: reload puma
    become: true
    systemd: name=puma state=restarted
```

Проверим корректность плейбука и запустим его

``` bash
ansible-playbook reddit_app2.yml --tags deploy-tag --check
ansible-playbook reddit_app2.yml --tags deploy-tag
```

## Несколько плейбуков

В директории ansible создадим три новых файла:

* app.yml
* db.yml
* deploy.yml

Заодно переименуем наши предыдущие плейбуки:

* reddit_app.yml ➡ reddit_app_one_play.yml
* reddit_app2.yml ➡ reddit_app_multiple_plays.yml

Из файла reddit_app_multiple_plays.yml скопируем сценарий, относящийся к настройке БД, в файл db.yml. При этом, удалим тег определенный в сценарии.

Поскольку мы выносим наши сценарии в отдельные плейбуки, то для запуска нужного нам сценария достаточно будет указать имя плейбука, который его содержит. Значит, тег нам больше не понадобится.

Файл `ansible/db.yml`:

``` yml
---
- name: Configure MongoDB
  hosts: db
  become: true
  vars:
    mongo_bind_ip: 0.0.0.0

  tasks:

    - name: Change mongo config file
      template:
        src: templates/mongod.conf.j2
        dest: /etc/mongod.conf
        mode: 0644
      notify: restart mongod

  handlers:
  - name: restart mongod
    service: name=mongod state=restarted
```

Файл `ansible/app.yml`:

``` yml
---
- name: Configure App
  hosts: app
  tags: app-tag
  become: true
  vars:
    db_host: 10.132.0.50
  
  tasks:

    - name: Add unit file for Puma
      copy:
        src: files/puma.service
        dest: /etc/systemd/system/puma.service
      notify: reload puma

    - name: Add config for DB connection
      template:
        src: templates/db_config.j2
        dest: /home/rmartsev/db_config
        owner: rmartsev
        group: rmartsev

    - name: enable puma
      systemd: name=puma enabled=yes

  handlers:
  - name: reload puma
    systemd: name=puma state=restarted
```

Файл `ansible/deploy.yml`:

``` yml
---
- name: Deploy
  hosts: app
  tags: deploy-tag

  tasks:

    - name: Fetch the latest version of application code
      git:
        repo: 'https://github.com/express42/reddit.git'
        dest: /home/rmartsev/reddit
        version: monolith # <-- Указываем нужную ветку
      notify: reload puma

    - name: Bundle install
      bundler:
        state: present
        chdir: /home/rmartsev/reddit # <-- В какой директории выполнить команду bundle

  handlers:
  - name: reload puma
    become: true
    systemd: name=puma state=restarted
```

Создадим файл site.yml в директории ansible, в котором опишем управление конфигурацией всей нашей инфраструктуры. Это будет нашим главным плейбуком, который будет включать в себя все остальные:

Файл `ansible/site.yml`:

``` yml
---
- import_playbook: db.yml
- import_playbook: app.yml
- import_playbook: deploy.yml
```

### Проверка результата

Для чистоты проверки наших плейбуков пересоздадим инфраструктуру окружения stage, используя команды: 

``` bash
terraform destroy
terraform apply -auto-approve=false
```

и проверим работу плейбуков:

``` bash
ansible-playbook site.yml --check
ansible-playbook site.yml
```

Перед проверкой не забудьте изменить внешние IP-адреса инстансов в инвентори файле ansible/inventory и переменную db_host в плейбуке app.yml:

# Ansible 3

В директории `ansible` создадим роли для приложения и базы данных:

``` bash
cd ansible 
mkdir roles
cd roles 
ansible-galaxy init app
ansible-galaxy init db
```

Структура создаваемой роли:

``` bash
tree db
db
├── README.md
├── defaults          # <-- Директория для переменных по умолчанию
│   └── main.yml
├── files
├── handlers
│   └── main.yml
├── meta              # <-- Информация о роли, создателе и зависимостях
│   └── main.yml
├── tasks             # <-- Директория для тасков
│   └── main.yml
├── templates
├── tests
│   ├── inventory
│   └── test.yml
└── vars              # <-- Директория для переменных, которые не должны
    └── main.yml      #     переопределяться пользователем

8 directories, 8 files
```

Перенесем из файлов `ansible/app/yml` и `ansible/db.yml` в созданные директории ролей и отредактирует:

Файл `ansible/roles/db/tasks/main.yml`:

``` yml
---
# tasks file for db

- name: Change mongo config file
  template:
    src: mongod.conf.j2
    dest: /etc/mongod.conf
    mode: 0644
  notify: restart mongod
```

Файл `ansible/roles/db/handlers/main.yml`:

``` yml
---
# handlers file for db

- name: restart mongod
  service: name=mongod state=restarted
```

Файл `ansible/roles/db/defaults/main.yml`:

``` yml
---
# defaults file for db

mongo_port: 27017
mongo_bind_ip: 127.0.0.1
```

Файл `ansible/roles/app/tasks/main.yml`:

``` yml
---
# tasks file for app

- name: Add unit file for Puma
  copy:
    src: files/puma.service
    dest: /etc/systemd/system/puma.service
  notify: reload puma

- name: Add config for DB connection
  template:
    src: templates/db_config.j2
    dest: /home/rmartsev/db_config
    owner: rmartsev
    group: rmartsev
  notify: reload puma

- name: enable puma
  systemd: name=puma enabled=yes
```

Файл `ansible/roles/app/handlers/main.yml`:

``` yml
---
# handlers file for app
- name: reload puma
  systemd: 
    name: puma 
    state: restarted
    daemon_reload: yes
```

Файл `ansible/roles/app/defaults/main.yml`:

``` yml
---
# defaults file for app

db_host: 127.0.0.1
```

Скопируем файлы:

`ansible/templates/mongod.conf.j2` -> `ansible/roles/db/templates/mongod.conf.j2` /
`ansible/templates/db_config.j2` -> `ansible/roles/app/templates/db_config.j2` /
`ansible/files/puma.service` -> `ansible/roles/app/files/puma.service`

Удалим определение тасков и хендреров в плейбуках `ansible/app.yml` и `ansible/db.yml`:

Файл `ansible/app.yml`:

``` yml
---
- name: Configure App
  hosts: app
  become: true

  vars:
    db_host: 10.132.0.60
  
  roles:

    - app
```

Файл `ansible/db.yml`:

``` yml
---
- name: Configure MongoDB
  hosts: db
  become: true

  vars:
    mongo_bind_ip: 0.0.0.0

  roles:

    - db
```

Проверим корректность составления плейбука

``` bash
$ ansible-playbook site.yml --check

PLAY [Configure MongoDB] *****************************************************************************************

TASK [Gathering Facts] *******************************************************************************************
ok: [dbserver]

TASK [db : Change mongo config file] *****************************************************************************
changed: [dbserver]

RUNNING HANDLER [db : restart mongod] ****************************************************************************
changed: [dbserver]

PLAY [Configure App] *********************************************************************************************

TASK [Gathering Facts] *******************************************************************************************
ok: [appserver]

TASK [app : Add unit file for Puma] ******************************************************************************
changed: [appserver]

TASK [app : Add config for DB connection] ************************************************************************
changed: [appserver]

TASK [app : enable puma] *****************************************************************************************
ok: [appserver]

RUNNING HANDLER [app : reload puma] ******************************************************************************
changed: [appserver]

PLAY [Deploy] ****************************************************************************************************

TASK [Gathering Facts] *******************************************************************************************
ok: [appserver]

TASK [Fetch the latest version of application code] **************************************************************
ok: [appserver]

TASK [Bundle install] ********************************************************************************************
ok: [appserver]

PLAY RECAP *******************************************************************************************************
appserver                  : ok=8    changed=3    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0   
dbserver                   : ok=3    changed=2    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0   
```

И выполним его

``` bash
ansible-playbook site.yml
```

Проверим подключение к app через браузер - все работает корректно.

Скопируем файл `ansible/inventory` в каталоги `ansible/environtents/prod` и `ansible/environtents/stage`, исходный файл удалим.

Теперь для запуска плейбука необходимо выполнить команду:

``` bash
ansible-playbook -i environments/prod/inventory deploy.yml
```

Определим окружение по умолчанию в конфигурации ansible `ansible/ansible.cfg`:

``` ini
[defaults]
inventory = ./environments/stage/inventory
remote_user = rmartsev
private_key_file = ~/.ssh/rmartsev_rsa
host_key_checking = False
retry_files_enabled = False
ansible_python_interpreter=auto
interpreter_python=auto
```

Создадим директорию `group_vars` в директориях наших окружений `environments/prod` и `environments/stage`

Зададим настройки окружения stage, используя групповые переменные:

1. Создадим файлы `stage/group_vars/app` для определения переменных для группы хостов app, описанных в инвентори файле `stage/inventory`.
2. Скопируем в этот файл переменные, определенные в плейбуке `ansible/app.yml`.
3. Также удалим определение переменных из самого плейбука `ansible/app.yml`.
4. Создадим файлы `stage/group_vars/db` для определения переменных для группы хостов app, описанных в инвентори файле `stage/inventory`.
5. Скопируем в этот файл переменные, определенные в плейбуке `ansible/db.yml`.
6. Также удалим определение переменных из самого плейбука `ansible/db.yml`.
7. Создадим файл `ansible/environments/stage/group_vars/all` со следующим содержимым:

``` ini
env: stage
```

Конфигурация окружения prod будет идентичной, за исключением переменной env, определенной для группы all. Скопируем файлы переменных из окружения stage в prod и изменим значение переменной `env` на `prod`.

Для хостов из каждого окружения мы определили переменную `env`, которая содержит название окружения. Теперь настроим вывод информации об окружении, с которым мы работаем, при применении плейбуков. Определим переменную по умолчанию `env` в используемых ролях...

Для роли app в файле `ansible/roles/app/defaults/main.yml`:

``` ini
# defaults file for app
db_host: 127.0.0.1
env: local
```

Для роли db в файле `ansible/roles/db/defaults/main.yml`:

``` ini
# defaults file for db
mongo_port: 27017
mongo_bind_ip: 127.0.0.1
env: local
```

Будем выводить информацию о том, в каком окружении находится конфигурируемый хост. Воспользуемся модулем debug для вывода значения переменной. Добавим следующий таск в начало наших ролей.

Для роли app (файл `ansible/roles/app/tasks/main.yml`):

``` yml
# tasks file for app
- name: Show info about the env this host belongs to
  debug:
    msg: "This host is in {{ env }} environment!!!"
```

Добавим такой же таск в роль db.

Улучшим наш ansible.cfg. Для этого приведем его к такому виду:

``` ini
[defaults]
inventory = ./environments/stage/inventory
remote_user = rmartsev
private_key_file = ~/.ssh/rmartsev_rsa
host_key_checking = False
retry_files_enabled = False
ansible_python_interpreter=auto
interpreter_python=auto
# Отключим проверку SSH Host-keys (поскольку они всегда разные для новых инстансов)
host_key_checking = False
# Отключим создание *.retry-файлов (они нечасто нужны, но мешаются под руками)
retry_files_enabled = False
# # Явно укажем расположение ролей (можно задать несколько путей через ; )
roles_path = ./roles

[diff]
# Включим обязательный вывод diff при наличии изменений и вывод 5 строк контекста
always = True
context = 5
```

Для проверки пересоздадим инфраструктуру окружения stage, используя команды:

``` bash
terraform destroy
terraform apply -auto-approve=false
```

Если все сделано правильно, то получим примерно такой вывод команды ansible-playbook:

``` bash
ansible-playbook playbooks/site.yml --check
ansible-playbook playbooks/site.yml
```

Используем роль jdauphant.nginx и настроим обратное проксирование для нашего приложения с помощью nginx.

Хорошей практикой является разделение зависимостей ролей (`requirements.yml`) по окружениям.

1. Создадим файлы `environments/stage/requirements.yml` и `environments/prod/requirements.yml`
2. Добавим в них запись вида:

``` yml
- src: jdauphant.nginx
  version: v2.21.1
```

3. Установим роль:

``` bash
ansible-galaxy install -r environments/stage/requirements.yml
```

4. Комьюнити-роли не стоит коммитить в свой репозиторий, для этого добавим в .gitignore запись: jdauphant.nginx

Добавим эти переменные в `stage/group_vars/app` и `prod/group_vars/app`:

``` ini
db_host: 10.132.15.194
nginx_sites:
    default:
        - listen 80
        - server_name "reddit"
        - location / {
                proxy_pass http://127.0.0.1:9292;
            }
```

Самостоятельное задание

1. Добавьте в конфигурацию Terraform открытие 80 порта для инстанса приложения.
2. Добавьте вызов роли jdauphant.nginx в плейбук app.yml.
3. Примените плейбук site.yml для окружения stage и проверьте, что приложение теперь доступно на 80 порту.

Подготовим плейбук для создания пользователей, пароль пользователей будем хранить в зашифрованном виде в файле `credentials.yml`

1. Создайте файл vault.key со произвольной строкой ключа
2. Изменим файл ansible.cfg, добавим опцию vault_password_file в секцию [defaults]

``` ini
[defaults]
...
vault_password_file = vault.key
```

Добавим в `.gitignore` файл `vault.key`

Добавим плейбук для создания пользователей - файл `ansible/playbooks/users.yml`

``` yml
---
- name: Create users
  hosts: all
  become: true

  vars_files:
    - "{{ inventory_dir }}/credentials.yml"

  tasks:
    - name: create users
      user:
        name: "{{ item.key }}"
        password: "{{ item.value.password|password_hash('sha512', 65534|random(seed=inventory_hostname)|string) }}"
        groups: "{{ item.value.groups | default(omit) }}"
      with_dict: "{{ credentials.users }}"
```

Создадим файл с данными пользователей для каждого окружения.

Файл для prod (ansible/environments/prod/credentials.yml):

``` ini
credentials:
  users:
    admin:
      password: admin123
      groups: sudo
```

Файл для stage (ansible/environments/stage/credentials.yml):

``` ini
credentials:
  users:
    admin:
      password: qwerty123
      groups: sudo
    qauser:
      password: test123
```

1. Зашифруем файлы используя vault.key (используем одинаковый для всех окружений):

``` bash
ansible-vault encrypt environments/prod/credentials.yml
ansible-vault encrypt environments/stage/credentials.yml
```

2. Проверьте содержимое файлов, убедитесь что они зашифрованы
3. Добавьте вызов плейбука в файл site.yml и выполните его для stage окружения:

``` bash
ansible-playbook site.yml —check
ansible-playbook site.yml
```

# Docker

Запустим первый контейнер после установки `Docker`:

``` bash
$ docker run hello-world 
Unable to find image 'hello-world:latest' locally
latest: Pulling from library/hello-world
0e03bdcc26d7: Pull complete 
Digest: sha256:1a523af650137b8accdaed439c17d684df61ee4d74feac151b5b337bd29e7eec
Status: Downloaded newer image for hello-world:latest

Hello from Docker!
This message shows that your installation appears to be working correctly.
<skip>
```

Полезные команды:

1. `docker ps` - список запушенных контейнеров.
2. `docker ps -a` - список всех контейнеров.
3. `docker images` - список сохраненных образов.
4. `docker run` - создает и запускает контейнер из image (eg. docker run -it ubuntu:16.04 /bin/bash). При каждом запуске создается новый контейнер. Если не указывать флаг `--rm` при запуске `docker run`, то после остановки контейнер вместе с содержимым остается на диске. `docker run` = `docker create` + `docker start` + `docker attach`.
5. `docker create` - создает контейнер, используется, когда не нужно стартовать контейнер сразу.
6. `docker start <u_container_id>` - запускает контейнер.
7. `docker attach <u_container_id>` - присоединяет терминал к запущенному контейнеру.
8. `docker exec` - запускает новый процесс внутри контейнера.
9. `docker commit` - создает image из контейнера; контейнер остается запущенным.
10. `docker system df` - отображение дискового пространства, занятого образами, контейнерами и volume’ами.
11. `docker rm` -  удаляет контейнер, можно добавить флаг -f, чтобы удалялся работающий container(будет послан sigkill).
12. `socker rmi` - удаляет image, если от него не зависят запущенные контейнеры.

* Через параметры передаются лимиты(cpu/mem/disk), ip, volumes
* -i – запускает контейнер в foreground режиме (docker attach)
* -d – запускает контейнер в background режиме
* -t создает TTY

Создадим два контейнера:

``` bash
docker run -it ubuntu:16.04 /bin/bash 
echo 'Hello world!' > /tmp/file
exit
```

``` bash
$ docker run -it ubuntu:16.04 /bin/bash
$ cat /tmp/file
cat: /tmp/file: No such file or directory
$ exit
```

Найдем ранее созданный контейнер в котором мы создали `/tmp/file`:

``` bash
$ docker ps -a --format "table {{.ID}}\t{{.Image}}\t{{.CreatedAt}}\t{{.Names}}"  
CONTAINER ID   IMAGE          CREATED AT                      NAMES
227696ce103d   ubuntu:16.04   2021-01-10 11:41:09 +0300 MSK   wonderful_pike
ecb44f1b9d02   ubuntu:16.04   2021-01-10 11:39:48 +0300 MSK   suspicious_fermat
22ba602cfbba   hello-world    2021-01-10 11:30:12 +0300 MSK   zealous_shaw
```

Запустим предпоследний контейнер из образа ubuntu:16.04, подключимся к нему и выведем на экран содержимое файла `/tmp/file`:

``` bash
$ docker start ecb44f1b9d02
$ docker attach ecb44f1b9d02
<ENTER>
$ cat /tmp/file
Hello world!
$ exit
```

Удалим все контейнеры:

``` bash
$ docker rm $(docker ps -a -q)
227696ce103d
ecb44f1b9d02
22ba602cfbba
```

Удалим все образы:

``` bash
$ docker rmi $(docker images -q)
Untagged: yourname/ubuntu-tmp-file:latest
Deleted: sha256:a99c1eb62561e8acca5f96b3d6ce4c3d3eff6c53715bcad24a5a3e6015df2a43
Deleted: sha256:215c89cc569b2f33a222fe9c608bebb2c05091a9b36cf6a25380d82d89c3cf06
Untagged: ubuntu:16.04
Untagged: ubuntu@sha256:3355b6e4ba1b12071ba5fe9742042a2f10b257c908fbdfac81912a16eb463879
Deleted: sha256:9499db7817713c4d10240ca9f5386b605ecff7975179f5a46e7ffd59fff462ee
Deleted: sha256:f40485a002f52daa539c4ebf3a9805d74a0396eacb48d09f3774b2c9865a43db
Deleted: sha256:4c823febe808dcc9c69e7b99a91796fcf125fdde4aac206c9eac13fcfd4ffba3
Deleted: sha256:ea2e76a9d2f2be4a60d0872a63775f03f9510d7a0aa6bdc68a936e9a7b7b995a
Deleted: sha256:da2785b7bb163ff867008430c06b6c02d3ffc16fcee57ef38822861af85989ea
Untagged: hello-world:latest
Untagged: hello-world@sha256:1a523af650137b8accdaed439c17d684df61ee4d74feac151b5b337bd29e7eec
Deleted: sha256:bf756fb1ae65adf866bd8c456593cd24beb6a0a061dedf42b26a993176745f6b
Deleted: sha256:9c27e219663c25e0f28493790cc0b88bc973ba3b1686355f221c38a36978ac63
```

Установим docker-machine: `https://docs.docker.com/machine/install-machine/`

``` bash
$ docker-machine -v                                                  
docker-machine version 0.16.0, build 702c267f
```

Создадим хост с докер:

``` bash
$ export GOOGLE_PROJECT=docker-301310
$ docker-machine create --driver google \
 --google-machine-image https://www.googleapis.com/compute/v1/projects/ubuntu-os-cloud/global/images/family/ubuntu-2004-lts \
 --google-machine-type n1-standard-1 \
 --google-zone europe-west1-b \
 --google-project docker-301310 \
 docker-host
Running pre-create checks...
(docker-host) Check that the project exists
(docker-host) Check if the instance already exists
Creating machine...
(docker-host) Generating SSH Key
(docker-host) Creating host...
(docker-host) Opening firewall ports
(docker-host) Creating instance
(docker-host) Waiting for Instance
(docker-host) Uploading SSH Key
Waiting for machine to be running, this may take a few minutes...
Detecting operating system of created instance...
Waiting for SSH to be available...
Detecting the provisioner...
Provisioning with ubuntu(systemd)...
Installing Docker...
Copying certs to the local machine directory...
Copying certs to the remote machine...
Setting Docker configuration on the remote daemon...
Checking connection to Docker...
Docker is up and running!
To see how to connect your Docker Client to the Docker Engine running on this virtual machine, run: docker-machine env docker-host
$ docker-machine ls                      
NAME          ACTIVE   DRIVER   STATE     URL                        SWARM   DOCKER     ERRORS
docker-host   -        google   Running   tcp://130.211.99.56:2376           v20.10.2   
$ eval $(docker-machine env docker-host)
```

Создадим 4 файла:

* Dockerfile - текстовое описание нашего образа
* mongod.conf - подготовленный конфиг для mongodb
* db_config - содержит переменную окружения со ссылкой на mongodb
* start.sh - скрипт запуска приложения

Файл `mongod.conf`:

``` conf
# Where and how to store data.
storage:
  dbPath: /var/lib/mongodb
  journal:
    enabled: true

# where to write logging data.
systemLog:
  destination: file
  logAppend: true
  path: /var/log/mongodb/mongod.log

# network interfaces
net:
  port: 27017
  bindIp: 127.0.0.1
```

Файл `start.sh`

``` sh
#!/bin/bash

/usr/bin/mongod --fork --logpath /var/log/mongod.log --config /etc/mongodb.conf

source /reddit/db_config

cd /reddit && puma || exit
```

Файл `db_config`:

``` ini
DATABASE_URL=127.0.0.1
```

Начнем создавать образ с приложением. За основу возьмем известный нам дистрибутив ubuntu версии 16.04

Создадим файл "Dockerfile" и добавим в него строки:

``` Dockerfile
FROM ubuntu:16.04
```

Для работы приложения нам нужны mongo и ruby. Обновим кеш репозитория и установим нужные пакеты. Добавим в "Dockerfile" строки:

``` Dockerfile
RUN apt-get update
RUN apt-get install -y mongodb-server ruby-full ruby-dev build-essential git
RUN gem install bundler
```

Скачаем наше приложение в контейнер:

``` Dockerfile
RUN git clone -b monolith https://github.com/express42/reddit.git
```

Скопируем файлы конфигурации в контейнер:

``` Dockerfile
COPY mongod.conf /etc/mongod.conf
COPY db_config /reddit/db_config
COPY start.sh /start.sh
```

Теперь нам нужно установить зависимости приложения и произвести настройку:

``` Dockerfile
RUN cd /reddit && bundle install
RUN chmod 0777 /start.sh
```

Добавляем старт сервиса при старте контейнера:

``` Dockerfile
CMD ["/start.sh"]
```

Теперь мы готовы собрать свой образ

``` bash
docker build -t reddit:latest .
```

Посмотрим на все образы (в том числе промежуточные):

``` bash
$ docker images -a
REPOSITORY      TAG       IMAGE ID       CREATED              SIZE
<none>          <none>    5b3f9bf549f5   27 seconds ago       690MB
reddit          latest    6cb0891308ce   27 seconds ago       690MB
<none>          <none>    50eef95391dc   28 seconds ago       690MB
<none>          <none>    69cf32a288a1   40 seconds ago       658MB
<none>          <none>    208afc1b216e   40 seconds ago       658MB
<none>          <none>    86c1829e8e3e   40 seconds ago       658MB
<none>          <none>    9de44cece132   40 seconds ago       658MB
<none>          <none>    675219976c4c   42 seconds ago       658MB
<none>          <none>    eeedf0544209   52 seconds ago       655MB
<none>          <none>    bad32b22df16   About a minute ago   161MB
ubuntu          16.04     9499db781771   6 weeks ago          131MB
```

Теперь можно запустить наш контейнер командой:

``` bash
docker run --name reddit -d --network=host reddit:latest
```

Проверим результат:

``` bash
$ docker-machine ls
NAME          ACTIVE   DRIVER   STATE     URL                        SWARM   DOCKER     ERRORS
docker-host   *        google   Running   tcp://130.211.99.56:2376           v20.10.2   
```

Разрешим входящий TCP-трафик на порт 9292 выполнив команду:

``` bash
$ gcloud compute firewall-rules create reddit-app \
 --allow tcp:9292 \
 --target-tags=docker-machine \
 --description="Allow PUMA connections" \
 --direction=INGRESS
 ```

Для проверки откроем в браузере ссылку http://130.211.99.56:9292/

Аутентифицируемся на docker hub для продолжения работы:

``` bash
$ docker login
Login with your Docker ID to push and pull images from Docker Hub. If you don't have a Docker ID, head over to https://hub.docker.com to create one.
Username: windemiatrix
Password: 
Login Succeeded
```

Загрузим наш образ на docker hub для использования в будущем:

``` bash
$ docker tag reddit:latest windemiatrix/otus-reddit:1.0
$ docker push windemiatrix/otus-reddit:1.0
The push refers to repository [docker.io/windemiatrix/otus-reddit]
726d957787a8: Pushed 
fe38e14f4895: Pushed 
c3f808e07aa1: Pushed 
b7f80a28a07b: Pushed 
ccb5e3d3fec2: Pushed 
0f791091e5a4: Pushed 
7b154bd12e3a: Pushed 
f16d1ef0d66f: Pushed 
fb2512f5cfb4: Pushed 
1a1a19626b20: Mounted from library/ubuntu 
5b7dc8292d9b: Mounted from library/ubuntu 
bbc674332e2e: Mounted from library/ubuntu 
da2785b7bb16: Mounted from library/ubuntu 
1.0: digest: sha256:6c4efdca3cee9b5b5eabe6066de9e644dbe17119b817e2262ac94497c266a7ed size: 3035
```

Т.к. теперь наш образ есть в докер хабе, то мы можем запустить его не только в докер хосте в GCP, но и в вашем локальном докере или на другом хосте. Выполним в другой консоли:

``` bash
docker run --name reddit -d -p 9292:9292 windemiatrix/otus-reddit:1.0
```

# Docker-3

Проверим список хостов Docker:

``` bash
$ docker-machine ls
NAME          ACTIVE   DRIVER   STATE     URL                         SWARM   DOCKER     ERRORS
docker-host   -        google   Running   tcp://104.199.71.220:2376           v20.10.2   
$ eval $(docker-machine env docker-host)
```

Скопируем каталог, предоставленный в рамках программы обучения OTUS, в корень репозитория и переименуем в `src`

Создадим файл `src/post-py/Dockerfile` со следующим содержимым:

``` Dockerfile
FROM python:3.6.0-alpine
WORKDIR /app
ADD . /app
RUN pip install --upgrade pip
RUN apk add --no-cache make build-base
RUN pip install -r /app/requirements.txt
ENV POST_DATABASE_HOST post_db
ENV POST_DATABASE posts
CMD ["python3", "post_app.py"]
```

Создадим файл `src/comment/Dockerfile` со следующим содержимым:

``` Dockerfile
FROM ruby:2.2
RUN apt-get update -qq && apt-get install -y build-essential
ENV APP_HOME /app
RUN mkdir $APP_HOME
WORKDIR $APP_HOME
ADD Gemfile* $APP_HOME/
RUN bundle install
COPY . $APP_HOME
ENV COMMENT_DATABASE_HOST comment_db
ENV COMMENT_DATABASE comments
CMD ["puma"]
```

Создадим файл `src/ui/Dockerfile` со следующим содержимым:

``` Dockerfile
FROM ruby:2.2
RUN apt-get update -qq && apt-get install -y build-essential
ENV APP_HOME /app
RUN mkdir $APP_HOME
WORKDIR $APP_HOME
ADD Gemfile* $APP_HOME/
RUN bundle install
ADD . $APP_HOME
ENV POST_SERVICE_HOST post
ENV POST_SERVICE_PORT 5000
ENV COMMENT_SERVICE_HOST comment
ENV COMMENT_SERVICE_PORT 9292
CMD ["puma"]
```

Скачаем последний образ MongoDB:

``` bash
docker pull mongo:latest
```

Соберем образы с нашими сервисами:

``` bash
docker build -t windemiatrix/post:1.0 ./post-py
docker build -t windemiatrix/comment:1.0 ./comment
docker build -t windemiatrix/ui:1.0 ./ui
```

Создадим специальную сеть для приложения:

``` bash
docker network create reddit
```

Запустим наши контейнеры:

``` bash
docker run -d --network=reddit --network-alias=post_db --network-alias=comment_db mongo:latest
docker run -d --network=reddit --network-alias=post windemiatrix/post:1.0
docker run -d --network=reddit --network-alias=comment windemiatrix/comment:1.0
docker run -d --network=reddit -p 9292:9292 windemiatrix/ui:1.0
```

Посмотрим размер созданных образов:

``` bash
docker images
REPOSITORY             TAG            IMAGE ID       CREATED         SIZE
windemiatrix/ui        1.0            dbda66e67943   2 minutes ago   770MB
windemiatrix/comment   1.0            3b09bb97715f   2 minutes ago   768MB
windemiatrix/post      1.0            b0d4150e0472   3 minutes ago   265MB
mongo                  latest         c97feb3412a3   7 days ago      493MB
ruby                   2.2            6c8e6f9667b2   2 years ago     715MB
python                 3.6.0-alpine   cb178ebbf0f2   3 years ago     88.6MB
```

Оптимизируем Dickerfile для UI:

``` Dockerfile
FROM ubuntu:16.04
RUN apt-get update \
    && apt-get install -y ruby-full ruby-dev build-essential \
    && gem install bundler --no-ri --no-rdoc

ENV APP_HOME /app
RUN mkdir $APP_HOME

WORKDIR $APP_HOME
ADD Gemfile* $APP_HOME/
RUN bundle install
ADD . $APP_HOME

ENV POST_SERVICE_HOST post
ENV POST_SERVICE_PORT 5000
ENV COMMENT_SERVICE_HOST comment
ENV COMMENT_SERVICE_PORT 9292

CMD ["puma"]
```

Перемоберем UI:

``` bash
docker build -t windemiatrix/ui:2.0 ./ui
```

Выключим старые версии контейнеров:

``` bash
docker kill $(docker ps -q)
```

Запустим новые версии контейнеров:

``` bash
docker run -d --network=reddit --network-alias=post_db --network-alias=comment_db mongo:latest
docker run -d --network=reddit --network-alias=post windemiatrix/post:1.0
docker run -d --network=reddit --network-alias=comment windemiatrix/comment:1.0
docker run -d --network=reddit -p 9292:9292 windemiatrix/ui:2.0
```

Все данные пропали. Для сохранения данных создадим Docker volume:

``` bash
docker volume create reddit_db
```

И подключим его к контейнеру MongoDB

``` bash
docker kill $(docker ps -q)
docker run -d --network=reddit --network-alias=post_db --network-alias=comment_db -v reddit_db:/data/db mongo:latest
docker run -d --network=reddit --network-alias=post windemiatrix/post:1.0
docker run -d --network=reddit --network-alias=comment windemiatrix/comment:1.0
docker run -d --network=reddit -p 9292:9292 windemiatrix/ui:2.0
```

Теперь все данные после перезапуска контейнера сохраняются.

# Docker 4

Создадим докер хост в GCP и подключимся к нему

``` bash
$ docker-machine create --driver google \
 --google-machine-image https://www.googleapis.com/compute/v1/projects/ubuntu-os-cloud/global/images/family/ubuntu-1604-lts \
 --google-machine-type n1-standard-1 \
 --google-zone europe-west1-b \
 --google-project docker-301310 \
 docker-host
...
$ docker-machine ls
NAME          ACTIVE   DRIVER   STATE     URL                        SWARM   DOCKER     ERRORS
docker-host   -        google   Running   tcp://104.155.94.64:2376           v20.10.2   
$ eval $(docker-machine env docker-host)
```

Запустим контейнер с использованием none-драйвера.
В качестве образа используем joffotron/docker-net-tools
Делаем это для экономии сил и времени, т.к. в его состав уже входят необходимые утилиты для работы с сетью: пакеты bindtools, net-tools и curl.
Контейнер запустится, выполнить команду `ifconfig` и будет удален (флаг --rm)

``` bash
$ docker run -ti --rm --network none joffotron/docker-net-tools -c ifconfig
...
lo        Link encap:Local Loopback  
          inet addr:127.0.0.1  Mask:255.0.0.0
          UP LOOPBACK RUNNING  MTU:65536  Metric:1
          RX packets:0 errors:0 dropped:0 overruns:0 frame:0
          TX packets:0 errors:0 dropped:0 overruns:0 carrier:0
          collisions:0 txqueuelen:1000 
          RX bytes:0 (0.0 B)  TX bytes:0 (0.0 B)
```

В результате, видим:

* что внутри контейнера из сетевых интерфейсов существует только loopback.
* сетевой стек самого контейнера работает (ping localhost), но без возможности контактировать с внешним миром.
* Значит, можно даже запускать сетевые сервисы внутри такого контейнера, но лишь для локальных экспериментов (тестирование, контейнеры для выполнения разовых задач и т.д.)

Запустим контейнер в сетевом пространстве docker-хоста

``` bash
$ docker run -ti --rm --network host joffotron/docker-net-tools -c ifconfig
docker0   Link encap:Ethernet  HWaddr 02:42:AA:E3:5C:4C  
          inet addr:172.17.0.1  Bcast:172.17.255.255  Mask:255.255.0.0
          UP BROADCAST MULTICAST  MTU:1500  Metric:1
          RX packets:0 errors:0 dropped:0 overruns:0 frame:0
          TX packets:0 errors:0 dropped:0 overruns:0 carrier:0
          collisions:0 txqueuelen:0 
          RX bytes:0 (0.0 B)  TX bytes:0 (0.0 B)

ens4      Link encap:Ethernet  HWaddr 42:01:0A:84:00:04  
          inet addr:10.132.0.4  Bcast:0.0.0.0  Mask:255.255.255.255
          inet6 addr: fe80::4001:aff:fe84:4%32569/64 Scope:Link
          UP BROADCAST RUNNING MULTICAST  MTU:1460  Metric:1
          RX packets:11337 errors:0 dropped:0 overruns:0 frame:0
          TX packets:5510 errors:0 dropped:0 overruns:0 carrier:0
          collisions:0 txqueuelen:1000 
          RX bytes:119448106 (113.9 MiB)  TX bytes:591655 (577.7 KiB)

lo        Link encap:Local Loopback  
          inet addr:127.0.0.1  Mask:255.0.0.0
          inet6 addr: ::1%32569/128 Scope:Host
          UP LOOPBACK RUNNING  MTU:65536  Metric:1
          RX packets:204 errors:0 dropped:0 overruns:0 frame:0
          TX packets:204 errors:0 dropped:0 overruns:0 carrier:0
          collisions:0 txqueuelen:1000 
          RX bytes:21202 (20.7 KiB)  TX bytes:21202 (20.7 KiB)
```

Данный контейнер включен в стандартный bridge docker0. Также данный контейнер будет привязан к интерфейсу хоста `docker-host`.

Запустим несколько раз создание контейнера с nginx:

``` bash
docker run --network host -d nginx
```

В результате получим один рабочий контейнер, запущенный первым. Все остальные будут со статусом `Exited`:

``` bash
$ docker ps -a                      
CONTAINER ID   IMAGE     COMMAND                  CREATED              STATUS                          PORTS     NAMES
ed803139aec3   nginx     "/docker-entrypoint.…"   13 seconds ago       Exited (1) 10 seconds ago                 practical_cohen
87fee6c20feb   nginx     "/docker-entrypoint.…"   About a minute ago   Exited (1) About a minute ago             affectionate_elion
46cd53d6ef66   nginx     "/docker-entrypoint.…"   3 minutes ago        Exited (1) 3 minutes ago                  funny_kilby
eeda461ef995   nginx     "/docker-entrypoint.…"   3 minutes ago        Exited (1) 3 minutes ago                  elegant_lederberg
55ad3595540c   nginx     "/docker-entrypoint.…"   3 minutes ago        Up 3 minutes                              modest_kilby
```

Остановим все запущенные контейнеры:

``` bash
docker kill $(docker ps -q)
```

Подключимся к ssh docker-host:

``` bash
docker-machine ssh docker-host
```

Выполним на `docker-host` команду:

``` bash
sudo ln -s /var/run/docker/netns /var/run/netns 
```

Теперь мы можем просматривать существующие в данный момент net-namespaces с помощью команды:

``` bash
sudo ip netns
```

`ip netns exec <namespace> <command>` - позволит выполнять команды в выбранном namespace

Запустим еще раз контейнеры и проверим список net-namespaces:

``` bash
$ sudo ip netns
default
```

Создадим bridge-сеть в docker (флаг --driver указывать не обязательно, т.к. по-умолчанию используется bridge)

``` bash
docker network create reddit --driver bridge
```

Запустим наш проект reddit с использованием bridge-сети

``` bash
docker run -d --network=reddit mongo:latest
docker run -d --network=reddit windemiatrix/post:1.0
docker run -d --network=reddit windemiatrix/comment:1.0
docker run -d --network=reddit -p 9292:9292 windemiatrix/ui:1.0
```

При просмотре приложения видим ошибку "Can't show blog posts, some problems with the post service. Refresh?".

На самом деле, наши сервисы ссылаются друг на друга по dnsименам, прописанным в ENV-переменных (см Dockerfile). В текущей инсталляции встроенный DNS docker не знает ничего об этих именах.

Решением проблемы будет присвоение контейнерам имен или сетевых алиасов при старте:

* --name `name` (можно задать только 1 имя)
* --network-alias `alias-name` (можно задать множество алиасов)

Остановим контейнеры и повторим запуск с указанием имен и алиасов для контейнеров

``` bash
docker kill $(docker ps -q)
docker run -d --network=reddit --network-alias=post_db --network-alias=comment_db mongo:latest
docker run -d --network=reddit --network-alias=post windemiatrix/post:1.0
docker run -d --network=reddit --network-alias=comment windemiatrix/comment:1.0
docker run -d --network=reddit -p 9292:9292 windemiatrix/ui:1.0
```

Теперь веб-приложение работает корректно.

Запустим наш проект в 2-х bridge сетях. Так, чтобы сервис ui не имел доступа к базе данных.

* сеть front_net: `ui`, `comment`, `post`;
* сеть back_net: `comment`, `post`, `db`.

Остановим старые копии контейнеров и создадим docker-сети

``` bash
docker kill $(docker ps -q)
docker network create back_net --subnet=10.0.2.0/24
docker network create front_net --subnet=10.0.1.0/24
```

Запустим контейнеры

``` bash
docker run -d --network=front_net -p 9292:9292 --name ui windemiatrix/ui:1.0
docker run -d --network=back_net --name comment windemiatrix/comment:1.0
docker run -d --network=back_net --name post windemiatrix/post:1.0
docker run -d --network=back_net --name mongo_db --network-alias=post_db --network-alias=comment_db mongo:latest
```

Что пошло не так?

Docker при инициализации контейнера может подключить к нему только 1 сеть. При этом контейнеры из соседних сетей не будут доступны как в DNS, так и для взаимодействия по сети. Поэтому нужно поместить контейнеры post и comment в обе сети. Дополнительные сети подключаются командой:

``` bash
docker network connect <network> <container>
```

Подключим контейнеры ко второй сети

``` bash
docker network connect front_net post
docker network connect front_net comment
```

Теперь веб-приложение работает корректно.

Посмотрим как выглядит сетевой стек Linux в текущий момент

``` bash
$ docker-machine ssh docker-host
$ sudo apt-get update && sudo apt-get install bridge-utils
$ sudo docker network ls
NETWORK ID     NAME        DRIVER    SCOPE
b3e24c5d2e76   back_net    bridge    local
582885f8090d   bridge      bridge    local
e21e795350b0   front_net   bridge    local
c6d781080887   host        host      local
9076aa02495c   none        null      local
36da497a2705   reddit      bridge    local
$ sudo ifconfig | grep br
br-36da497a2705 Link encap:Ethernet  HWaddr 02:42:d6:dd:44:57
br-b3e24c5d2e76 Link encap:Ethernet  HWaddr 02:42:2e:27:75:8d
br-e21e795350b0 Link encap:Ethernet  HWaddr 02:42:49:71:dc:27
$ sudo brctl show br-b3e24c5d2e76
bridge name     bridge id               STP enabled     interfaces
br-b3e24c5d2e76         8000.02422e27758d       no              veth2eedcae
                                                        veth38e7e71
                                                        vethf59b59c
$ sudo iptables -nL -t nat (флаг -v даст чуть больше инфы)
Chain PREROUTING (policy ACCEPT)
target     prot opt source               destination         
DOCKER     all  --  0.0.0.0/0            0.0.0.0/0            ADDRTYPE match dst-type LOCAL

Chain INPUT (policy ACCEPT)
target     prot opt source               destination         

Chain OUTPUT (policy ACCEPT)
target     prot opt source               destination         
DOCKER     all  --  0.0.0.0/0           !127.0.0.0/8          ADDRTYPE match dst-type LOCAL

Chain POSTROUTING (policy ACCEPT)
target     prot opt source               destination         
MASQUERADE  all  --  10.0.1.0/24          0.0.0.0/0           
MASQUERADE  all  --  10.0.2.0/24          0.0.0.0/0           
MASQUERADE  all  --  172.18.0.0/16        0.0.0.0/0           
MASQUERADE  all  --  172.17.0.0/16        0.0.0.0/0           
MASQUERADE  tcp  --  10.0.1.2             10.0.1.2             tcp dpt:9292

Chain DOCKER (2 references)
target     prot opt source               destination         
RETURN     all  --  0.0.0.0/0            0.0.0.0/0           
RETURN     all  --  0.0.0.0/0            0.0.0.0/0           
RETURN     all  --  0.0.0.0/0            0.0.0.0/0           
RETURN     all  --  0.0.0.0/0            0.0.0.0/0           
DNAT       tcp  --  0.0.0.0/0            0.0.0.0/0            tcp dpt:9292 to:10.0.1.2:9292
$ udo ps ax | grep docker-proxy
17502 ?        Sl     0:00 /usr/bin/docker-proxy -proto tcp -host-ip 0.0.0.0 -host-port 9292 -container-ip 10.0.1.2 -container-port 9292
21141 pts/0    S+     0:00 grep --color=auto docker-proxy
```

Отображаемые veth-интерфейсы (команда `sudo brctl show br-b3e24c5d2e76`) - это те части виртуальных пар интерфейсов, которые лежат в сетевом пространстве хоста и также отображаются в ifconfig. Вторые их части лежат внутри контейнеров

## Docker compose

В директории с проектом, папка src, из предыдущего домашнего задания создадим файл `docker-compose.yml`

``` yml
version: '3.3'
services:
  post_db:
    image: mongo:3.2
    volumes:
      - post_db:/data/db
    networks:
      - reddit
  ui:
    build: ./ui
    image: ${USERNAME}/ui:1.0
    ports:
      - 9292:9292/tcp
    networks:
      - reddit
  post:
    build: ./post-py
    image: ${USERNAME}/post:1.0
    networks:
      - reddit
  comment:
    build: ./comment
    image: ${USERNAME}/comment:1.0
    networks:
      - reddit

volumes:
  post_db:

networks:
  reddit:
```

Остановим контейнеры, запущенные на предыдущих шагах

``` bash
docker kill $(docker ps -q)
```

Выполним:

``` bash
$ export USERNAME=windemiatrix
$ docker-compose up -d
$ docker-compose ps
    Name                  Command             State           Ports         
----------------------------------------------------------------------------
src_comment_1   puma                          Up                            
src_post_1      python3 post_app.py           Up                            
src_post_db_1   docker-entrypoint.sh mongod   Up      27017/tcp             
src_ui_1        puma                          Up      0.0.0.0:9292->9292/tcp
```

Веб-приложение работает корректно.

Создадим файл с переменными .env:

``` env
USERNAME=windemiatrix
```

Создадим docker-compose.override.yml для reddit проекта, который позволит

* Изменять код каждого из приложений, не выполняя сборку образа
* Запускать puma для руби приложений в дебаг режиме с двумя воркерами (флаги --debug и -w 2)

# Домашнее задание по GitLab CI

## Создание виртуальной машины

Для создания виртуальной машины воспользуемся `terraform`. При создании виртуальной машины `terraform` создает файл `ansible/inventory` для дальнейшего запуска плейбука.

Плейбук `ansible` устанавливает необходимые компоненты на созданную виртуальную машину и запускает GitLab.

Далее... скачиваем приложение с репозитория в домашнем задании, выполняем феерические кульбиты в попытке его запустить и изменяем код, чтобы выполнение `pipelanes` ограничивалось командами `echo`, к примеру. А все потому, что это приложение написано криво под старую версию `ruby`, а в инструкциях указан образ `alpine`, в котором `ruby` отсутствует по определению.

Боль и страдания.

Кроме того, в конце домашнего задания выясняется, что `gitlab-ci` необходимо было развернуть с помощью `docker-compose` несмотря на инструкции в начале задания.

`GitLab` - круто. Задание - нет. Если читаешь это... удачи!

# Введение в мониторинг. Модели и принципы работы систем мониторинга

## План

* Prometheus: запуск, конфигурация, знакомство с
Web UI
* Мониторинг состояния микросервисов
* Сбор метрик хоста с использованием экспортера
* Задания со *

## Подготовка окружения

Выберем проект в GCP

``` bash
gcloud config set project docker-301310
export GOOGLE_PROJECT=docker-301310
```
Создадим правило фаервола для Prometheus и Puma:

``` bash
gcloud compute firewall-rules create prometheus-default --allow tcp:9090
gcloud compute firewall-rules create puma-default --allow tcp:9292
```

Создадим Docker хост в GCE и настроим локальное окружение на работу с ним

``` bash
# create docker host
docker-machine create --driver google \
    --google-machine-image https://www.googleapis.com/compute/v1/projects/ubuntu-os-cloud/global/images/family/ubuntu-1604-lts \
    --google-machine-type n1-standard-1 \
    --google-zone europe-west1-b \
    docker-host

# configure local env
eval $(docker-machine env docker-host)
```

Систему мониторинга Prometheus будем запускать внутри Docker контейнера. Для начального знакомства воспользуемся готовым образом с DockerHub.

``` bash
$ docker run --rm -p 9090:9090 -d --name prometheus  prom/prometheus

$ docker ps
CONTAINER ID        IMAGE               COMMAND                  CREATED              STATUS              PORTS                    NAMES
8e942808e1af        prom/prometheus     "/bin/prometheus --c…"   About a minute ago   Up About a minute   0.0.0.0:9090->9090/tcp   prometheus

$ docker-machine ip docker-host
35.195.94.46
```

Откроем в браузере приложение `prometeus`: http://35.195.94.46:9090

Нажмем на кнопку `Classic UI`. Выберем метрику `prometheus_build_info` и нажмем `Execute`:

``` json
prometheus_build_info{branch="HEAD",goversion="go1.15.6",instance="localhost:9090",job="prometheus",revision="e4487274853c587717006eeda8804e597d120340",version="2.24.1"}
```

* `prometheus_build_info` - идентификатор собранной метрики
* `branch`, `goversion` , ... - добавляет метаданных метрике, уточняет ее.

Использование лейблов дает нам возможность не ограничиваться лишь одним названием метрик для идентификации получаемой информации. Лейблы содержаться в {} скобках и представлены наборами "ключ=значение".

Значение метрики - численное значение метрики, либо NaN, если значение недоступно.

## Targets

Targets (цели) - представляют собой системы или процессы, за которыми следит Prometheus. Помним, что Prometheus является pull системой, поэтому он постоянно делает HTTP запросы на имеющиеся у него адреса (endpoints). Посмотрим текущий список целей (`Status` - `Targets`).

В Targets сейчас мы видим только сам Prometheus. У каждой цели есть свой список адресов (endpoints), по которым следует обращаться для получения информации.

В веб интерфейсе мы можем видеть состояние каждого endpoint-а (up); лейбл (instance="someURL"), который Prometheus автоматически добавляет к каждой метрике, получаемой с данного endpoint-а; а также время, прошедшее с момента последней операции сбора информации с endpoint-а.

Также здесь отображаются ошибки при их наличии и можно отфильтровать только неживые таргеты.

Обратите внимание на `endpoint`. Мы можем открыть страницу в веб браузере по данному HTTP пути (host:port/metrics), чтобы посмотреть, как выглядит та информация, которую собирает Prometheus.

``` bash
# HELP go_gc_duration_seconds A summary of the pause duration of garbage collection cycles.
# TYPE go_gc_duration_seconds summary
go_gc_duration_seconds{quantile="0"} 1.9306e-05
go_gc_duration_seconds{quantile="0.25"} 2.8606e-05
go_gc_duration_seconds{quantile="0.5"} 7.6798e-05
go_gc_duration_seconds{quantile="0.75"} 8.0965e-05
go_gc_duration_seconds{quantile="1"} 0.000105957
go_gc_duration_seconds_sum 0.000999092
go_gc_duration_seconds_count 15
# HELP go_goroutines Number of goroutines that currently exist.
# TYPE go_goroutines gauge
go_goroutines 32
# HELP go_info Information about the Go environment.
# TYPE go_info gauge
go_info{version="go1.15.6"} 1
# HELP go_memstats_alloc_bytes Number of bytes allocated and still in use.
# TYPE go_memstats_alloc_bytes gauge
go_memstats_alloc_bytes 1.6491544e+07
...
```

Остановим контейнер

``` bash
docker stop prometheus
```

## Переупорядочим структуру директорий

До перехода к следующему шагу приведем структуру каталогов в более
четкий/удобный вид:

1. Создадим директорию docker в корне репозитория и перенесем в нее директорию docker-monolith и файлы docker-compose.* и все .env (.env должен быть в .gitgnore), в репозиторий закоммичен .env.example, из которого создается .env
2. Создадим в корне репозитория директорию monitoring. В ней будет хранится все, что относится к мониторингу
3. Не забываем про .gitgnore и актуализируем записи при необходимости

P.S. С этого момента сборка сервисов отделена от docker-compose, поэтому инструкции build можно удалить из docker-compose.yml.

## Создание Docker образа

Познакомившись с веб интерфейсом Prometheus и его стандартной конфигурацией, соберем на основе готового образа с DockerHub свой Docker образ с конфигурацией для мониторинга наших микросервисов.

Создайте директорию monitoring/prometheus. Затем в этой директории создайте простой Dockerfile, который будет копировать файл конфигурации с нашей машины внутрь контейнера:

`monitoring/prometheus/Dockerfile`:

``` dockerfile
FROM prom/prometheus:v2.1.0
ADD prometheus.yml /etc/prometheus/
```

## Конфигурация

Вся конфигурация Prometheus, в отличие от многих других систем мониторинга, происходит через файлы конфигурации и опции командной строки.

Мы определим простой конфигурационный файл для сбора метрик с наших микросервисов. В директории `monitoring/prometheus` создайте файл `prometheus.yml` со следующим содержимым.

``` yml
---
global:
  scrape_interval: '5s' # с какой частотой собирать метрики

scrape_configs:
  - job_name: 'prometheus' # jobs объединяют в группы endpoint, выполняющие одинаковую функцию
    static_configs:
      - targets:
        - 'localhost:9090' # Адреса для сбора метрик (endpoints)

  - job_name: 'ui'
    static_configs:
      - targets:
        - 'ui:9292'

  - job_name: 'comment'
    static_configs:
      - targets:
        - 'comment:9292'
...
```

В директории prometheus собираем Docker образ:

``` bash
$ export USER_NAME=windemiatrix
$ docker build -t $USER_NAME/prometheus .
```

Где USER_NAME - ВАШ логин от DockerHub.

В конце занятия нужно будет запушить на DockerHub собранные вами на этом занятии образы. 

## Образы микросервисов

В коде микросервисов есть healthcheck-и для проверки работоспособности приложения.

Сборку образов теперь необходимо производить при помощи скриптов docker_build.sh, которые есть в директории каждого сервиса. С его помощью мы добавим информацию из Git в наш healthcheck.

Выполните сборку образов из корня репозитория: 

``` bash
for i in ui post-py comment; do cd src/$i; bash docker_build.sh; cd -; done
```

## docker-compose.yml

Будем поднимать наш Prometheus совместно с микросервисами. Определите в вашем `docker/docker-compose.yml` файле новый сервис. 

``` yml
services:
...
  prometheus:
    image: ${USERNAME}/prometheus
    ports:
      - '9090:9090'
    volumes:
      - prometheus_data:/prometheus
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus' # Передаем доп. параметры в командной строке
      - '--storage.tsdb.retention=1d' # Задаем время хранения метрик в 1 день

volumes:
  prometheus_data:
```

Отметим, что сборка Docker образов с данного момента производится через скрипт docker_build.sh.

Поэтому удалите build директивы из docker_compose.yml и используйте директиву image.

Мы будем использовать Prometheus для мониторинга всех наших микросервисов, поэтому нам необходимо, чтобы контейнер с ним мог общаться по сети со всеми другими сервисами, определенными в компоуз файле.

Самостоятельно добавьте секцию networks в определение сервиса `Prometheus` в `docker/dockercompose.yml`. Также проверьте актуальность версий сервисов в .env и .env.example

``` yml
version: '3.3'
services:
  post_db:
    image: mongo:latest
    volumes:
      - post_db:/data/db
    networks:
      back_net:
        aliases:
          - post_db
          - comment_db
  ui:
    image: ${USERNAME:-rmartsev}/ui
    ports:
      - 9292:9292/tcp
    networks:
      front_net:
        aliases:
          - ui
  post:
    image: ${USERNAME:-rmartsev}/post
    networks:
      back_net:
        aliases:
          - post
      front_net:
        aliases:
          - post
  comment:
    image: ${USERNAME:-rmartsev}/comment
    networks:
      back_net:
        aliases:
          - prom
      front_net:
        aliases:
          - prom
  prometheus:
    image: ${USERNAME:-rmartsev}/prometheus
    ports:
      - '9090:9090'
    volumes:
      - prometheus_data:/prometheus
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus' # Передаем доп. параметры в командной строке
      - '--storage.tsdb.retention=1d' # Задаем время хранения метрик в 1 день
    networks:
      - front_net
      - back_net

volumes:
  post_db:
  prometheus_data:

networks:
  front_net:
  back_net:
```

## Запуск микросервисов

Поднимем сервисы, определенные в docker/dockercompose.yml

``` bash
$ docker-compose up -d
```

Проверьте, что приложение работает и Prometheus запустился: `http://35.195.94.46:9292`, `http://35.195.94.46:9090`

## Мониторинг состояния микросервисов

### Список endpoint-ов

Посмотрим список endpoint-ов, с которых собирает информацию Prometheus. Помните, что помимо самого Prometheus, мы определили в конфигурации мониторинг ui и comment сервисов. Endpoint-ы должны быть в состоянии UP.

### Healthchecks

Healthcheck-и представляют собой проверки того, что наш сервис здоров и работает в ожидаемом режиме. В нашем случае healthcheck выполняется внутри кода микросервиса и выполняет проверку того, что все сервисы, от которых зависит его работа, ему доступны.

Если требуемые для его работы сервисы здоровы, то healthcheck проверка возвращает status = 1, что соответсвует тому, что сам сервис здоров. 

#### Состояние сервиса UI

В веб интерфейсе Prometheus выполните поиск по названию метрики ui_health. Видим, что статус UI сервиса был стабильно 1, что означает, что сервис работал. Данный график оставьте открытым. 

#### Остановим post сервис

Мы говорили, что условились считать сервис здоровым, если все сервисы, от которых он зависит также являются здоровыми.

Попробуем остановить сервис post на некоторое время и проверим, как изменится статус ui сервиса, который зависим от post.

``` bash
docker-compose stop post 
```

Обновим наш график. Метрика изменила свое значение на 0, что означает, что UI сервис стал нездоров.

#### Поиск проблемы

Помимо статуса сервиса, мы также собираем статусы сервисов, от которых он зависит. Названия метрик, значения которых соответствует данным статусам, имеет формат ui_health_<service-name>.

Посмотрим, не случилось ли чего плохого с сервисами, от которых зависит UI сервис.

Наберем в строке выражений ui_health_ и Prometheus нам предложит дополнить названия метрик.

Проверим comment сервис. Видим, что сервис свой статус не менял в данный промежуток времени. А с post сервисом все плохо.

#### Чиним

Проблему мы обнаружили и знаем, как ее поправить (ведь мы же ее и создали). Поднимем post сервис.

``` bash
$ docker-compose start post
Starting post ... done
```

Post и ui сервисы поправились.

## Сбор метрик хоста

### Exporters

Экспортер похож на вспомогательного агента для сбора метрик.

В ситуациях, когда мы не можем реализовать отдачу метрик Prometheus в коде приложения, мы можем использовать экспортер, который будет транслировать метрики приложения или системы в формате доступном для чтения Prometheus.

* Программа, которая делает метрики доступными для сбора Prometheus
* Дает возможность конвертировать метрики в нужный для Prometheus формат
* Используется когда нельзя поменять код приложения
* Примеры: PostgreSQL, RabbitMQ, Nginx, Node exporter, cAdvisor

### Node exporter

Воспользуемся Node экспортер для сбора информации о работе Docker хоста (виртуалки, где у нас запущены контейнеры) и предоставлению этой информации в Prometheus.

Node экспортер будем запускать также в контейнере. Определим еще один сервис в `docker/docker-compose.yml` файле. Не забудьте также добавить определение сетей для сервиса node-exporter, чтобы обеспечить доступ Prometheus к экспортеру. 

``` yml
  node-exporter:
    image: prom/node-exporter:v0.15.2
    user: root
    volumes:
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro
      - /:/rootfs:ro
    command:
      - '--path.procfs=/host/proc'
      - '--path.sysfs=/host/sys'
      - '--collector.filesystem.ignored-mount-points="^/(sys|proc|dev|host|etc)($$|/)"'
    networks:
      back_net:
        aliases:
          - node
      front_net:
        aliases:
          - node
```

Чтобы сказать Prometheus следить за еще одним сервисом, нам нужно добавить информацию о нем в конфиг.

Добавим еще один job: 

``` yml
  - job_name: 'node'
    static_configs:
      - targets:
        - 'node-exporter:9100' 
```

Пересоберем докер образ:

``` bash
docker build -t $USER_NAME/prometheus .
```

Пересоздадим наши сервисы

``` bash
docker-compose down
docker-compose up -d
```

Посмотрим, список endpoint-ов Prometheus - должен появится еще один endpoint.

Получим информацию об использовании CPU, для этого воспользуемся метрикой node_load1.

Проверим мониторинг

* Зайдем на хост: `docker-machine ssh docker-host`
* Добавим нагрузки: `yes > /dev/null`

Нагрузка выросла, мониторинг отображает повышение загруженности CPU

## Завершение работы

Запушьте собранные вами образы на DockerHub:

``` bash
$ docker login
Login Succeeded
$ docker push $USER_NAME/ui
$ docker push $USER_NAME/comment
$ docker push $USER_NAME/post
$ docker push $USER_NAME/prometheus
```

• Удалите виртуалку:
$ docker-machine rm docker-host

# Мониторинг приложения и инфраструктуры

## План

* Мониторинг Docker контейнеров
* Визуализация метрик
* Сбор метрик работы приложения и бизнес метрик
* Настройка и проверка алертинга
* Много заданий со ⭐ (необязательных)

## Подготовка окружения

1. Открывать порты в файрволле для новых сервисов нужно самостоятельно по мере их добавления.
2. Создадим Docker хост в GCE и настроим локальное окружение на работу с ним:

``` bash
export GOOGLE_PROJECT=docker-301310

# Создать докер хост
docker-machine create --driver google \
    --google-machine-image https://www.googleapis.com/compute/v1/projects/ubuntu-os-cloud/global/images/family/ubuntu-1604-lts \
    --google-machine-type n1-standard-1 \
    --google-zone europe-west1-b \
    docker-host

# Настроить докер клиент на удаленный докер демон
eval $(docker-machine env docker-host)

docker-machine ip docker-host
```

Разделим файлы Docker Compose:

В данный момент и мониторинг и приложения у нас описаны в одном большом docker-compose.yml. С одной стороны это просто, а с другой - мы смешиваем различные сущности, и сам файл быстро растет.

Оставим описание приложений в `docker-compose.yml`, а мониторинг выделим в отдельный файл `docker-compose-monitoring.yml`.

Для запуска приложений будем как и ранее использовать `docker-compose up -d`, а для мониторинга - `docker-compose -f docker-compose-monitoring.yml up -d`.

## cAdvisor

Мы будем использовать cAdvisor для наблюдения за состоянием наших Docker контейнеров.

cAdvisor собирает информацию о ресурсах потребляемых контейнерами и характеристиках их работы.

Примерами метрик являются:

* процент использования контейнером CPU и памяти, выделенные для его запуска,
* объем сетевого трафика
* и др.

cAdvisor также будем запускать в контейнере. Для этого добавим новый сервис в наш компоуз файл мониторинга `docker/docker-compose-monitoring.yml`:

``` yml
version: '3.3'
services:
  cadvisor:
    image: google/cadvisor:v0.29.0
    volumes:
      - '/:/rootfs:ro'
      - '/var/run:/var/run:rw'
      - '/sys:/sys:ro'
      - '/var/lib/docker/:/var/lib/docker:ro'
    ports:
      - '8080:8080'
    networks:
      back_net:
        aliases:
          - cadvisor

networks:
  back_net:
```

Поместим данный сервис в одну сеть с Prometheus, чтобы тот мог собирать с него метрики.

Добавим информацию о новом сервисе в конфигурацию Prometheus, чтобы он начал собирать метрики `monitoring/prometheus/prometheus.yml`:

``` yml
---
global:
  scrape_interval: '5s'

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets:
        - 'localhost:9090'

  - job_name: 'ui'
    static_configs:
      - targets:
        - 'ui:9292'

  - job_name: 'comment'
    static_configs:
      - targets:
        - 'comment:9292'

  - job_name: 'node'
    static_configs:
      - targets:
        - 'node-exporter:9100'

  - job_name: 'cadvisor'
    static_configs:
      - targets:
        - 'cadvisor:8080'
...
```

Пересоберем образ Prometheus с обновленной конфигурацией:

``` bash
cd ./monitoring/prometheus
export USER_NAME=windemiatrix 
docker build -t ${USER_NAME}/prometheus .
cd ../../
```

## cAdvisor UI

Запустим сервисы:

``` bash
cd ./docker
docker-compose up -d
docker-compose -f docker-compose-monitoring.yml up -d
cd ../
```

cAdvisor имеет UI, в котором отображается собираемая о контейнерах информация.

Откроем страницу Web UI по адресу http://35.195.157.109:8080

Не открывается. Скорее всего, у нас не открыты порты. Разумеется, открывать руками мы их не будем. Воспользуемся написанным IaC для `terraform` и автоматизируем работу.

В директорию `docker` добавим две директории: `ansible` и `terraform` для развертывания в облаке виртуальной машины. Описывать конфигурацию не буду. Terraform создает в облаке виртуальную машину, далее в качестве провижинера выступает `ansible`, устанавливающий докер на машину, копирующий файлы проекта в директорию `opt` и запускающий `docker-compose`.

На всякий случай, файл `docker/terraform/main.tf`:

``` terraform
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
    tags = ["allow-http", "allow-https", "allow-tcp-8080", "allow-tcp-9090", "allow-tcp-9292"]
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
```

Файл `docker/terraform/output.tf`:

```
output "gitlab_external-ip" {
    value = google_compute_instance.docker.network_interface.0.access_config.0.nat_ip
}
```

Файл `docker/terraform/varoables.tf`:

``` terraform
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
variable private_key_path {
  # Описание переменной
  description = "Path to the private key used for ssh access"
}
variable disk_image {
  description = "Disk image"
}
```

Файл `docker/terraform/terraform.tfvars`:

``` terraform
project = "xxx"
public_key_path = "~/.ssh/id_rsa.pub"
private_key_path = "~/.ssh/id_rsa"
disk_image = "ubuntu-minimal-2004-lts"
```

Файл `docker/ansible/install-docker.yml`:

``` yml
---
- hosts: docker_public
  become: true

  tasks:

    - name: Add an Apt signing key, uses whichever key is at the URL
      ansible.builtin.apt_key:
        url: https://download.docker.com/linux/ubuntu/gpg
        state: present

    - name: Add docker repository into sources list
      ansible.builtin.apt_repository:
        repo: deb [arch=amd64] https://download.docker.com/linux/ubuntu focal stable
        state: present

    - name: install docker
      package:
        name:
          - docker-ce
          - docker-ce-cli
          - containerd.io
          - docker-compose
          - net-tools
          - telnet
        state: present

    - name: Copy files with prometheus
      ansible.builtin.copy:
        directory_mode: 0777
        src: ../../monitoring/prometheus
        dest: /opt/
        mode: 0666

    - name: Run docker with prometheus
      raw: cd /opt/prometheus && export USER_NAME=windemiatrix && docker build -t ${USER_NAME}/prometheus .

    - name: Copy files with services
      ansible.builtin.copy:
        src: "{{ item }}"
        dest: /opt/
        mode: 0666
      with_fileglob:
        - ../docker-compose-monitoring.yml
        - ../docker-compose.yml
        - ../.env

    - name: Run the service defined in docker-compose.yml and docker-compose-monitoring.yml files
      docker_compose:
        project_src: /opt/
        files:
          - docker-compose.yml
          - docker-compose-monitoring.yml
        state: present
```

Файл `docker/ansible/inventory.tmpl`:

```
[t_public]
docker_public ansible_host=${docker_public}

[t_private]
docker_private ansible_host=${docker_internal}
```

IP адрес поменялся. Откроем страницу Web UI по адресу http://35.195.157.109:8080. Работает. Ура.

На данной странице мы видим всевозможную информацию по контейнерам. 

На странице http://35.195.157.109:8080/metrics отображается информация по собираемым и публикуемым метрикам.

На странице http://35.195.157.109:9090/ проверим, что метрики собираются в `prometheus`.

## Визуализация метрик: Grafana

Используем инструмент Grafana для визуализации данных из Prometheus.

Добавим новый сервис в `docker-compose-monitoring.yml`:

``` yml
services:

  grafana:
    image: grafana/grafana:5.0.0
    volumes:
      - grafana_data:/var/lib/grafana
    environment:
      - GF_SECURITY_ADMIN_USER=admin
      - GF_SECURITY_ADMIN_PASSWORD=secret
    depends_on:
      - prometheus
    ports:
      - 3000:3000
    networks:
      back_net:
        aliases:
          - grafana

volumes:
  grafana_data:
```

Также внесем изменения в файл `docker/terragorm/mail.tf`:

```
...
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
...
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
...
```

И выполним команды для пересоздания окружения:

``` bash
terraform destroy
terraform apply
```

IP адрес изменился.

Графана доступна по адресу: http://35.195.3.24:3000/.

## Grafana: Добавление источника данных

Нажмем Add data source (Добавить источник данных).

Зададим нужный тип и параметры подключения:

* Name: Prometheus Server
* Type: Prometheus
* URL: http://prometheus:9090
* Access: Proxy

И затем нажмем `Save & test`.

## Импорт дашборда

Перейдем на [сайт Grafana](https://grafana.com/dashboards), где можно найти и скачать большое количество уже созданных официальных и комьюнити дашбордов для визуализации различного типа метрик для разных систем мониторинга и баз данных.

Выберем в качестве источника данных нашу систему мониторинга (Prometheus) и выполним поиск по категории Docker. Затем выберем популярный дашборд (Docker and system monitoring).

Нажмем `Загрузить JSON`. В директории `monitoring` создадим директории `grafana/dashboards`, куда поместим скачанный дашборд. Поменяем название файла дашборда на `DockerMonitoring.json`.

Снова откроем веб-интерфейс Grafana и выберем импорт шаблона (Import). Загрузим скачанный дашборд. При загрузке укажем источник данных для визуализации (Prometheus Server). Должен появиться набор графиков с информацией о состоянии хостовой системы и работе контейнеров.

## Мониторинг работы приложения

В качестве примера метрик приложения в сервис UI добавлены:

* счетчик ui_request_count, который считает каждый приходящий HTTP-запрос (добавляя через лейблы такую информацию как HTTP метод, путь, код возврата, мы уточняем данную метрику)
* гистограмма ui_request_latency_seconds, которая позволяет отслеживать информацию о времени обработки каждого запроса

В качестве примера метрик приложения в сервис Post добавлены:

* гистограмма post_read_db_seconds, которая позволяет
* отслеживание информации о времени требуемом для поиска поста в БД

Созданные метрики придадут видимости работы нашего приложения и понимания, в каком состоянии оно сейчас находится.

Например, время обработки HTTP запроса не должно быть большим, поскольку это означает, что пользователю приходится долго ждать между запросами, и это ухудшает его общее впечатление от работы с приложением. Поэтому большое время обработки запроса будет для нас сигналом проблемы.

Отслеживая приходящие HTTP-запросы, мы можем, например, посмотреть, какое количество ответов возвращается с кодом ошибки. Большое количество таких ответов также будет служить для нас сигналом проблемы в работе приложения.

## prometheus.yml

Добавим информацию о post-сервисе в конфигурацию Prometheus, чтобы он начал собирать метрики и с него:

``` yml
...
  - job_name: 'post'
    static_configs:
      - targets:
        - 'post:5000'
...
```

Пересоберем образ Prometheus с обновленной конфигурацией, для этого выполним:

``` bash
terraform destroy
terraform apply
```

Создадим несоклько постов для метрик: http://35.195.157.109:9292/new

## Создание дашборда в Grafana

Еще раз нажмем Add data source (Добавить источник данных).

Зададим нужный тип и параметры подключения:

* Name: Prometheus Server
* Type: Prometheus
* URL: http://prometheus:9090
* Access: Proxy

Построим графики собираемых метрик приложения. Выберем создать новый дашборд: Снова откроем вебинтерфейс Grafana и выберем создание шаблона (Dashboard).

1. Выбираем "Построить график" (New Panel ➡ Graph)
2. Жмем один раз на имя графика (Panel Title), затем выбираем Edit:

Построим для начала простой график изменения счетчика HTTP-запросов по времени. Выберем источник данных и в поле запроса введем название метрики.

Далее достаточно нажать мышкой на любое место UI, чтобы убрать курсор из поля запроса, и Grafana выполнит запрос и построит график.

Сохраним дашборд.

Построим график запросов, которые возвращают код ошибки на этом же дашборде. Добавим еще один график на наш дашборд. Переходим в режим правки графика.

В поле запросов запишем выражение для поиска всех http запросов, у которых код возврата начинается либо с 4 либо с 5 (используем регулярное выражения для поиска по лейблу). Будем использовать функцию rate(), чтобы посмотреть не просто значение счетчика за весь период наблюдения, но и скорость увеличения данной величины за промежуток времени (возьмем, к примеру 1-минутный интервал, чтобы график был хорошо видим).

В качестве метрики укажем выражение: `rate(ui_request_count{http_status=~"^[45].*"}[1m])`.

График ничего не покажет, если не было запросов с ошибочным кодом возврата. Для проверки правильности нашего запроса обратимся по несуществующему HTTP пути, например, http://35.195.157.109:9292/nonexistent, чтобы получить код ошибки 404 в ответ на наш запрос.

Проверим график (временной промежуток можно уменьшить для лучшей видимости графика). Данные отображаются. Сохраним график.

Grafana поддерживает версионирование дашбордов, именно поэтому при сохранении нам предлагалось ввести сообщение, поясняющее изменения дашборда. Вы можете посмотреть историю изменений своего

## Самостоятельно

Как вы можете заметить, первый график, который мы сделали просто по ui_request_count не отображает никакой полезной информации, т.к. тип метрики count, и она просто растет. Задание:

Используйте для первого графика (UI http requests) функцию rate аналогично второму графику (Rate of UI HTTP Requests with Error).

Создадим панель с выражением: `rate(ui_request_count[1m])`.

## Гистограмма

Гистограмма представляет собой графический способ представления распределения вероятностей некоторой случайной величины на заданном промежутке значений. Для построения гистограммы берется интервал значений, который может принимать измеряемая величина и разбивается на промежутки (обычно одинаковой величины), данные промежутки помечаются на горизонтальной оси X. Затем над каждым интервалом рисуется прямоугольник, высота которого соответствует числу измерений величины, попадающих в данный интервал.

Простым примером гистограммы может быть распределение оценок за контрольную в классе, где учится 21 ученик. Берем промежуток возможных значений (от 1 до 5) и разбиваем на равные интервалы. Затем на каждом интервале рисуем столбец, высота которого соответсвует частоте появлению данной оценки.

## Histogram метрика

В Prometheus есть тип метрик histogram. Данный тип метрик в качестве своего значение отдает ряд распределения измеряемой величины в заданном интервале значений. Мы используем данный тип метрики для измерения времени обработки HTTP запроса нашим приложением.

Рассмотрим пример гистограммы в Prometheus. Посмотрим информацию по времени обработки запроса приходящих на главную страницу приложения.

`ui_request_latency_seconds_bucket{path="/"}`

Эти значения означают, что запросов с временем обработки <= 0.025s было 3 штуки, а запросов 0.01 <= 0.01s было 7 штук (в этот столбец входят 3 запроса из предыдущего столбца и 4 запроса из промежутка [0.025s; 0.01s], такую гистограмму еще называют кумулятивной). Запросов, которые бы заняли > 0.01s на обработку не было, поэтому величина всех последующих столбцов равна 7.

## Алертинг

### Правила алертинга

Мы определим несколько правил, в которых зададим условия состояний наблюдаемых систем, при которых мы должны получать оповещения, т.к. заданные условия могут привести к недоступности или неправильной работе нашего приложения.

P.S. Стоит заметить, что в самой Grafana тоже есть alerting. Но по функционалу он уступает Alertmanager в Prometheus.

### Alertmanager

Alertmanager - дополнительный компонент для системы мониторинга Prometheus, который отвечает за первичную обработку алертов и дальнейшую отправку оповещений по заданному назначению.

Создайте новую директорию monitoring/alertmanager. В этой директории создайте Dockerfile со следующим содержимым:

``` yml
FROM prom/alertmanager:v0.14.0
ADD config.yml /etc/alertmanager/
```

Настройки Alertmanager-а как и Prometheus задаются через YAML файл или опции командой строки. В директории monitoring/alertmanager создайте файл config.yml, в котором определите отправку нотификаций в ВАШ тестовый слак канал. Для отправки нотификаций в слак канал потребуется создать СВОЙ Incoming Webhook monitoring/alertmanager/config.yml

``` yml
global:
  slack_api_url: 'https://hooks.slack.com/services/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'

route:
  receiver: 'slack-notifications'

receivers:
- name: 'slack-notifications'
  slack_configs:
  - channel: '#devops'
```

Создадим файл `alerts.yml` в директории prometheus, в котором определим условия при которых должен срабатывать алерт и посылаться Alertmanager-у. Мы создадим простой алерт, который будет срабатывать в ситуации, когда одна из наблюдаемых систем (endpoint) недоступна для сбора метрик (в этом случае метрика up с лейблом instance равным имени данного эндпоинта будет равна нулю). Выполните запрос по имени метрики up в веб интерфейсе Prometheus, чтобы убедиться, что сейчас все эндпоинты доступны для сбора метрик:

``` yml
groups:
  - name: alert.rules
    rules:
    - alert: InstanceDown
      expr: up == 0
      for: 1m
      labels:
        severity: page
      annotations:
        description: '{{ $labels.instance }} of job {{ $labels.job }} has been down for more than 1 minute'
        summary: 'Instance {{ $labels.instance }} down'
```

Добавим операцию копирования данного файла в Dockerfile: `monitoring/prometheus/Dockerfile`

``` dockerfile
FROM prom/prometheus:v2.1.0
ADD prometheus.yml /etc/prometheus/
ADD alerts.yml /etc/prometheus/
```

Добавим информацию о правилах в конфиг `Prometheus`:

``` yml
rule_files:
  - "alerts.yml"

alerting:
  alertmanagers:
  - scheme: http
    static_configs:
    - targets:
      - "alertmanager:9093"
```

Перезапустим окружение terraform... Молимся!

Вроде, заработало, ура. Алерты можно посмотреть в веб интерфейсе Prometheus: http://35.195.3.24:9090/alerts.

Оставлю это тут, пригодится: https://github.com/Otus-DevOps-2019-08/sgremyachikh_microservices
