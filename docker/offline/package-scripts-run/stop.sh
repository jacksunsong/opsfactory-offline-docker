#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"
set -a; source ./config.env; set +a
CONTAINER_NAME="${CONTAINER_NAME:-opsfactory}"
if docker ps -a --format '{{.Names}}' | grep -qx "${CONTAINER_NAME}"; then
    docker stop "${CONTAINER_NAME}" >/dev/null 2>&1 || true
    docker rm "${CONTAINER_NAME}" >/dev/null 2>&1 || true
    echo "Container ${CONTAINER_NAME} stopped and removed."
else
    echo "Container ${CONTAINER_NAME} is not running."
fi
