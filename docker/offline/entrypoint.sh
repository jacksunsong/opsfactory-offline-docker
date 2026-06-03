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
    ENABLE_ONLYOFFICE=false ENABLE_LANGFUSE=false ENABLE_EXPORTER=false ENABLE_OPERATION_INTELLIGENCE=false \
        "${APP_DIR}/scripts/ctl.sh" shutdown gateway || true
    ENABLE_ONLYOFFICE=false ENABLE_LANGFUSE=false ENABLE_EXPORTER=false ENABLE_OPERATION_INTELLIGENCE=false \
        "${APP_DIR}/scripts/ctl.sh" shutdown knowledge || true
    ENABLE_ONLYOFFICE=false ENABLE_LANGFUSE=false ENABLE_EXPORTER=false ENABLE_OPERATION_INTELLIGENCE=true \
        "${APP_DIR}/scripts/ctl.sh" shutdown operation-intelligence || true
}

trap 'shutdown; exit 0' INT TERM

mkdir -p "${RUNTIME_CONFIG_DIR}"

init_dir_from_seed "${SEED_DIR}/gateway/agents" "${APP_DIR}/gateway/agents"
init_dir_from_seed "${SEED_DIR}/gateway/users" "${APP_DIR}/gateway/users"
init_dir_from_seed "${SEED_DIR}/gateway/data" "${APP_DIR}/gateway/data"
init_dir_from_seed "${SEED_DIR}/knowledge-service/data" "${APP_DIR}/knowledge-service/data"
init_dir_from_seed "${SEED_DIR}/operation-intelligence/data" "${APP_DIR}/operation-intelligence/data"

init_config_file "${SEED_DIR}/gateway/config.yaml" "${APP_DIR}/gateway/config.yaml" "${RUNTIME_CONFIG_DIR}/gateway/config.yaml"
init_config_file "${SEED_DIR}/web-app/config.json" "${APP_DIR}/web-app/config.json" "${RUNTIME_CONFIG_DIR}/web-app/config.json"
# Sync web-app dist config.json so the static server serves the runtime values
if [ -f "${RUNTIME_CONFIG_DIR}/web-app/config.json" ] && [ -d "${APP_DIR}/web-app/dist" ]; then
    cp -a "${RUNTIME_CONFIG_DIR}/web-app/config.json" "${APP_DIR}/web-app/dist/config.json"
fi
if [ -f "${SEED_DIR}/knowledge-service/config.yaml" ]; then
    init_config_file "${SEED_DIR}/knowledge-service/config.yaml" "${APP_DIR}/knowledge-service/config.yaml" "${RUNTIME_CONFIG_DIR}/knowledge-service/config.yaml"
fi
if [ -f "${SEED_DIR}/operation-intelligence/config.yaml" ]; then
    init_config_file "${SEED_DIR}/operation-intelligence/config.yaml" "${APP_DIR}/operation-intelligence/config.yaml" "${RUNTIME_CONFIG_DIR}/operation-intelligence/config.yaml"
fi

find \
    "${APP_DIR}/gateway" \
    -path '*/target/*.jar' -type f -exec touch {} +

export ENABLE_ONLYOFFICE="${ENABLE_ONLYOFFICE:-false}"
export ENABLE_LANGFUSE="${ENABLE_LANGFUSE:-false}"
export ENABLE_EXPORTER="${ENABLE_EXPORTER:-false}"
export ENABLE_OPERATION_INTELLIGENCE="${ENABLE_OPERATION_INTELLIGENCE:-true}"
export GATEWAY_TLS="${GATEWAY_TLS:-false}"
export OFFICE_PREVIEW_ENABLED="${OFFICE_PREVIEW_ENABLED:-false}"
export GOOSED_BIN="${GOOSED_BIN:-/usr/local/bin/goosed}"

log "Starting OpsFactory knowledge-service"
"${APP_DIR}/scripts/ctl.sh" startup knowledge || true

log "Starting OpsFactory operation-intelligence"
"${APP_DIR}/scripts/ctl.sh" startup operation-intelligence || true

log "Starting OpsFactory gateway"
"${APP_DIR}/scripts/ctl.sh" startup gateway

log "Starting webapp static server"
mkdir -p "${APP_DIR}/web-app/logs"
node /usr/local/bin/opsfactory-static-web-server.js "${APP_DIR}/web-app/dist" > "${APP_DIR}/web-app/logs/webapp.log" 2>&1 &
WEBAPP_PID="$!"

log "OpsFactory startup command completed; tailing logs"
mkdir -p \
    "${APP_DIR}/gateway/logs" \
    "${APP_DIR}/web-app/logs"

touch \
    "${APP_DIR}/gateway/logs/gateway.log" \
    "${APP_DIR}/web-app/logs/webapp.log"

tail -F \
    "${APP_DIR}/gateway/logs/gateway.log" \
    "${APP_DIR}/web-app/logs/webapp.log" &

while true; do
    sleep 3600
done
