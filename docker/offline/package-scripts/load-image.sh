#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE_TAR="${ROOT_DIR}/images/opsfactory-linux-amd64.tar"

if [ ! -f "${IMAGE_TAR}" ]; then
    echo "Image archive not found: ${IMAGE_TAR}" >&2
    exit 1
fi

cd "${ROOT_DIR}"
if command -v sha256sum >/dev/null 2>&1; then
    sha256sum -c SHA256SUMS.txt
elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 -c SHA256SUMS.txt
else
    echo "sha256sum/shasum not found; skipping checksum verification" >&2
fi

docker load -i "${IMAGE_TAR}"
