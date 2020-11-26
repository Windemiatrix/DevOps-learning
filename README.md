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
$ packer build ubuntu16.json
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


