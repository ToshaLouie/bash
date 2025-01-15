#!/bin/bash
# Script for synchronization enabled hosts only
# Dependencies: fping, csync2

documentroot="/var/www/vhosts/project/www"
#documentroot="/var/www/sys.local/www"

# Logging
#
log=${documentroot}/protected/runtime/csync_nosleep.log
touch $log
echo $(date +'%Y-%m-%d %H:%M:%S') | tee -a $log

hostsAvailable=$(cat /etc/hosts | grep -v "#" | grep -v "node1$" | grep -v "ip6" | grep -e "node" -e "TestPHP7" -e "dot818" -e "cab-buyer"  -e "analytics01" -e "node-0$" -e "dot818west" | sed 's/[\t ]\{1,\}/ /' | cut -f2 -d" ")
if [ -z "$hostsAvailable" ]
then
   echo "There are not available hosts" | tee -a $log
   exit
fi
echo "Hosts available: "$hostsAvailable

hostsEnabled=$(/usr/bin/fping $hostsAvailable | grep "alive" | cut -f1 -d" ")
echo "Hosts enabled: "$hostsEnabled | tee -a $log

csync2 -xv -P $(echo $hostsEnabled | sed 's/ /,/g' | tr '[:upper:]' '[:lower:]') 2>&1 | tee -a $log
