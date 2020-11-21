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

bastion_IP = 35.210.88.217\
someinternalhost_IP = 10.132.0.2
