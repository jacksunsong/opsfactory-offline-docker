#!/usr/bin/env bash
set -euo pipefail

APP_DIR="/app"
SEED_DIR="${APP_DIR}/seed"
RUNTIME_CONFIG_DIR="${APP_DIR}/runtime-config"

log() {
    printf '[opsfactory] %s\n' "$*"
}

is_empty_dir() {
    local dir="$1"
    [ ! -d "${dir}" ] && return 0
    [ -z "$(find "${dir}" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]
}

init_dir_from_seed() {
    local seed="$1"
    local target="$2"
    mkdir -p "${target}"
    if [ ! -d "${seed}" ]; then
        return 0
    fi
    if is_empty_dir "${target}"; then
        log "Initializing ${target} from seed"
        cp -a "${seed}/." "${target}/"
    else
        log "Keeping existing ${target}"
    fi
}

init_config_file() {
    local seed_file="$1"
    local target_file="$2"
    local runtime_file="$3"
    mkdir -p "$(dirname "${runtime_file}")"
    if [ ! -f "${runtime_file}" ] && [ -f "${seed_file}" ]; then
        log "Initializing ${runtime_file} from seed"
        cp -a "${seed_file}" "${runtime_file}"
    fi
    rm -f "${target_file}"
    ln -s "${runtime_file}" "${target_file}"
}

shutdown() {
    log "Stopping OpsFactory services"
    if [ -n "${WEBAPP_PID:-}" ]; then
        kill "${WEBAPP_PID}" 2>/dev/null || true
    fi
    ENABLE_ONLYOFFICE=false ENABLE_LANGFUSE=false ENABLE_EXPORTER=true ENABLE_OPERATION_INTELLIGENCE=true \
        "${APP_DIR}/scripts/ctl.sh" shutdown all || true
}

trap 'shutdown; exit 0' INT TERM

mkdir -p "${RUNTIME_CONFIG_DIR}"

init_dir_from_seed "${SEED_DIR}/gateway/agents" "${APP_DIR}/gateway/agents"
init_dir_from_seed "${SEED_DIR}/gateway/users" "${APP_DIR}/gateway/users"
init_dir_from_seed "${SEED_DIR}/gateway/data" "${APP_DIR}/gateway/data"
init_dir_from_seed "${SEED_DIR}/knowledge-service/data" "${APP_DIR}/knowledge-service/data"
init_dir_from_seed "${SEED_DIR}/business-intelligence/data" "${APP_DIR}/business-intelligence/data"
init_dir_from_seed "${SEED_DIR}/skill-market/data" "${APP_DIR}/skill-market/data"
init_dir_from_seed "${SEED_DIR}/control-center/data" "${APP_DIR}/control-center/data"
init_dir_from_seed "${SEED_DIR}/operation-intelligence/data" "${APP_DIR}/operation-intelligence/data"

init_config_file "${SEED_DIR}/gateway/config.yaml" "${APP_DIR}/gateway/config.yaml" "${RUNTIME_CONFIG_DIR}/gateway/config.yaml"
init_config_file "${SEED_DIR}/knowledge-service/config.yaml" "${APP_DIR}/knowledge-service/config.yaml" "${RUNTIME_CONFIG_DIR}/knowledge-service/config.yaml"
init_config_file "${SEED_DIR}/business-intelligence/config.yaml" "${APP_DIR}/business-intelligence/config.yaml" "${RUNTIME_CONFIG_DIR}/business-intelligence/config.yaml"
init_config_file "${SEED_DIR}/skill-market/config.yaml" "${APP_DIR}/skill-market/config.yaml" "${RUNTIME_CONFIG_DIR}/skill-market/config.yaml"
init_config_file "${SEED_DIR}/control-center/config.yaml" "${APP_DIR}/control-center/config.yaml" "${RUNTIME_CONFIG_DIR}/control-center/config.yaml"
init_config_file "${SEED_DIR}/operation-intelligence/config.yaml" "${APP_DIR}/operation-intelligence/config.yaml" "${RUNTIME_CONFIG_DIR}/operation-intelligence/config.yaml"
init_config_file "${SEED_DIR}/prometheus-exporter/config.yaml" "${APP_DIR}/prometheus-exporter/config.yaml" "${RUNTIME_CONFIG_DIR}/prometheus-exporter/config.yaml"
init_config_file "${SEED_DIR}/web-app/config.json" "${APP_DIR}/web-app/config.json" "${RUNTIME_CONFIG_DIR}/web-app/config.json"

find \
    "${APP_DIR}/gateway" \
    "${APP_DIR}/knowledge-service" \
    "${APP_DIR}/business-intelligence" \
    "${APP_DIR}/skill-market" \
    "${APP_DIR}/control-center" \
    "${APP_DIR}/operation-intelligence" \
    "${APP_DIR}/prometheus-exporter" \
    -path '*/target/*.jar' -type f -exec touch {} +

export ENABLE_ONLYOFFICE="${ENABLE_ONLYOFFICE:-false}"
export ENABLE_LANGFUSE="${ENABLE_LANGFUSE:-false}"
export ENABLE_EXPORTER="${ENABLE_EXPORTER:-true}"
export ENABLE_OPERATION_INTELLIGENCE="${ENABLE_OPERATION_INTELLIGENCE:-true}"
export GATEWAY_TLS="${GATEWAY_TLS:-false}"
export OFFICE_PREVIEW_ENABLED="${OFFICE_PREVIEW_ENABLED:-false}"
export GOOSED_BIN="${GOOSED_BIN:-/usr/local/bin/goosed}"

log "Starting OpsFactory backend services"
"${APP_DIR}/scripts/ctl.sh" startup gateway knowledge business-intelligence skill-market operation-intelligence exporter control-center

log "Starting webapp static server"
mkdir -p "${APP_DIR}/web-app/logs"
node /usr/local/bin/opsfactory-static-web-server.js "${APP_DIR}/web-app/dist" > "${APP_DIR}/web-app/logs/webapp.log" 2>&1 &
WEBAPP_PID="$!"

log "OpsFactory startup command completed; tailing logs"
mkdir -p \
    "${APP_DIR}/gateway/logs" \
    "${APP_DIR}/knowledge-service/logs" \
    "${APP_DIR}/business-intelligence/logs" \
    "${APP_DIR}/skill-market/logs" \
    "${APP_DIR}/control-center/logs" \
    "${APP_DIR}/operation-intelligence/logs" \
    "${APP_DIR}/prometheus-exporter/logs" \
    "${APP_DIR}/web-app/logs"

touch \
    "${APP_DIR}/gateway/logs/gateway.log" \
    "${APP_DIR}/knowledge-service/logs/knowledge-service.log" \
    "${APP_DIR}/business-intelligence/logs/business-intelligence.log" \
    "${APP_DIR}/skill-market/logs/skill-market.log" \
    "${APP_DIR}/control-center/logs/control-center.log" \
    "${APP_DIR}/operation-intelligence/logs/operation-intelligence.log" \
    "${APP_DIR}/prometheus-exporter/logs/prometheus-exporter.log" \
    "${APP_DIR}/web-app/logs/webapp.log"

tail -F \
    "${APP_DIR}/gateway/logs/gateway.log" \
    "${APP_DIR}/knowledge-service/logs/knowledge-service.log" \
    "${APP_DIR}/business-intelligence/logs/business-intelligence.log" \
    "${APP_DIR}/skill-market/logs/skill-market.log" \
    "${APP_DIR}/control-center/logs/control-center.log" \
    "${APP_DIR}/operation-intelligence/logs/operation-intelligence.log" \
    "${APP_DIR}/prometheus-exporter/logs/prometheus-exporter.log" \
    "${APP_DIR}/web-app/logs/webapp.log" &

wait $!
