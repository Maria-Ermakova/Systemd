#!/bin/bash

su -

cat > /etc/default/watchlog >> EOF
# Configuration file for my watchlog service
# Place it to /etc/default
# File and word in that file that we will be monit
WORD="ALERT"
LOG=/var/log/watchlog.log
EOF

cat > /var/log/watchlog.log >> EOF
ALERT
EOF

cat > /opt/watchlog.sh >> EOF
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
EOF

chmod +x /opt/watchlog.sh

cat > /etc/systemd/system/watchlog.service >> EOF
[Unit]
Description=My watchlog service

[Service]
Type=oneshot
EnvironmentFile=/etc/default/watchlog
ExecStart=/opt/watchlog.sh $WORD $LOG
EOF

cat > /etc/systemd/system/watchlog.timer >> EOF
[Unit]
Description=Run watchlog script every 30 second

[Timer]
# Run every 30 second
OnCalendar=*:*:0/30 
Unit=watchlog.service

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl start watchlog.timer
