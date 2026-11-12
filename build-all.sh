#!/usr/bin/env bash
# Build both Castaway images: the main app and the optional AI (transcription) sidecar.
# Run from anywhere; it always builds from the repo root.
set -euo pipefail
cd "$(dirname "$0")"

TAG="${1:-latest}"

echo "==> Building castaway:${TAG} (main app)"
docker build -t "castaway:${TAG}" .

echo "==> Building castaway-ai:${TAG} (AI sidecar)"
docker build -t "castaway-ai:${TAG}" ./pinepods-ai

echo "==> Done. Built:"
echo "    castaway:${TAG}"
echo "    castaway-ai:${TAG}"
