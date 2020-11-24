#!/bin/sh
DB_USER=#填写数据库用户名
docker exec -it oj-postgres pg_dumpall -c -U $DB_USER > ~/SZUOJ/OnlineJudgeDeploy/backup/db_backup_`date +%Y_%m_%d"_"%H_%M_%S`.sql
