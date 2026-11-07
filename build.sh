#!/bin/sh
# Usage: ./build.sh 1.1.11 [--push]
set -eu
V="$1"; shift || true
mkdir -p dist
for a in aarch64 armv7; do
  curl -fsSL -o "dist/tt-$a.tgz" \
    "https://github.com/TrustTunnel/TrustTunnelClient/releases/download/v$V/trusttunnel_client-v$V-linux-$a.tar.gz"
done
docker buildx build --builder "${BUILDER:-tt-builder}" --platform linux/arm64,linux/arm/v7 --build-arg VERSION="$V" \
  -t "quai1rol/trusttunnel-client-mikrotik:$V" -t quai1rol/trusttunnel-client-mikrotik:latest "$@" .
