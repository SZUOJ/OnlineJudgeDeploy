# OnlineJudgeDeploy
SZUOJ部署用

1. 安装docker，docker-compose

2. 调整Nginx配置文件`oj.conf`(User名)、环境变量配置文件`.env.prod`的设置

3. docker-compose启动

## 开发模式启动

使用多个-f参数追加（或覆盖）了原文件的配置

- 检查配置项
```shell script
docker-compose -f docker-compose.yml -f docker-compose.dev.yml --env-file ./conf/.env.dev config
```

- 启动
```shell script
docker-compose -f docker-compose.yml -f docker-compose.dev.yml --env-file ./conf/.env.dev up -d
```

- 如果在本机运行后端

启动判题机、数据库、Redis、消息队列。
```shell script
docker-compose -f docker-compose.yml -f docker-compose.dev.yml --env-file ./conf/.env.dev up -d oj-judger oj-mq oj-postgres oj-redis oj-pgbouncer
```

本机启动Django
```shell script
# 数据库初始化
python manage.py makemigrations
python manage.py migrate --no-input
python manage.py inituser --username=root --password=rootroot --action=create_super_admin
python manage.py loaddata data/fixtures/test.json

# 启动开发服务器
python manage.py runserver
python manage.py rundramatiq
```
## 生产模式启动（正式部署）

使用环境变量文件`./conf/.env.prod`进行配置
```shell script
docker-compose --env-file ./conf/.env.prod config  # 检查配置
docker-compose --env-file ./conf/.env.prod up -d  # 启动
```

## Nginx性能优化

`sudo vim /etc/nginx/nginx.conf`

```
events {
	use epoll;
	worker_connections 65535;
	multi_accept on;
}
```

## Postgresql性能优化

参照https://pgtune.leopard.in.ua/#/