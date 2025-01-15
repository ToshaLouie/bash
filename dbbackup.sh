#!/bin/bash
function print_help() {
echo "
# Script for full/incremental backup db mysql by innobackupex
# Script has dependend on:  awscli, gnupg2, innobackupex
#
# This script does the following:
#     1. Creates FULL backup using innobackupex
#     2. Applies a binlog to clear uncommitted transactions
#     3. Archives, encodes database backup using gpg
#     4, Uploads encoded backup to S3-storage
#        (In fact copy file /home/dove/backup/<date>_full.tar.gz.asc
#                        to s3://main.total.storage/<hostname>/)
#     5. Deletes remote backups when their count exceeds variable value
#
# Notes:
#       1. Credentials for access to the AWS should be configured under root account:
#          aws configure
#          aws configure set default.region eu-central-1
#       2. Configure gpg keys:
#          sudo su
#          gpg --gen-key
#
        "
}

function show_usage() {
        echo "Usage: $0 --full | --incremental | --help"
        exit -1
}

# set all these parameters in a backup file
# default path is /root/awsbackup.cfg
db_user=''
db_passwd=''
backup_dir=''
remote_archives_count=3
crypt_archive=true
# you can add extra files/directories for tar'ing here
extra_backup_targets=''
# change these only if it is needed
current_backup_path=${backup_dir}"/"$(date +%Y-%m-%d)"_full"
aws_remote_path=s3://main.total.storage/`hostname`/
gpg_id="toshaor97@gmail.com"

[ -r /root/awsbackup.cfg ] && . /root/awsbackup.cfg

current_backup_path=${backup_dir}"/"$(date +%Y-%m-%d)"_full"
aws_remote_path=s3://main.total.storage/`hostname`/

function do_full_db_backup() {
        while [[ -n `ps aux | grep "innobackupex" | grep -v "grep"` ]]; do
                echo "Backup still is in progress. Waiting for a 10 minutes."
                sleep 600
        done
        ### Deleting all old backups
        rm -rf `find $backup_dir/ -maxdepth 1 -nowarn -type d -name '20??-??-??_*'`
        ### Creating new FULL backup for current date
        mkdir -p ${current_backup_path}
        innobackupex --defaults-file=/etc/mysql/my.cnf --user=$db_user --password=$db_passwd --slave-info --no-timestamp --rsync $current_backup_path 2>&1 | tee $current_backup_path/xtrabackup.log
        innobackupex --apply-log --redo-only ${current_backup_path} 2>&1 | tee ${current_backup_path}/xtrabackup_apply.log
}

function do_incremental_db_backup() {
        while [[ -n `ps aux | grep "innobackupex" | grep -v "grep"` ]]; do
                echo "Backup still is in progress. Waiting for a 10 minutes."
                sleep 600
        done
        ### Looking for backup_directory with last FULL backup (with date not older then 7 days)
        path_base=`find ${backup_dir} -maxdepth 1 -type d -name "20??-??-??_full" -mtime -7 | sort | tail -n 1`
        ### Looking for backup_directory with last INCREMENT backup (with date not older then date of full backup)
        path_pre=`find ${backup_dir} -maxdepth 1 -type d -name "20??-??-??_incr" -mtime -7 | sort | tail -n 1`

        if [[ -z "$path_pre" ]]; then
                path_pre=${path_base}
        fi

        mkdir -p ${backup_dir}"/"$(date +%Y-%m-%d_incr)
		current_backup_path=${backup_dir}"/"$(date +%Y-%m-%d_incr)""

        innobackupex --defaults-file=/etc/mysql/my.cnf --db_user=${db_user} --password=${db_passwd} --slave-info --no-timestamp --rsync ${backup_dir}"/"$(date +%Y-%m-%d_incr) --incremental --incremental-basedir=${path_pre} 2>&1 | tee ${backup_dir}"/"$(date +%Y-%m-%d_incr)/xtrabackup.log
#        innobackupex --apply-log --redo-only ${path_base} --incremental-dir=${backup_dir}"/"$(date +%Y-%m-%d_incr) 2>&1 | tee ${backup_dir}"/"$(date +%Y-%m-%d_incr)/xtrabackup_apply.log
}

function tar_and_crypt() {
        ### Testing posobility for backup
        echo "Testing backup..."
        if [[ -z `tail $current_backup_path/xtrabackup.log | grep "completed OK!"` || -z `tail $current_backup_path/xtrabackup_apply.log | grep "completed OK!"` ]]; then
                exit -1
        fi

        echo "Packing backup to tar.gz ..."
        /bin/tar -cz $current_backup_path $extra_backup_targets | gpg --encrypt --sign --armor -r ${gpg_id}  > $current_backup_path.tar.gz.asc

        if [[ ! $? -eq 0 ]]; then
		       	echo "ERROR: Packing the backup to .tar.gz is not complete. Copying to the S3-storage has not done!"
                exit -1
        fi
		echo 'Packing the backup to .tar.gz is Complete!'
}

function upload() {
        echo "Copying backup to S3-storage..."
        aws s3 cp $current_backup_path.tar.gz.asc $aws_remote_path
        if [[ ! $? -eq 0 ]]; then
                exit -1
        fi
}

function cleanup_remote_storage() {
        ### Deleting old archive from the S3-storage
        echo "Deleting old backup from the S3-storage..."
        s3_archives_count=`aws s3 ls $aws_remote_path | wc -l`
        if [[ $s3_archives_count -gt $remote_archives_count ]]; then
                for archive in `aws s3 ls $aws_remote_path | awk '{print $4}' | sort | head -n $(( $s3_archives_count - $remote_archives_count ))`; do
                        aws s3 rm $aws_remote_path$archive
                done
        fi
}

# main code

if [[ -z $db_user || -z $db_passwd || -z $backup_dir ]]; then
        echo -e "\tMain config parameters are not set in /root/awsbackup.cfg.
        Consider setting db_user, db_passwd and backup_dir to appropriate values"
        exit -1
fi

if [[ $# -ne 1 ]]; then
        show_usage
elif [[ $1 -eq 'help' ]]; then
        print_help
elif [[ $1 -eq 'incremental' ]]; then
        do_incremental_db_backup
elif [[ $1 -eq 'full' ]]; then
        do_full_db_backup && tar_and_crypt && upload && cleanup_remote_storage
      rm $current_backup_path.tar.gz.asc
elif [[ $1 -eq 'tar' ]]; then
        tar_and_crypt && upload && cleanup_remote_storage
      rm $current_backup_path.tar.gz.asc
fi
