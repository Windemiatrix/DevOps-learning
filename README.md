# Google Cloud Platform

## VM Instances

bastion - виртуальная машина с доступом в интернет\
Internal IP: 10.132.0.2\
External IP: 35.210.88.217

someinternalhost - виртуальная машина без доступа в интернет\
Internal IP: 10.132.0.3

# SSH

## Полезные команды SSH

`ssh-add -L` - список RSA ключей, добавленных в агент авторизации\
`ssh-add ~/.ssh/appuser` - добавить ключ RSA в агент авторизации\
`ssh -i ~/.ssh/appuser appuser@146.148.80.202` - подключиться по SSH к хосту с IP 146.148.80.202 с использованием ключа RSA\
`ssh -i ~/.ssh/appuser -A appuser@146.148.80.202` - подключиться по SSH к хосту с IP 146.148.80.202 с использованием ключа RSA и использованием SSH Agent Forwarding\

## Подключение по SSH через промежуточный хост

Для подключения через SSH шлюз с IP адресом 35.210.88.217 на SSH сервер с IP 10.132.0.3, на SSH сервере необходимо выполнить команду

```
ssh -J rmartsev@35.210.88.217 rmartsev@10.132.0.3
```

Таким образом можно подключаться через любое количество SSH шлюзов к SSH серверу, указывая их через запятую

```
ssh -J user@host1,user@host2 user@host3
```

Для подключения к серверу командой `ssh someinternalhost` добавим в файл `~/.ssh/config` строчки:

```
Host someinternalhost
    Hostname 10.132.0.3
    ProxyJump rmartsev@35.210.88.217
    User rmartsev
```

# Создание VPN сервера

Создаем файл `setupvpn.sh` в домашней папке со следующим содержимым:

```
cat <<EOF> setupvpn.sh
#!/bin/bash
echo "deb http://repo.mongodb.org/apt/ubuntu xenial/mongodb-org/3.4 multiverse" > /etc/apt/sources.list.d/mongodb-org-3.4.list
echo "deb http://repo.pritunl.com/stable/apt xenial main" > /etc/apt/sources.list.d/pritunl.list
apt-key adv --keyserver hkp://keyserver.ubuntu.com --recv 0C49F3730359A14518585931BC711F9BA15703C6
apt-key adv --keyserver hkp://keyserver.ubuntu.com --recv 7568D9BB55FF9E5287D586017AE645C0CF8E292A
apt-get --assume-yes update
apt-get --assume-yes upgrade
apt-get --assume-yes install pritunl mongodb-org
systemctl start pritunl mongod
systemctl enable pritunl mongod
EOF
```

Запускаем скрипт

```
$ sudo bash setupvpn.sh
```

Выполняем команду для генерации кода установки pritunl

```
$ sudo pritunl setup-key
```

Открываем в браузере ссылку `https://35.210.88.217/setup`, подставляем код установки и нажимаем `Save`

Набираем в консоли команду для генерации пары логина и пароля для доступа к веб-интерфейсу

```
$ sudo pritunl default-password
```

Авторизуемся в веб-интерфейсе с отображенными учетными данными. На вкладке `Users` добавляем организацию и пользователя внутри этой организации с логином `test` и пин-кодом `6214157507237678334670591556762`

На вкладке `Servers` добавляем сервер и привязываем к созданной организации.

Нажимаем `Start server`. Сервер поднят на порту UDP 11884.

## Настройка сетевого экрана

В Google Cloud Platform переходим в `VPC Network` -> `Firewall` и выбираем `Create Firewall rule`. Создаем разрешающее правило для пакетов UDP с номером порта 11884 для тега `udp-11884`. Присваиваем тег виртуальной машине `bastion`.

## Настройка VPN клиента

Через веб-интерфейс pritunl скачиваем конфигурационный файл пользователя `test` и добавляем его в клиент OpenVPN на локальной станции. Также указываем логин и пароль данного пользователя, заданные в веб-интерфейсе ранее.

## Настройка SSL сертификата для веб-интерфейса

Воспользуемся сервисом `xip.io`, с помощью которого будем использовать DNS имя для подключения к серверу `bastion` `35.210.88.217.xip.io`.

Сервис `pritunl` поддерживает функционал автоматического генерирования SSL сертификатов, для этого достаточно добавить в настройках доменное имя `35.210.88.217.xip.io`.

