# OnlineJudgeDeploy
SZUOJ部署用

1. 安装docker，docker-compose

2. 调整Nginx配置文件`oj.conf`(User名)、环境变量配置文件`.env.prod`的设置

3. docker-compose启动

## 开发模式启动（开发环境部署）

使用多个-f参数追加（或覆盖）了原文件的配置

- 检查配置项

```sh
docker-compose -f docker-compose.yml -f docker-compose.dev.yml --env-file ./conf/.env.dev config
```

- 启动

```sh
docker-compose -f docker-compose.yml -f docker-compose.dev.yml --env-file ./conf/.env.dev up -d
```

- 如果在本机运行后端

启动判题机、数据库、Redis、消息队列。

```sh
docker-compose -f docker-compose.yml -f docker-compose.dev.yml --env-file ./conf/.env.dev up -d oj-judger oj-mq oj-postgres oj-redis oj-pgbouncer
```

本机启动Django
```sh
# 数据库初始化
python manage.py makemigrations
python manage.py migrate --no-input
python manage.py inituser --username=root --password=rootroot --action=create_super_admin
python manage.py loaddata data/fixtures/test.json

# 启动开发服务器
python manage.py runserver
python manage.py rundramatiq
```

## 预发布环境启动

```sh
docker-compose config  # 检查配置
docker-compose -f docker-compose.pre.yml up -d  # 启动
```

## 生产模式启动（正式部署）

使用环境变量文件`.env`进行配置

```sh
docker-compose config  # 检查配置
docker-compose up -d  # 启动
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

参照`https://pgtune.leopard.in.ua/#/`进行设置


## docker容器web可视化管理

```sh
docker run -d -p 9000:9000 --restart=always \
    -v /var/run/docker.sock:/var/run/docker.sock \
    --name portainer portainer/portainer
```

启动后即可在9000端口访问可视化管理页面

对于同一服务器的情况，选用`Local`模式即可
