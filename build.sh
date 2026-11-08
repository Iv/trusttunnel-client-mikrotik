#!/bin/sh
# Local build. Usage: ./build.sh [VERSION] [--push]
# VERSION defaults to the contents of the VERSION file.
set -eu
case "${1:-}" in ""|-*) V="$(cat VERSION)" ;; *) V="$1"; shift ;; esac
mkdir -p dist
for a in aarch64 armv7; do
  curl -fsSL -o "dist/tt-$a.tgz" \
    "https://github.com/TrustTunnel/TrustTunnelClient/releases/download/v$V/trusttunnel_client-v$V-linux-$a.tar.gz"
done
docker buildx build --builder "${BUILDER:-tt-builder}" --platform linux/arm64,linux/arm/v7 --build-arg VERSION="$V" \
  -t "quai1rol/trusttunnel-client-mikrotik:$V" -t quai1rol/trusttunnel-client-mikrotik:latest "$@" .
