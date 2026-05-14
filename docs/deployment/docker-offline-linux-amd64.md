# OpsFactory Linux amd64 离线 Docker 交付包

本文档描述如何构建和使用 OpsFactory `linux/amd64` 离线 Docker 交付包。交付包面向目标主机已有 Docker Engine 和 Docker Compose plugin、但 Docker 运行环境不能访问公网的场景。

## 定位

该交付包是单机 all-in-one 运行包，用于演示、试用、单机验证和内网交付前置验证。它不是生产最佳实践架构，不拆分多容器微服务，不引入 Kubernetes，也不负责安装 Docker。

交付包包含：

- `docker save` 导出的 OpsFactory 镜像 tar
- `docker-compose.yml`
- `load-image.sh`、`start.sh`、`stop.sh`、`status.sh`
- `README.md`
- `SHA256SUMS.txt`
- `build-report.txt`

目标主机不需要 Git、Maven、npm、Java、Node、OS 软件源、GitHub release 访问能力或公网镜像仓库访问能力。

## 运行范围

镜像基础系统为 `openEuler 24.03 LTS SP3`，平台为 `linux/amd64`。`goosed` 固定为 `1.33.1`，因为 openEuler 24.03 LTS SP3 提供 glibc 2.38，而 `goosed 1.34.0` 需要 `GLIBC_2.39`。

镜像包含并启动：

| 组件 | 端口 | 状态 |
| --- | ---: | --- |
| Web App | 5173 | 启用 |
| Gateway | 3000 | 启用 |
| Knowledge Service | 8092 | 启用 |
| Business Intelligence | 8093 | 启用 |
| Control Center | 8094 | 启用 |
| Skill Market | 8095 | 启用 |
| Operation Intelligence | 8096 | 启用 |
| Prometheus Exporter | 9091 | 启用 |
| goosed 1.33.1 | 动态端口 | 启用 |
| Langfuse | 3100 | 禁用 |
| OnlyOffice | 8080 | 禁用 |

Gateway 默认以 HTTP 暴露。镜像不内置 `gateway` keystore 或 PEM 私钥材料。

## 构建

在构建机上执行：

```bash
./scripts/build-offline-package-linux-amd64.sh
```

默认镜像 tag 为：

```text
opsfactory:offline-YYYYMMDD-linux-amd64
```

默认输出：

```text
dist/opsfactory-offline-YYYYMMDD-linux-amd64.tar.gz
```

如需指定 tag：

```bash
./scripts/build-offline-package-linux-amd64.sh \
  --tag opsfactory:offline-20260514-linux-amd64
```

如需使用已下载的 Goose rpm：

```bash
./scripts/build-offline-package-linux-amd64.sh \
  --goose-rpm /path/to/Goose-1.33.1-1.x86_64.rpm
```

构建脚本会生成 sanitized staging 目录，不依赖 Git。若当前目录是 Git 仓库，脚本只把分支、commit 和 status 作为诊断信息写入报告。

## 数据和密钥处理

镜像会内置当前项目的非模型用户数据和运行配置作为 seed data。构建前应确认这些数据可以分发。

构建脚本会保留模型相关配置文件结构，但清空模型 key 值：

- Agent `secrets.yaml` 中被 custom provider `api_key_env` 引用的 key
- `knowledge-service/config.yaml` 中 `knowledge.embedding.api-key`

构建脚本不自动重写 LLM provider、model、base URL 或 embedding endpoint。非模型疑似敏感内容只写入警告，不自动修改，也不默认阻塞构建。

## 目标机安装

将离线包复制到目标 Linux x86_64 主机：

```bash
tar -xzf opsfactory-offline-YYYYMMDD-linux-amd64.tar.gz
cd opsfactory-offline-YYYYMMDD-linux-amd64
./scripts/load-image.sh
./scripts/start.sh
```

启动成功后访问：

```text
http://127.0.0.1:5173
```

`start.sh` 会检查默认端口是否被占用，并等待所有启用服务健康检查通过后输出访问地址。

## 首次启动和持久化

容器首次启动时，会将镜像内的 seed data 复制到 Docker named volumes。已有 volume 不会被覆盖。

如果需要重新从 seed data 初始化：

```bash
./scripts/stop.sh
docker compose -f docker-compose.yml down -v
./scripts/start.sh
```

第一版不提供自动升级迁移或新 seed data 与旧 volume 的合并逻辑。

## 手工配置模型

镜像不会内置真实 LLM 或 embedding key。启动后 Web UI、agent 列表、已有用户数据和配置数据应可见；涉及模型调用的功能在填写对应 key 前失败是预期行为。

进入容器编辑配置：

```bash
docker exec -it opsfactory bash
vi /app/gateway/agents/<agent-id>/config/secrets.yaml
vi /app/knowledge-service/config.yaml
/app/scripts/ctl.sh restart gateway knowledge
exit
```

如果需要更换 provider 或 model，还需要同时检查并修改对应 agent 的配置和 custom provider JSON，确保 `GOOSE_PROVIDER`、`GOOSE_MODEL` 和 provider JSON 中的 `name`、`models[].name` 对齐。

## 运维命令

```bash
./scripts/status.sh
./scripts/stop.sh
docker logs opsfactory --tail 200
```

## 验收标准

- 离线包可在构建机生成。
- 目标 Linux x86_64 主机已有 Docker Engine 和 Docker Compose plugin。
- 目标主机执行 `load-image.sh` 和 `start.sh` 时不发生公网下载。
- Web UI 可通过 `http://<host>:5173` 打开。
- 当前项目 seed 用户数据、agent 列表和配置数据可见。
- Gateway、Knowledge Service、Business Intelligence、Skill Market、Control Center、Operation Intelligence、Prometheus Exporter 健康检查通过。
- Langfuse 和 OnlyOffice 不启动。
- 模型 key 不内置；填 key 前模型调用失败是预期行为。
