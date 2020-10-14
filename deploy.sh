#!/bin/bash
# Nginx配置
sudo ln -s ~/SZUOJ/OnlineJudgeDeploy/conf/nginx/gzip.conf /etc/nginx/conf.d/gzip.conf
sudo ln -s ~/SZUOJ/OnlineJudgeDeploy/conf/nginx/oj.conf /etc/nginx/conf.d/oj.conf
sudo nginx -t