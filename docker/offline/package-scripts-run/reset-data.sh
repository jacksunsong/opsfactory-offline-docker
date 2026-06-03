#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"
set -a; source ./config.env; set +a
CONTAINER_NAME="${CONTAINER_NAME:-opsfactory}"
DATA_DIR="${DATA_DIR:-./data}"
read -rp "This will delete ALL data under ${DATA_DIR}. Type 'yes' to continue: " confirm
if [ "${confirm}" != "yes" ]; then echo "Aborted."; exit 0; fi
if docker ps -a --format '{{.Names}}' | grep -qx "${CONTAINER_NAME}"; then
    docker stop "${CONTAINER_NAME}" >/dev/null 2>&1 || true
    docker rm "${CONTAINER_NAME}" >/dev/null 2>&1 || true
fi
rm -rf "${DATA_DIR}/agents" "${DATA_DIR}/users" "${DATA_DIR}/gateway-data" "${DATA_DIR}/runtime-config"
echo "Data cleared. Run ./start.sh to reinitialize."
