#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="${ROOT_DIR}/docker-compose.yml"

required_ports=(5173 3000 8092 8093 8094 8095 8096 9091)

port_in_use() {
    local port="$1"
    if command -v lsof >/dev/null 2>&1; then
        lsof -nP -iTCP:"${port}" -sTCP:LISTEN >/dev/null 2>&1
        return $?
    fi
    if command -v ss >/dev/null 2>&1; then
        ss -ltn | awk '{print $4}' | grep -Eq "[:.]${port}$"
        return $?
    fi
    if command -v netstat >/dev/null 2>&1; then
        netstat -ltn 2>/dev/null | awk '{print $4}' | grep -Eq "[:.]${port}$"
        return $?
    fi
    return 1
}

wait_http() {
    local name="$1"
    local url="$2"
    local header="${3:-}"
    local attempts="${4:-120}"
    local delay="${5:-2}"
    for ((i = 1; i <= attempts; i++)); do
        if [ -n "${header}" ]; then
            curl -fsS "${url}" -H "${header}" >/dev/null 2>&1 && return 0
        else
            curl -fsS "${url}" >/dev/null 2>&1 && return 0
        fi
        sleep "${delay}"
    done
    echo "Health check failed for ${name}: ${url}" >&2
    return 1
}

wait_gateway() {
    local attempts="${1:-120}"
    local delay="${2:-2}"
    local code
    for ((i = 1; i <= attempts; i++)); do
        code="$(curl -sS -o /dev/null -w '%{http_code}' "http://127.0.0.1:3000/gateway/status" -H "x-secret-key: test" 2>/dev/null || true)"
        if [ "${code}" = "200" ] || [ "${code}" = "401" ]; then
            return 0
        fi
        sleep "${delay}"
    done
    echo "Health check failed for Gateway: http://127.0.0.1:3000/gateway/status" >&2
    return 1
}

if ! docker compose version >/dev/null 2>&1; then
    echo "docker compose plugin is required" >&2
    exit 1
fi

if ! docker ps --format '{{.Names}}' | grep -qx 'opsfactory'; then
    for port in "${required_ports[@]}"; do
        if port_in_use "${port}"; then
            echo "Port ${port} is already in use. Stop the existing service or edit docker-compose.yml before starting." >&2
            exit 1
        fi
    done
fi

docker compose -f "${COMPOSE_FILE}" up -d

if ! wait_http "Web App" "http://127.0.0.1:5173" "" 120 2 \
    || ! wait_gateway 120 2 \
    || ! wait_http "Knowledge Service" "http://127.0.0.1:8092/actuator/health" "" 120 2 \
    || ! wait_http "Business Intelligence" "http://127.0.0.1:8093/actuator/health" "" 120 2 \
    || ! wait_http "Skill Market" "http://127.0.0.1:8095/actuator/health" "" 120 2 \
    || ! wait_http "Operation Intelligence" "http://127.0.0.1:8096/actuator/health" "" 120 2 \
    || ! wait_http "Prometheus Exporter" "http://127.0.0.1:9091/health" "" 120 2 \
    || ! wait_http "Control Center" "http://127.0.0.1:8094/actuator/health" "" 120 2; then
    docker logs opsfactory --tail 200 >&2 || true
    exit 1
fi

echo "OpsFactory is ready: http://127.0.0.1:5173"
