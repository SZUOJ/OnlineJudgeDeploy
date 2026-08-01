# SZUOJ 部署

判题架构由一个主站和任意数量的 JudgeAgent 节点组成。默认的 `docker-compose.yml` 已包含 Backend、Frontend 和一个同机 JudgeAgent，适合直接完成单机部署；需要扩容时，再在其他服务器使用 `docker-compose.judge-node.yml` 添加独立判题节点。

JudgeAgent 主动连接 Backend，并在节点本机完成任务领取、测试数据缓存、编译、SPJ 和 libjudger 沙箱执行。主站不需要访问判题机端口，判题节点也不开放 JudgeServer HTTP 服务。

## 一、单机生产部署与升级

### 镜像发布与兼容性前置条件

首次采用本版本或以后更新这套 Deploy 配置时，必须先确认以下三个仓库的对应发布 workflow 已成功完成，并且镜像仓库中的标签已更新：

- `JudgeAgent` 的 `main` 分支已发布 `registry.cn-shenzhen.aliyuncs.com/szuoj/judge_agent:main`。
- `OnlineJudge` 的 `JudgeAgent` 分支已发布 `registry.cn-shenzhen.aliyuncs.com/szuoj/backend:JudgeAgent`。
- `OnlineJudgeFE` 的 `JudgeAgent` 分支已发布 `registry.cn-shenzhen.aliyuncs.com/szuoj/frontend:JudgeAgent`。

三个镜像全部发布成功后，才能更新 `OnlineJudgeDeploy` 的 `JudgeAgent` 分支并执行下面的 `pull`、`up`。如果任一 workflow 失败或对应标签仍是旧镜像，应继续运行旧部署，不要先应用新 Compose。

新 Compose 的同机 JudgeAgent 使用 `JUDGE_AGENT_NODE_ID_FILE` 和配置项 `server.node_id_file` 从共享卷读取 Backend 自动生成的 Node ID，同时等待 Node ID 与 Token 文件就绪。旧 JudgeAgent 镜像不支持这套文件凭据协议，不能与新 Compose 混用；新 Backend、JudgeAgent 和 Deploy Compose 应作为同一兼容版本一起发布和升级。回滚时也应成套回滚，不能只替换其中一个镜像或配置文件。

1. 填写 `.env` 中的数据库、管理员密码及按需调整的 JudgeAgent 参数。
2. 确保 Nginx 对 `/ws/` 保留 Upgrade 头；仓库配置的长连接超时为 3600 秒。
3. 检查配置、拉取镜像并启动完整服务：

```sh
docker compose --env-file ./.env config
docker compose --env-file ./.env pull
docker compose --env-file ./.env up -d --remove-orphans
```

Backend 启动时会先执行数据库迁移，然后创建或校验受托管的本地判题节点，并将 Node ID 与 Token 原子写入 `judge_agent_credentials` 命名卷。Backend 健康检查通过后，同机 JudgeAgent 才会启动并读取这组凭据，因此单机部署不需要在管理后台手工创建节点，也不需要填写 Node ID 或 Token。

Backend 和 Frontend 固定使用 `JudgeAgent` 镜像标签，同机 JudgeAgent 固定使用 `main` 镜像标签。JudgeAgent 调度始终启用，不再存在 `JUDGE_AGENT_ENABLED` 开关；主站也不使用旧 JudgeServer 的 URL、Token 或 Secret。

升级前使用 `backup/db_backup.sh` 备份 PostgreSQL，并备份 Compose 命名卷 `test_case_data`、`media_data` 和 `judge_agent_credentials`；如需保留本地题目缓存，也备份 `judge_cache`。之后重复执行上面的 `pull` 和 `up` 命令即可。`pull`、`up` 和 `--remove-orphans` 不会删除命名卷，升级时不要执行 `docker compose down -v`。如果数据库中已有受托管节点而 `judge_agent_credentials` 丢失、损坏或与数据库身份不一致，Backend 会拒绝生成第二套身份并停止启动；应优先恢复该卷的备份，不能通过反复重启绕过。

### 从旧版同机 JudgeAgent 部署升级

旧版需要合并 `docker-compose.yml` 与 `docker-compose.judge-node.yml` 才能在主站服务器启动判题节点；新版不再需要这样做。升级时保持原 Compose project 名称不变，停止传入 `docker-compose.judge-node.yml` 和 `conf/.env.judge-node`，直接执行本节的默认启动命令。

新版仍使用 `judge-agent` 服务名和 `judge_cache` 命名卷，因此同一 Compose project 下的容器会原地更新且缓存会保留。Backend 会另外管理默认本地节点；确认新节点在线并能够判题后，可停用或删除旧的手工本地节点，避免后台长期显示一个不再连接的节点。

## 二、增加远程判题节点

默认单机节点可以和任意数量的远程节点同时工作。每台远程判题机使用独立 Node ID 与 Token，并只运行 JudgeAgent。

