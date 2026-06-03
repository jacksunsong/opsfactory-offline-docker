# OpsFactory 离线 Docker 安装包

精简版：Gateway + Web App + Knowledge Service + Operation Intelligence，LLM API key 已内置。部署到目标机器只需 Docker，无需 docker compose。

## 包内容

```
opsfactory-offline-20260602-linux-amd64/
├── images/
│   └── opsfactory-linux-amd64.tar    # Docker 镜像 (~773MB)
├── data/                              # 主机挂载目录（首次启动自动 seed）
│   ├── agents/
│   ├── users/
│   ├── gateway-data/
│   ├── knowledge-data/                # Knowledge Service 数据
│   ├── operation-intelligence-data/   # Operation Intelligence 数据
│   └── runtime-config/
├── config.env                         # 配置：端口、容器名、数据目录
├── start.sh                           # 一键启动：load + run
├── stop.sh
├── status.sh
├── reset-data.sh                      # 清空 data/ 重新初始化
└── README.md
```

## 三步部署

### 步骤 1：解压

```bash
tar -xzf opsfactory-offline-20260602-linux-amd64.tar.gz
cd opsfactory-offline-20260602-linux-amd64
```

### 步骤 2：改配置（可选）

编辑 `config.env`：

```bash
# 容器名（同一台机器只能跑一个 opsfactory）
CONTAINER_NAME=opsfactory

# 数据目录（相对于包根目录；首次启动会自动创建并从镜像 seed 初始化）
DATA_DIR=./data
```

端口已固定（5173 webapp、3000 gateway、8092 knowledge、8096 operation-intelligence），**部署时不可更改**。如需改端口必须重建镜像。

### 步骤 3：启动

```bash
./start.sh
```

脚本会按顺序执行：
1. 检查 `docker` 命令
2. 检查 5173/3000/8092/8096 端口是否被占用
3. `docker load -i images/opsfactory-linux-amd64.tar`（如果还没导入）
4. `docker run -d --network host` 启动容器，挂载 `data/` 到主机
5. 等 Gateway 健康检查通过（最多 240 秒）

成功输出：
```
=== OpsFactory is ready ===
  Web app:  http://10.0.0.5:5173
            http://127.0.0.1:5173
  Gateway:  http://127.0.0.1:3000  (returns 401 without auth header, normal)
  Knowledge: http://127.0.0.1:8092/actuator/health
  Operation Intelligence: http://127.0.0.1:8096/actuator/health
```

## 访问

在浏览器打开：

- **Web App**：`http://<服务器IP>:5173`（固定端口，不可更改）
- **Gateway API**（一般不直接访问）：`http://<服务器IP>:3000`

默认 secret key：**`test`**（已内置在 `web-app/config.json` 里）

## 常用操作

```bash
./status.sh       # 查容器状态、HTTP 检查、资源占用
./stop.sh         # 停止并移除容器（data/ 数据保留）
./start.sh        # 再次启动（不会重复 load 镜像）

docker logs -f opsfactory    # 实时看日志
docker exec -it opsfactory bash   # 进容器排查

./reset-data.sh   # 清空 data/ 重新初始化（会丢所有聊天记录！）
```

## 数据持久化

所有运行时数据挂在 `./data/` 目录（相对包根目录），结构：

```
data/
├── agents/           # 10 个 agent 的 config（含 secrets.yaml）、skills、prompts
├── users/            # 用户数据、goosed session、聊天记录
├── gateway-data/     # gateway 共享数据
└── runtime-config/   # runtime 配置（gateway config.yaml 等）
```

- `./stop.sh` 只删容器，不删数据。再 `./start.sh` 数据还在。
- 想备份整个服务：直接打包 `data/` 目录即可。
- 想换台机器迁移：连镜像 tar 一起拷过去，`./start.sh` 即可。

## 已内置的 LLM 配置

镜像已带以下 provider 的 API key（在 `data/agents/<agent>/config/secrets.yaml`）：

