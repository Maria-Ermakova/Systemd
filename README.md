# Systemd
Create units
1.Написать service, который будет раз в 30 секунд мониторить лог на предмет наличия ключевого слова

#Для начала создаём файл с конфигурацией для сервиса в директории /etc/default - из неё сервис будет брать необходимые переменные.

nano /etc/default/watchlog
# Configuration file for my watchlog service
# Place it to /etc/default

# File and word in that file that we will be monit
WORD="ALERT"
LOG=/var/log/watchlog.log

#создаем /var/log/watchlog.log с ключевым словом ‘ALERT’
nano /var/log/watchlog.log

#Создадим скрипт. Команда logger отправляет лог в системный журнал (syslog):
cat > /opt/watchlog.sh 
Enter
#!/bin/bash

WORD=$1
LOG=$2
DATE=`date`

if grep $WORD $LOG &> /dev/null
then
logger "$DATE: I found word, Master!"
else
exit 0
fi
Ctrl+D

#Добавим права на запуск файла:
chmod +x /opt/watchlog.sh

#Создадим юнит для сервиса:
nano /etc/systemd/system/watchlog.service

[Unit]
Description=My watchlog service

[Service]
Type=oneshot
EnvironmentFile=/etc/default/watchlog
ExecStart=/opt/watchlog.sh $WORD $LOG

#Создадим юнит для таймера:
cat > /etc/systemd/system/watchlog.timer
Enter
[Unit]
Description=Run watchlog script every 30 second

[Timer]
# Run every 30 second
OnUnitActiveSec=30 
#OnCalendar=*:*:0/30 - не тебует ручного запуска сервиса
Unit=watchlog.service

[Install]
WantedBy=multi-user.target
Ctrl+D

#после внесения изменений в конфигурации юнитов
systemctl daemon-reload

#Запустим сервис (это необходимо, тк параметр OnUnitActiveSec=30 означает, то запуск сервиса будет происходить по таймеру каждые 30 сек с момента последней активации сервиса)
systemctl start watchlog.service

#Запустим таймер
systemctl start watchlog.timer

#проверим результат
tail -n 1000 /var/log/syslog  | grep word

_______________________________________________

2.Установить spawn-fcgi и создать unit-файл (spawn-fcgi.sevice) с помощью переделки init-скрипта

#FastCGI — это протокол для взаимодействия веб-сервера с приложениями (например, PHP). В отличие от обычного CGI, который создает новый процесс на каждый запрос, FastCGI процессы постоянно #запущены и обрабатывают запросы многократно, что значительно быстрее.
#spawn-fcgi — это утилита, которая:
#Запускает FastCGI-приложения
#Управляет процессами (создает пул процессов)
#Создает сокет для связи с веб-сервером

#Устанавливаем spawn-fcgi и необходимые для него пакеты:
#spawn-fcgi — сама утилита для запуска FastCGI процессов (установка предоставляет только Исполняемый файл /usr/bin/spawn-fcgi)
#php, php-cgi, php-cli — интерпретатор PHP и его CGI-версия
#apache2 — веб-сервер
#libapache2-mod-fcgid — модуль Apache для работы с FastCGI
apt install spawn-fcgi php php-cgi php-cli apache2 libapache2-mod-fcgid -y

#Сам Init скрипт, который будем переписывать, можно найти здесь: https://gist.github.com/cea2k/1318020 

#перед этим необходимо создать файл /etc/spawn-fcgi/fcgi.conf.
#Подробно: разрешено запускать процессы ползователю (-u) и группе (-g) www-data, создать UNIX-сокет (-s $SOCKET) по этому пути /var/run/php-fcgi.sock, 
#создать сокет (если не указан, создает TCP-порт) (-S), Установить права на сокет (rw-------) (-M 0600), установить максимальное количество дочерних процессов (для PHP) (-C 32),
#Количество процессов для форка при запуске (-F 1), запускать (исполняемый файл) (-- /usr/bin/php-cgi)
mkdir /etc/spawn-fcgi
touch /etc/spawn-fcgi/fcgi.conf
cat > /etc/spawn-fcgi/fcgi.conf
Enter
# You must set some working options before the "spawn-fcgi" service will work.
# If SOCKET points to a file, then this file is cleaned up by the init script.
#
# See spawn-fcgi(1) for all possible options.
#
# Example :
SOCKET=/var/run/php-fcgi.sock
OPTIONS="-u www-data -g www-data -s $SOCKET -S -M 0600 -C 32 -F 1 -- /usr/bin/php-cgi"
Ctrl+D

#создадим юнит-файл:
nano /etc/systemd/system/spawn-fcgi.service
[Unit]
Description=Spawn-fcgi startup service by Otus
After=network.target