1. 使用管理员账号进入“系统管理 → 判题机管理”。
2. 创建节点，立即保存 Node ID 和只展示一次的 Token。
3. 在判题机准备配置：

```sh
cp conf/.env.judge-node.example conf/.env.judge-node
cp conf/judge-agent.token.example conf/judge-agent.token
chmod 600 conf/judge-agent.token
```

4. 将 Node ID 写入 `conf/.env.judge-node`，Token 写入 `conf/judge-agent.token`，并填写主站的生产 WSS/HTTPS 地址。
5. 检查配置、拉取镜像并启动：

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

远程节点固定使用 JudgeAgent `main` 镜像标签；升级时重复执行上述 `pull` 和 `up` 即可。增加更多判题机时，在每台机器重复此流程并为每个节点创建独立凭据。

`JUDGE_NODE_CONCURRENCY` 控制该节点同时执行的提交数；`JUDGE_TEST_CASE_WORKERS` 固定为 1，避免每个提交再次放大并发。`JUDGE_AGENT_PIDS_LIMIT` 默认为 512，用于限制容器内全部进程和线程；只有在提高并发且确认 Java/JVM 任务触发 PID 上限时才应调高。`JUDGE_AGENT_TMPFS_SIZE` 默认将可执行的 `/tmp` tmpfs 限制为 512 MiB；只有在可复现的工具链临时空间不足时才应调高。

## 三、开发环境

开发环境同样会自动创建本地判题节点，不需要先启动 Backend 再手工填写凭据。准备好相邻目录中的 `OnlineJudge`、`OnlineJudgeFE` 和 `JudgeAgent` 后，一次启动完整环境：

```sh
docker compose \
  -f docker-compose.yml \
  -f docker-compose.dev.yml \
  --env-file ./conf/.env.dev \
  up -d --build --remove-orphans
```

开发节点仍通过 Backend 文件 API 下载测试数据，因此同机部署和远程多节点使用相同的真实判题链路。

## 四、暂停、Token 轮换与删除

- 暂停：节点停止领取新任务，已领取任务继续执行；再次启用后恢复抢占。
- 默认本地节点：凭据由 Backend 托管。该节点可以暂停或恢复，Backend 重启不会改变其启用状态。后台轮换 Token 后，Backend 会原子更新共享卷并断开旧连接，Agent 重连时会重新读取 Token，无需编辑文件或重启容器。受托管节点不能按普通远程节点直接删除。
- 远程节点：后台轮换 Token 后，将新 Token 写入该节点的 `conf/judge-agent.token`，保持文件权限为 `0600`，然后重启 Agent。旧连接会被主动断开。
- 删除远程节点：只能删除离线且没有运行任务的节点。

```sh
docker compose \
  -f docker-compose.judge-node.yml \
  --env-file ./conf/.env.judge-node \
  restart judge-agent
```

## 五、缓存维护

默认同机节点：

```sh
docker compose --env-file ./.env exec judge-agent \
  judge-agent --config /etc/judge-agent/config.yaml cache list

docker compose --env-file ./.env exec judge-agent \
  judge-agent --config /etc/judge-agent/config.yaml cache prune --days 30

docker compose --env-file ./.env exec judge-agent \
  judge-agent --config /etc/judge-agent/config.yaml cache clear
```

远程节点：

```sh
docker compose \
  -f docker-compose.judge-node.yml \
  --env-file ./conf/.env.judge-node \
  exec judge-agent judge-agent --config /etc/judge-agent/config.yaml cache list
```

将最后的 `cache list` 替换为 `cache prune --days 30` 或 `cache clear` 即可执行对应操作。正在同步或判题使用的题目会被跳过，不会被清理。

## 六、故障检查

默认单机部署：

```sh
docker compose --env-file ./.env ps
docker compose --env-file ./.env logs -f \
  oj-backend oj-backend-celery-beat judge-agent
```

远程判题节点：

```sh
docker compose \
  -f docker-compose.judge-node.yml \
  --env-file ./conf/.env.judge-node \
  logs -f judge-agent
```

常见检查项：

- 默认节点未启动：先检查 Backend 是否健康，再查看 Backend 是否报告凭据文件为空、格式非法、不是普通文件或卷权限错误。Backend 会使用持久凭据校正数据库中的 Token 哈希，并在数据库节点记录缺失时恢复同一节点。
- 远程节点离线：核对 WSS 地址、反向代理 Upgrade 头、Node ID/Token 和系统时间。
- 一直等待任务：核对节点是否启用、语言是否匹配、最低优先级和空闲并发。
- 数据版本冲突：Agent 会发送 reset，主站刷新 manifest 后重新入队；持续发生时检查 Backend 测试数据目录是否被外部程序直接修改。
- 编译或沙箱失败：确认节点镜像完整、`/judger`、`/log`、`/test_case` 可写，并保留 Compose 中的降权能力配置。
- 任务重复执行：断线或租约过期时允许重新执行，但主站会使用 lease token 与 judge version 保证结果只落库一次。
