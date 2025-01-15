#!/bin/bash
# Version:     0.2
# Description: Script collect all configs to the same directory and pushs them to the Git-repository
# Deploying:   1. Make dir:
#                     mkdir -p /home/dove/backup; cd /home/dove/backup
#              2. Clone repository:
#                     git clone https://azuresrv@bitbucket.org/intelicosystems/srv-conf.git -b azure
#              3. Store credentials to the file /root/.git-credentials:
#                     cd /home/dove/backup/srv-conf
#                     sudo git config credential.helper store; sudo git pull
#              4. Put conf2git.sh into /home/dove/backup/:
#                     scp -P 2222 conf2git.sh dove@10.1.0.100:/home/dove/backup/
#              5. Configure Cron:
#                     sudo crontab -e
#                     00 15	* * *	/bin/bash /home/dove/backup/conf2git.sh
#              6. Test:
#                      sudo /bin/bash /home/dove/backup/conf2git.sh
#                      tail -100 /var/log/conf2git.log
hostname=$(hostname)
dir="/home/dove/backup/srv-conf"
local_backup="${dir}/${hostname}/"
log="/var/log/conf2git.log"

### Configs list
#
declare -a configs=(
  "/etc/systemd"              # System.d
  "/etc/ssh"                  # SSH
  "/etc/ssl"                  # SSL certificates and keys
  "/etc/postfix"              # Postfix
  "/etc/zabbix"               # Zabbix
  "/etc/hosts"                # Hosts
  "/etc/nginx"                # Nginx
  "/etc/php"                  # Php
  "/etc/csync2*"              # csync
  "/etc/mysql"                # MySQL
  "/etc/chproxy_config.yml"   # CHProxy config
  "/var/spool/cron/crontabs"  # Cron
  "/var/spool/incron"         # Incrontab
  "/var/www/vhosts/project/www/bash/" # Bash script for project
  "/home/dove/.ssh"           # User's ssh-config
)


### Create a directory for backups if it is not exist
#
if [ ! -d "${local_backup}" ]; then
  mkdir -p ${local_backup}
fi

### Copy all files with structure of directories
#
for config in "${configs[@]}"; do
  cp -r --parents ${config} ${local_backup} 2>/dev/null
done

### Add a new files to Git
#
echo "==============================================" >> ${log}
date '+%Y-%m-%d %H:%M' >> ${log}
cd ${dir}
/usr/bin/git pull origin azure 2>&1 | tee -a ${log}
/usr/bin/git add * 2>&1 | tee -a ${log}
/usr/bin/git commit -m "Commit by conf2git.sh from ${hostname}" 2>&1 | tee -a ${log}
/usr/bin/git push origin azure 2>&1 | tee -a ${log}