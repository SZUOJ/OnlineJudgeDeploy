# SZUOJ 部署

判题已拆分为“主站”和任意数量的“判题节点”。主站只运行 Django/PostgreSQL/Redis/Celery/Frontend；每台判题机单独运行 JudgeAgent + JudgeServer。JudgeAgent 主动连接主站，主站不需要访问判题机端口。

## 一、部署或升级主站

1. 配置 `.env` 中的数据库、Redis、管理员和 JudgeAgent 调度参数。
2. 确保 Nginx 对 `/ws/` 保留 Upgrade 头；仓库配置的长连接超时为 3600 秒。
3. 启动：

```sh
docker compose --env-file ./.env config
docker compose --env-file ./.env up -d
```

Backend 启动时会自动执行数据库迁移。主站 Compose 不再包含固定 `oj-judger`，也不再使用 `JUDGER_SERVER_URL` 或旧的 `JUDGE_SERVER_TOKEN`。

升级到多判题机版本时，先备份 PostgreSQL 与 `data/test_case`，再更新镜像并启动主站。迁移会新增 JudgeNode、JudgeTask 和 CodeSubmission.judge_version；已有题目的 manifest 会在首次使用时自动补齐。

## 二、新增判题节点

1. 使用管理员账号进入“系统管理 → 判题机管理”。
2. 创建节点，立即保存 Node ID 和只展示一次的 Token。
3. 在判题机复制配置：

```sh
cp conf/.env.judge-node.example conf/.env.judge-node
cp conf/judge-agent.token.example conf/judge-agent.token
cp conf/judge-server.token.example conf/judge-server.token
chmod 600 conf/judge-agent.token conf/judge-server.token
```

4. 将后台获得的 Node ID 写入 `conf/.env.judge-node`，Node Token 写入 `conf/judge-agent.token`；为本机 JudgeServer 生成另一个长随机 Token 写入 `conf/judge-server.token`。
5. 填写主站的生产 WSS/HTTPS 地址，然后启动：

```sh
docker compose \
  -f docker-compose.judge-node.yml \
  --env-file ./conf/.env.judge-node \
  config

docker compose \
  -f docker-compose.judge-node.yml \
  --env-file ./conf/.env.judge-node \
  up -d
```

JudgeServer 没有宿主机端口，只能由同一 Compose 网络内的 JudgeAgent 调用。Agent 对共享 `judge_cache` 卷可写，JudgeServer 以只读方式挂载 `/test_case`。

增加更多判题机时，在每台机器重复上述步骤并创建独立节点/Token。节点的 `JUDGE_NODE_CONCURRENCY` 同时设置 Agent 并发和 JudgeServer Worker 数量；第一版 `JUDGE_TEST_CASE_WORKERS` 固定为 1。

## 三、开发环境（主站与判题在同一台服务器）

先启动主站基础服务：

```sh
docker compose \
  -f docker-compose.yml \
  -f docker-compose.dev.yml \
  --env-file ./conf/.env.dev \
  up -d oj-postgres oj-pgbouncer oj-redis oj-backend
```

在后台创建本地节点，把 ID 写入 `conf/.env.dev`，Token 写入 `conf/judge-agent.token`，再启动本地判题节点：

```sh
docker compose \
  -f docker-compose.yml \
  -f docker-compose.dev.yml \
  --env-file ./conf/.env.dev \
  up -d judge-server judge-agent
```

开发覆盖文件只把 JudgeServer 调试端口绑定到 `127.0.0.1:12358`。Agent 仍通过后端文件 API 下载测试数据，因此单机开发和远程多节点使用同一条真实链路。

## 四、暂停、Token 轮换与删除

- 暂停：节点停止领取新任务，已领取任务继续执行；再次启用后恢复抢占。
- 轮换 Token：后台生成一次性新 Token，并主动断开旧连接。替换 Secret 后重启 JudgeAgent。
- 删除：只能删除离线且没有运行任务的节点。

```sh
docker compose -f docker-compose.judge-node.yml restart judge-agent
```

## 五、缓存维护

在 JudgeAgent 容器中运行：

```sh
docker compose -f docker-compose.judge-node.yml exec judge-agent \
  judge-agent --config /etc/judge-agent/config.yaml cache list

docker compose -f docker-compose.judge-node.yml exec judge-agent \
  judge-agent --config /etc/judge-agent/config.yaml cache prune --days 30

docker compose -f docker-compose.judge-node.yml exec judge-agent \
  judge-agent --config /etc/judge-agent/config.yaml cache clear
```

正在同步或判题使用的题目会被跳过，不会被清理。

## 六、故障检查

```sh
# 主站：查看 WebSocket、任务租约回收和数据库错误
docker compose logs -f oj-backend oj-backend-celery-beat

# 判题节点：查看连接、缓存下载和本机判题日志
docker compose -f docker-compose.judge-node.yml logs -f judge-agent judge-server
```

常见检查项：

- 节点离线：核对 WSS 地址、反向代理 Upgrade 头、Node ID/Token 和系统时间。
- 一直等待任务：核对节点是否启用、语言是否匹配、最低优先级和空闲并发。
- 数据版本冲突：Agent 会发送 reset，主站刷新 manifest 后重新入队；持续发生时检查后端测试数据目录是否被外部程序直接修改。
- JudgeServer 不健康：确认 Agent concurrency 与 JudgeServer workers 一致，Secret 文件内容一致，`/test_case` 为共享卷。
- 任务重复执行：断线/租约过期时允许重复运行，但主站会用 lease token + judge_version 保证结果只落库一次。