[Service]
Type=simple
#сюда spawn-fcgi запишет свой PID
PIDFile=/var/run/spawn-fcgi.pid
EnvironmentFile=/etc/spawn-fcgi/fcgi.conf
#-n — не уходить в фон (важно для systemd, чтобы он мог отслеживать процесс)
ExecStart=/usr/bin/spawn-fcgi -n $OPTIONS
#при остановке сервиса убивать только основной процесс, а не все его дочерние
KillMode=process

[Install]
WantedBy=multi-user.target

#Убеждаемся, что все успешно работает:

systemctl start spawn-fcgi
systemctl status spawn-fcgi

_____________________________________
3.Доработать unit-файл Nginx (nginx.service) для запуска нескольких инстансов сервера с разными конфигурационными файлами одновременно

#Ключевая идея: шаблон nginx@.service
#Символ @ в имени файла (nginx@.service) превращает его в шаблон. Это позволяет запускать множество экземпляров (instance) одного и того же сервиса с разными параметрами.
#Вы запускаете экземпляр командой systemctl start nginx@first.
#Часть после @ — first — становится специальной переменной окружения %I внутри unit-файла.
#Systemd подставляет %I во все места, где вы его укажете, создавая уникальные имена для каждого экземпляра.

#Установим Nginx из стандартного репозитория. Файл службы появится в системной директории и останется нетронутым в последствии /lib/systemd/system/nginx.service:
apt install nginx -y

#Для запуска нескольких экземпляров сервиса модифицируем исходный service для использования различной конфигурации, а также PID-файлов. Для этого создадим новый Unit для работы с шаблонами в /etc/systemd/system/nginx@.service, который переопределит системный файл /lib/systemd/system/nginx.service :
cat > /etc/systemd/system/nginx@.service
Enter
# Stop dance for nginx
# =======================
# ExecStop sends SIGSTOP (graceful stop) to the nginx process.
# If, after 5s (--retry QUIT/5) nginx is still running, systemd takes control
# and sends SIGTERM (fast shutdown) to the main process.
# After another 5s (TimeoutStopSec=5), and if nginx is alive, systemd sends
# SIGKILL to all the remaining processes in the process group (KillMode=mixed).
#
# nginx signals reference doc:
# http://nginx.org/en/docs/control.html

[Unit]
Description=A high performance web server and a reverse proxy server
Documentation=man:nginx(8)
After=network.target nss-lookup.target

[Service]
Type=forking
PIDFile=/run/nginx-%I.pid
ExecStartPre=/usr/sbin/nginx -t -c /etc/nginx/nginx-%I.conf -q -g 'daemon on; master_process on;'
ExecStart=/usr/sbin/nginx -c /etc/nginx/nginx-%I.conf -g 'daemon on; master_process on;'
ExecReload=/usr/sbin/nginx -c /etc/nginx/nginx-%I.conf -g 'daemon on; master_process on;' -s reload
ExecStop=-/sbin/start-stop-daemon --quiet --stop --retry QUIT/5 --pidfile /run/nginx-%I.pid
TimeoutStopSec=5
KillMode=mixed

[Install]
WantedBy=multi-user.target
Ctrl+D

#Далее необходимо создать два файла конфигурации (/etc/nginx/nginx-first.conf, /etc/nginx/nginx-second.conf). Их можно сформировать из стандартного конфига /etc/nginx/nginx.conf, с #модификацией путей до PID-файлов и разделением по портам:
cp /etc/nginx/nginx.conf /etc/nginx/nginx-first.conf
cp /etc/nginx/nginx.conf /etc/nginx/nginx-second.conf

nano /etc/nginx/nginx-first.conf
#c изменениями
pid /run/nginx-first.pid;

http {
…
	server {
		listen 9001;
	}
#include /etc/nginx/sites-enabled/*;
….
}

nano /etc/nginx/nginx-second.conf
#c изменениями
pid /run/nginx-second.pid;

http {
…
	server {
		listen 9002;
	}
#include /etc/nginx/sites-enabled/*;
….
}

#Этого достаточно для успешного запуска сервисов.
#Проверим работу:
systemctl start nginx@first
systemctl start nginx@second
systemctl status nginx@first
systemctl status nginx@second

#Проверить можно несколькими способами, например, посмотреть, какие порты слушаются Или просмотреть список процессов:
ss -tnulp | grep nginx
ps afx | grep nginx

#Если мы видим две группы процессов Nginx, то всё в порядке. Если сервисы не стартуют, смотрим их статус, ищем ошибки, проверяем ошибки в /var/log/nginx/error.log, а также в journalctl -u #nginx@first.
