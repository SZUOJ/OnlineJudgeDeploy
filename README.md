# SZUOJ 部署

判题架构分为“主站”和任意数量的“判题节点”。主站运行 Django/PostgreSQL/Redis/Celery/Frontend；每台判题机只运行一个一体化 JudgeAgent。Agent 主动连接主站，并在节点本机完成任务领取、测试数据缓存、编译、SPJ 和 libjudger 安全沙箱执行。主站不需要访问判题机端口，判题节点也不开放 JudgeServer HTTP 服务。

## 一、部署或升级主站

1. 配置 `.env` 中的数据库、Redis、管理员和 JudgeAgent 调度参数。
2. 确保 Nginx 对 `/ws/` 保留 Upgrade 头；仓库配置的长连接超时为 3600 秒。
3. 首次部署或每次升级时，先拉取当前 `JudgeAgent` 分支镜像，再启动：

```sh
docker compose --env-file ./.env config
docker compose --env-file ./.env pull
docker compose --env-file ./.env up -d --remove-orphans
```

Backend 启动时会自动执行数据库迁移。JudgeAgent 调度始终启用，不再存在 `JUDGE_AGENT_ENABLED` 开关；主站也不使用 JudgeServer URL、Token 或 Secret。

主站的 Backend/Frontend 固定使用 `JudgeAgent` 镜像标签，避免误拉取 master/latest 的旧架构。升级时先使用 `backup/db_backup.sh` 备份 PostgreSQL，并按需备份 Compose 命名卷 `test_case_data` 和 `media_data`，再执行上述 `pull` 和 `up` 命令。`pull`/`up` 和 `--remove-orphans` 都不会删除命名卷；升级时不要执行 `docker compose down -v`。迁移会保留已有节点数据，并将节点版本字段从独立 JudgeServer 语义更新为内嵌 JudgeEngine。

## 二、新增判题节点

1. 使用管理员账号进入“系统管理 → 判题机管理”。
2. 创建节点，立即保存 Node ID 和只展示一次的 Token。
3. 在判题机复制配置：

```sh
cp conf/.env.judge-node.example conf/.env.judge-node
cp conf/judge-agent.token.example conf/judge-agent.token
chmod 600 conf/judge-agent.token
```

4. 将 Node ID 写入 `conf/.env.judge-node`，Node Token 写入 `conf/judge-agent.token`，并填写主站的生产 WSS/HTTPS 地址。
5. 启动唯一的节点服务：

```sh
docker compose \
  -f docker-compose.judge-node.yml \
  --env-file ./conf/.env.judge-node \
  config

docker compose \
  -f docker-compose.judge-node.yml \
  --env-file ./conf/.env.judge-node \
  pull

docker compose \
  -f docker-compose.judge-node.yml \
  --env-file ./conf/.env.judge-node \
  up -d --remove-orphans
```

判题节点固定使用 JudgeAgent `main` 镜像标签；节点升级时重复执行上述 `pull` 和 `up` 即可。

增加更多判题机时，在每台机器重复上述步骤并创建独立节点/Token。`JUDGE_NODE_CONCURRENCY` 控制该节点同时执行的提交数；`JUDGE_TEST_CASE_WORKERS` 固定为 1，避免每个提交再次放大并发。`JUDGE_AGENT_PIDS_LIMIT` 默认为 512，用于限制容器内全部进程和线程；只有在提高节点并发且确认 Java/JVM 任务触发 PID 上限时才应调高。`JUDGE_AGENT_TMPFS_SIZE` 默认将可执行的 `/tmp` tmpfs 限制为 512 MiB，防止 Java/Node 或恶意提交无限消耗宿主内存；只有在可复现的工具链临时空间不足时才应调高。

### 主站与判题节点部署在同一台生产服务器

先按第一节启动主站并在后台创建节点。然后把判题节点地址改为 Compose 内网地址：

```dotenv
JUDGE_AGENT_WS_URL=ws://oj-backend:8000/ws/judge/
JUDGE_AGENT_FILE_URL=http://oj-backend:8000/api/judge-agent/files/
JUDGE_AGENT_TLS_VERIFY=false
```

之后始终同时合并主站和判题节点 Compose 文件，避免在同一 Compose project 中把另一组容器当成 orphan：

```sh
docker compose \
  --env-file ./.env \
  --env-file ./conf/.env.judge-node \
  -f docker-compose.yml \
  -f docker-compose.judge-node.yml \
  config

docker compose \
  --env-file ./.env \
  --env-file ./conf/.env.judge-node \
  -f docker-compose.yml \
  -f docker-compose.judge-node.yml \
  pull

docker compose \
  --env-file ./.env \
  --env-file ./conf/.env.judge-node \
  -f docker-compose.yml \
  -f docker-compose.judge-node.yml \
  up -d --remove-orphans
```

## 三、开发环境（主站与判题在同一台服务器）

先启动主站基础服务：

```sh
docker compose \
  -f docker-compose.yml \
  -f docker-compose.dev.yml \
  --env-file ./conf/.env.dev \
  up -d oj-postgres oj-pgbouncer oj-redis oj-backend
```

在后台创建本地节点，把 ID 写入 `conf/.env.dev`，Token 写入 `conf/judge-agent.token`，再启动同机 JudgeAgent：

```sh
docker compose \
  -f docker-compose.yml \
  -f docker-compose.dev.yml \
  --env-file ./conf/.env.dev \
  up -d judge-agent
```

开发节点仍通过后端文件 API 下载测试数据，因此同机部署和远程多节点使用相同的真实判题链路。

## 四、暂停、Token 轮换与删除

- 暂停：节点停止领取新任务，已领取任务继续执行；再次启用后恢复抢占。
- 轮换 Token：后台生成一次性新 Token，并主动断开旧连接。替换 Secret 后重启 JudgeAgent。
- 删除：只能删除离线且没有运行任务的节点。

```sh
docker compose -f docker-compose.judge-node.yml restart judge-agent
```

## 五、缓存维护

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

# 判题节点：查看连接、缓存、编译和沙箱日志
docker compose -f docker-compose.judge-node.yml logs -f judge-agent
```

常见检查项：

- 节点离线：核对 WSS 地址、反向代理 Upgrade 头、Node ID/Token 和系统时间。
- 一直等待任务：核对节点是否启用、语言是否匹配、最低优先级和空闲并发。
- 数据版本冲突：Agent 会发送 reset，主站刷新 manifest 后重新入队；持续发生时检查后端测试数据目录是否被外部程序直接修改。
- 编译或沙箱失败：确认节点镜像完整、`/judger`、`/log`、`/test_case` 可写，并保留 Compose 中的降权能力配置。
- 任务重复执行：断线/租约过期时允许重新执行，但主站会用 lease token + judge_version 保证结果只落库一次。
