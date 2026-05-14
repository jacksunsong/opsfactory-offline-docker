# OpsFactory 离线 Docker 安装使用手册

本文面向拿到 `opsfactory-offline-YYYYMMDD-linux-amd64.tar.gz` 离线包的安装人员。

## 1. 前置条件

目标服务器需要已经安装 Docker Engine 和 Docker Compose plugin：

```bash
docker --version
docker compose version
```

要求：

- Linux x86_64 / amd64 服务器
- Docker Engine 已可用
- Docker Compose plugin 已可用
- 目标服务器不需要连接外网
- 需要开放端口：`5173`、`3000`、`8092`、`8093`、`8094`、`8095`、`8096`、`9091`

## 2. 拷贝离线包到服务器

将安装包拷贝到目标服务器，例如：

```bash
scp opsfactory-offline-YYYYMMDD-linux-amd64.tar.gz user@server:/opt/
```

在目标服务器上解压：

```bash
cd /opt
tar -xzf opsfactory-offline-YYYYMMDD-linux-amd64.tar.gz
cd opsfactory-offline-YYYYMMDD-linux-amd64
```

## 3. 校验并导入 Docker 镜像

执行：

```bash
./scripts/load-image.sh
```

该脚本会校验 `SHA256SUMS.txt`，然后通过 `docker load` 导入镜像。

导入后可确认镜像：

```bash
docker images | grep opsfactory
```

应看到类似镜像：

```text
opsfactory   offline-YYYYMMDD-linux-amd64
```

## 4. 启动 OpsFactory

执行：

```bash
./scripts/start.sh
```

脚本会启动容器并等待所有服务健康检查通过。成功后会输出：

```text
OpsFactory is ready: http://127.0.0.1:5173
```

如果从其他机器访问，把 `127.0.0.1` 换成服务器 IP：

```text
http://<服务器IP>:5173
```

## 5. 查看运行状态

```bash
./scripts/status.sh
```

也可以查看容器：

```bash
docker ps | grep opsfactory
```

## 6. 服务端口

| 服务 | 端口 |
| --- | ---: |
| Web App | 5173 |
| Gateway | 3000 |
| Knowledge Service | 8092 |
| Business Intelligence | 8093 |
| Control Center | 8094 |
| Skill Market | 8095 |
| Operation Intelligence | 8096 |
| Prometheus Exporter | 9091 |

Langfuse 和 OnlyOffice 在此离线包中默认禁用。

## 7. 配置模型 Key

镜像内已经保留当前配置结构和 seed 数据，但不包含真实模型 Key。首次启动后页面可以访问、数据可以查看；涉及模型调用的功能需要手工配置 Key。

进入容器：

```bash
docker exec -it opsfactory bash
```

配置各 agent 的 LLM Key，例如：

```bash
vi /app/gateway/agents/<agent-id>/config/secrets.yaml
```

配置知识库 embedding Key：

```bash
vi /app/knowledge-service/config.yaml
```

如果还要调整 provider、base_url、model，也在对应 agent 配置文件中修改。

修改后重启相关服务：

```bash
/app/scripts/ctl.sh restart gateway knowledge
```

退出容器：

```bash
exit
```

## 8. 停止服务

```bash
./scripts/stop.sh
```

## 9. 查看日志

查看最近容器日志：

```bash
docker logs opsfactory --tail 200
```

持续观察日志：

```bash
docker logs -f opsfactory
```

## 10. 重置数据

首次启动时，镜像内置 seed 数据会复制到 Docker named volumes。后续重启不会覆盖已有数据。

如果需要清空当前数据并重新从镜像 seed 初始化：

```bash
./scripts/stop.sh
docker compose -f docker-compose.yml down -v
./scripts/start.sh
```

注意：`down -v` 会删除当前 Docker volumes 中的数据。

## 11. 常见问题

### 端口被占用

`./scripts/start.sh` 会在启动前检查端口。如果提示端口占用，先查占用进程：

```bash
ss -ltnp | grep -E '5173|3000|8092|8093|8094|8095|8096|9091'
```

停止占用端口的服务后重新启动：

```bash
./scripts/start.sh
```

### Docker Compose 不存在

检查：

```bash
docker compose version
```

如果失败，需要先安装 Docker Compose plugin。

### 服务启动失败

查看状态和日志：

```bash
./scripts/status.sh
docker logs opsfactory --tail 200
```

重新启动：

```bash
./scripts/stop.sh
./scripts/start.sh
```