# Данные для тестирования

bastion_IP = 35.210.88.217

someinternalhost_IP = 10.132.0.2

# Установка gcloud SDK

Установка `gcloud SDK` описана на странице: [Google](https://cloud.google.com/sdk/docs/quickstart).

# Создание нового инстанса

Для создания нового инстанса воспользуемся командой gcloud CLI

```
gcloud compute instances create reddit-app\
  --boot-disk-size=10GB \
  --image-family ubuntu-1604-lts \
  --image-project=ubuntu-os-cloud \
  --machine-type=g1-small \
  --tags puma-server \
  --restart-on-failure
```

Результат выполнения команды:

```
NAME        ZONE            MACHINE_TYPE  PREEMPTIBLE  INTERNAL_IP  EXTERNAL_IP    STATUS
reddit-app  europe-west1-d  g1-small                   10.132.0.4   34.77.102.100  RUNNING
```

Обновляем индекс пакетов и устанавливаем Ruby и Bundler

```
$ sudo apt update
$ sudo apt install -y ruby-full ruby-bundler build-essential
```

Проверяем результат установки

```
rmartsev@reddit-app:~$ ruby -v
ruby 2.3.1p112 (2016-04-26) [x86_64-linux-gnu]
rmartsev@reddit-app:~$ bundler -v
Bundler version 1.11.2
```

Добавляем ключи и репозиторий MongoDB

```
$ sudo apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv D68FA50FEA312927
$ sudo bash -c 'echo "deb http://repo.mongodb.org/apt/ubuntu xenial/mongodb-org/3.2 multiverse" > /etc/apt/sources.list.d/mongodb-org-3.2.list'
```

ОБновляем индекс пакетов и установим mongo-db

```
$ sudo apt update
$ sudo apt install -y mongodb-org
```

Запустим MongoDB и добавим в автозапуск

```
$ sudo systemctl start mongod
$ sudo systemctl enable mongod
```

Проверяем работу демона

```
$ sudo systemctl status mongod
● mongod.service - High-performance, schema-free document-oriented database
   Loaded: loaded (/lib/systemd/system/mongod.service; enabled; vendor preset: enabled)
   Active: active (running) since Mon 2020-11-23 16:11:18 UTC; 2min 31s ago
     Docs: https://docs.mongodb.org/manual
 Main PID: 9360 (mongod)
   CGroup: /system.slice/mongod.service
           └─9360 /usr/bin/mongod --quiet --config /etc/mongod.conf
```

Копируем код приложения в домашний каталог

```
$ cd ~
$ git clone -b monolith https://github.com/express42/reddit.git
```

Переходим в каталог проекта и устанавливаем зависимости приложения

```
$ cd reddit && bundle install
```

Запускаем сервер приложения

```
$ puma -d
```

Проверяем, что сервер запустился и на каком порту прослушивает входящие соединения

```
$ ps aux | grep puma
rmartsev 10218  0.5  1.5 515448 26900 ?        Sl   16:17   0:00 puma 3.10.0 (tcp://0.0.0.0:9292) [reddit]
rmartsev 10253  0.0  0.0  12944  1028 pts/0    S+   16:18   0:00 grep --color=auto puma
```

Создаем правило сетевого экрана для порта TCP 9292 в консоли GCP.

Переходим в браузере по ссылке http://34.77.102.100:9292/ для проверки работоспособности сервиса.

# Дополнительное задание

Команда gcloud для запуска создания инстанса и передачи скрипта

```
gcloud compute instances create reddit-app\
  --boot-disk-size=10GB \
  --image-family ubuntu-1604-lts \
  --image-project=ubuntu-os-cloud \
  --machine-type=g1-small \
  --tags puma-server \
  --restart-on-failure \
  --metadata startup-script=./startup_script
```

Команда для создания правила сетевого экрана

```
gcloud compute 
  --project=infra-296308 
  firewall-rules create allow-tcp-9292 
  --direction=INGRESS 
  --priority=1000 
  --network=default 
  --action=ALLOW 
  --rules=tcp:9292 
  --source-ranges=0.0.0.0/0 
  --target-tags=tcp-9292
```

Данные для тестирования

testapp_IP = 34.77.102.100

testapp_port = 9292
