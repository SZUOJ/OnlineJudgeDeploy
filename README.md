# OnlineJudgeDeploy
SZUOJ部署用

1. 安装docker

2. docker-compose启动

## 开发模式启动

使用多个-f参数追加（或覆盖）了原文件的配置

- 检查配置项
```shell script
docker-compose -f docker-compose.yml -f docker-compose-dev.yml config
```

- 启动
```shell script
docker-compose -f docker-compose.yml -f docker-compose-dev.yml up -d
```

## 生产模式启动（正式部署）

```shell script
docker-compose up -d
```