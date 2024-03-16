#!/bin/sh
DIR=$(cd $(dirname $0); pwd)
# 从 .env 文件获取 DB_USER=xxx, 解析出 xxx 赋值给 DB_USER
DB_USER=$(grep -Eo "DB_USER=[a-zA-Z0-9]+" .env | cut -d'=' -f2)

docker exec -it oj-postgres pg_dumpall -c -U $DB_USER > ${DIR}/db_backup_`date +%Y_%m_%d"_"%H_%M_%S`.sql