| Provider | 后端 | 用于 |
| --- | --- | --- |
| `custom_qwen3.5-27b` | OpenRouter `qwen/qwen3.5-27b` | universal-agent, qa-agent, qa-cli-agent, qos-agent, fo-copilot, report-agent, fault-diagnosis-agent |
| `custom_qwen3.5-35b-a3b` | OpenRouter | supervisor-agent |
| `custom_glm` | 智谱 GLM | kb-agent |
| `custom_ollama_local` | 本地 Ollama (127.0.0.1:11434) | local-tiny-agent（需自带 ollama） |

**目标机器必须能访问 `openrouter.ai` 和 `bigmodel.cn`**，否则 LLM 调用失败。

## 故障排查

### 启动失败：端口被占用
```
Port 5173 is already in use on the host.
```
端口已固定，只能停掉占用进程：
```bash
ss -ltnp | grep -E '5173|3000|8092|8096'
```

### 启动失败：Gateway 240 秒还没就绪
```
Gateway did not become ready within 240s.
```
看日志：
```bash
docker logs opsfactory --tail 200
```
常见原因：
- 内存不够（goosed 启动需要 ~1GB，建议 ≥4GB 内存）
- 首次启动在 ARM 机器上通过 QEMU 模拟，可能更慢（本包是 amd64）

### Agent 对话报 500
进容器看对应 agent 的 goosed 日志：
```bash
docker exec opsfactory bash -lc \
  'ls /app/gateway/users/admin/agents/qos-agent/state/logs/server/'
docker exec opsfactory bash -lc \
  'tail -50 /app/gateway/users/admin/agents/qos-agent/state/logs/server/<日期>/<文件>'
```
常见错误：
- `Required API key ... is not set` → secrets.yaml 没分发到那个 agent
- `401 Unauthorized` 或 `403 Forbidden` → API key 失效
- `Connection refused` / timeout → 出不去网

### 改了 secrets 或 agent 配置没生效
```bash
docker restart opsfactory
```

### 容器不停重启
```bash
docker logs opsfactory --tail 100
```
如果是 `sleep infinity` 之类的诡异问题，确认镜像是从这个包导入的（不是旧版本）。

## 已知限制

- **amd64 only**：在 ARM 机器（如 Apple Silicon）上跑会通过 QEMU 模拟，启动慢
- **openEuler 24.03 base**：`tail -F` 在这个 base 上约 2 分钟会自己退出（GNU coreutils 行为），entrypoint 已用 `while true; do sleep 3600; done` 规避
- Gateway 跑 HTTP（不是 HTTPS），因为内置 webapp 配置就是 HTTP。要 HTTPS 需要自己加反代

## 验证清单

部署完成后逐项验证：

1. **页面能打开**：浏览器访问 `http://<IP>:5173`，看到登录页
2. **能看到 agent 列表**：登录后看到 10 个 agent
3. **能跟 agent 对话**：选 `Universal Agent`，发"介绍你自己"，能收到 LLM 回复
4. **状态正常**：`./status.sh` 显示 container Up，两个 HTTP 检查返回 200/401

第 3 步失败说明 LLM 调用有问题，看上面"Agent 对话报 500"那一节。

## 前置条件（目标机器需要什么）

| 项 | 要求 |
| --- | --- |
| OS | Linux x86_64 |
| Docker Engine | ≥ 20.10，能跑 `docker` 命令 |
| Docker Compose | **不需要**（这个包不用 compose） |
| CPU | ≥ 4 核 |
| 内存 | ≥ 4 GiB（推荐 8 GiB） |
| 磁盘 | ≥ 10 GB（镜像 773MB + 运行数据） |
| 端口 | 5173、3000、8092、8096 能从外部访问 |
| 网络 | 能访问 `openrouter.ai`、`bigmodel.cn`（LLM 调用） |

确认命令：
```bash
docker --version
docker info --format 'CPUs={{.NCPU}} Mem={{.MemTotal}} Arch={{.Architecture}}'
```
