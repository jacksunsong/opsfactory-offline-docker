FROM --platform=linux/amd64 maven:3.9.9-eclipse-temurin-21 AS java-builder

WORKDIR /src
COPY . /src

RUN set -eux; \
    cd /src/gateway; \
    mvn -q -DskipTests package; \
    cd /src/knowledge-service; \
    mvn -q -DskipTests package; \
    cd /src/business-intelligence; \
    mvn -q -DskipTests package; \
    cd /src/skill-market; \
    mvn -q -DskipTests package; \
    cd /src/control-center; \
    mvn -q -DskipTests package; \
    cd /src/operation-intelligence; \
    mvn -q -DskipTests package; \
    cd /src/prometheus-exporter; \
    mvn -q -DskipTests package

FROM --platform=linux/amd64 node:20-bookworm-slim AS node-builder

WORKDIR /src
COPY . /src
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN set -eux; \
    npm install --prefix /src --no-audit --no-fund --no-save yaml; \
    cd /src/typescript-sdk; \
    npm ci --no-audit --no-fund; \
    npm run build; \
    cd /src/web-app; \
    npm ci --no-audit --no-fund; \
    npm run build

RUN set -eux; \
    while IFS= read -r pkg; do \
        dir="$(dirname "${pkg}")"; \
        case "${dir}" in */node_modules/*) continue ;; esac; \
        case "${dir}" in */browser-use) continue ;; esac; \
        cd "/src/${dir}"; \
        if [ -f package-lock.json ]; then \
            npm ci --no-audit --no-fund; \
        else \
            npm install --no-audit --no-fund; \
        fi; \
        if node -e "const p=require('./package.json'); process.exit(p.scripts && p.scripts.build ? 0 : 1)"; then \
            npm run build; \
        elif [ -f tsconfig.json ]; then \
            npx tsc; \
        fi; \
        cd /src; \
    done < <(find gateway/agents -path '*/node_modules' -prune -o -path '*/config/mcp/*/package.json' -print | sort)

FROM --platform=linux/amd64 openeuler/openeuler:24.03-lts-sp3

ARG GOOSE_RPM=vendor/goose/Goose-1.33.1-1.x86_64.rpm
ARG GOOSE_VERSION=1.33.1

ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    ENABLE_ONLYOFFICE=false \
    ENABLE_LANGFUSE=false \
    ENABLE_EXPORTER=true \
    ENABLE_OPERATION_INTELLIGENCE=true \
    GATEWAY_TLS=false \
    OFFICE_PREVIEW_ENABLED=false

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN set -eux; \
    for attempt in 1 2 3 4 5; do \
        dnf -y makecache && \
        dnf -y install --setopt=install_weak_deps=False --nodocs \
            ca-certificates \
            cpio \
            curl \
            findutils \
            gzip \
            hostname \
            java-21-openjdk-headless \
            libgomp \
            lsof \
            net-tools \
            nodejs \
            npm \
            procps-ng \
            python3 \
            rpm \
            tar \
            unzip \
            util-linux \
            vulkan-loader \
            which \
        && break; \
        if [ "${attempt}" = "5" ]; then exit 1; fi; \
        sleep "$((attempt * 10))"; \
    done; \
    dnf clean all; \
    rm -rf /var/cache/dnf

WORKDIR /app
COPY . /app
COPY --from=java-builder /src/gateway/gateway-common/target /app/gateway/gateway-common/target
COPY --from=java-builder /src/gateway/gateway-service/target /app/gateway/gateway-service/target
COPY --from=java-builder /src/knowledge-service/target /app/knowledge-service/target
COPY --from=java-builder /src/business-intelligence/target /app/business-intelligence/target
COPY --from=java-builder /src/skill-market/target /app/skill-market/target
COPY --from=java-builder /src/control-center/target /app/control-center/target
COPY --from=java-builder /src/operation-intelligence/target /app/operation-intelligence/target
COPY --from=java-builder /src/prometheus-exporter/target /app/prometheus-exporter/target
COPY --from=node-builder /src/node_modules /app/node_modules
COPY --from=node-builder /src/typescript-sdk/dist /app/typescript-sdk/dist
COPY --from=node-builder /src/typescript-sdk/node_modules /app/typescript-sdk/node_modules
COPY --from=node-builder /src/web-app/dist /app/web-app/dist
COPY --from=node-builder /src/web-app/node_modules /app/web-app/node_modules
COPY --from=node-builder /src/gateway/agents /app/gateway/agents
COPY docker/offline/entrypoint.sh /usr/local/bin/opsfactory-entrypoint.sh
COPY docker/offline/static-web-server.js /usr/local/bin/opsfactory-static-web-server.js

