#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"
set -a; source ./config.env; set +a
CONTAINER_NAME="${CONTAINER_NAME:-opsfactory}"

echo "=== Container ==="
docker ps -a --filter "name=${CONTAINER_NAME}" --format 'table {{.Names}}\t{{.Status}}\t{{.Networks}}'
echo
echo "=== HTTP checks ==="
for url in "http://127.0.0.1:5173/" "http://127.0.0.1:3000/" "http://127.0.0.1:8092/actuator/health" "http://127.0.0.1:8096/actuator/health"; do
    code="$(curl -s -o /dev/null -w '%{http_code}' "${url}" 2>/dev/null || echo "000")"
    echo "  ${url} -> ${code}"
done
echo
echo "=== Network mode ==="
docker inspect "${CONTAINER_NAME}" --format 'NetworkMode={{.HostConfig.NetworkMode}}' 2>/dev/null || true
echo
echo "=== Resource usage ==="
docker stats "${CONTAINER_NAME}" --no-stream --format 'CPU={{.CPUPerc}} Mem={{.MemUsage}}' 2>/dev/null || true