RUN set -eux; \
    chmod +x /usr/local/bin/opsfactory-entrypoint.sh /usr/local/bin/opsfactory-static-web-server.js; \
    mkdir -p /tmp/goose-rpm; \
    cd /tmp/goose-rpm; \
    rpm2cpio "/app/${GOOSE_RPM}" | cpio -idmu; \
    goosed_path="$(find /tmp/goose-rpm -type f -name goosed -perm /111 | head -n 1)"; \
    test -n "${goosed_path}"; \
    install -m 0755 "${goosed_path}" /usr/local/bin/goosed; \
    ldd /usr/local/bin/goosed; \
    if goosed --version > /app/goosed-validation.txt 2>&1; then \
        grep -F "${GOOSE_VERSION}" /app/goosed-validation.txt; \
    else \
        goosed --help > /app/goosed-validation.txt 2>&1; \
    fi; \
    rm -rf /tmp/goose-rpm "/app/${GOOSE_RPM}"

RUN set -eux; \
    mkdir -p /app/seed/gateway /app/seed/knowledge-service /app/seed/business-intelligence \
        /app/seed/skill-market /app/seed/control-center /app/seed/operation-intelligence \
        /app/seed/prometheus-exporter /app/seed/web-app /app/runtime-config; \
    for path in gateway/agents gateway/users gateway/data knowledge-service/data; do \
        if [ -d "/app/${path}" ]; then \
            mkdir -p "/app/seed/$(dirname "${path}")"; \
            cp -a "/app/${path}" "/app/seed/${path}"; \
        else \
            mkdir -p "/app/seed/${path}"; \
        fi; \
    done; \
    for svc in business-intelligence skill-market control-center operation-intelligence; do \
        if [ -d "/app/${svc}/data" ]; then \
            cp -a "/app/${svc}/data" "/app/seed/${svc}/data"; \
        else \
            mkdir -p "/app/seed/${svc}/data"; \
        fi; \
    done; \
    cp -a /app/gateway/config.yaml /app/seed/gateway/config.yaml; \
    cp -a /app/knowledge-service/config.yaml /app/seed/knowledge-service/config.yaml; \
    cp -a /app/business-intelligence/config.yaml /app/seed/business-intelligence/config.yaml; \
    cp -a /app/skill-market/config.yaml /app/seed/skill-market/config.yaml; \
    cp -a /app/control-center/config.yaml /app/seed/control-center/config.yaml; \
    cp -a /app/operation-intelligence/config.yaml /app/seed/operation-intelligence/config.yaml; \
    cp -a /app/prometheus-exporter/config.yaml /app/seed/prometheus-exporter/config.yaml; \
    cp -a /app/web-app/config.json /app/seed/web-app/config.json; \
    rm -rf \
        /app/gateway/gateway-common/src \
        /app/gateway/gateway-service/src \
        /app/knowledge-service/src \
        /app/business-intelligence/src \
        /app/skill-market/src \
        /app/control-center/src \
        /app/operation-intelligence/src \
        /app/prometheus-exporter/src \
        /app/web-app/src \
        /app/web-app/node_modules; \
    find /app/gateway/agents -path '*/config/mcp/*/src' -type d -prune -exec rm -rf {} +; \
    find /app -name '*.ts' -delete; \
    find /app -name '*.tsx' -delete; \
    find /app -name '*.tsbuildinfo' -delete; \
    find /app -name '.DS_Store' -delete; \
    find /app -path '*/target/*-sources.jar' -delete; \
    find /app -path '*/target/*-javadoc.jar' -delete

EXPOSE 3000 5173 8092 8093 8094 8095 8096 9091

ENTRYPOINT ["/usr/local/bin/opsfactory-entrypoint.sh"]
