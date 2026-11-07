#!/bin/sh
set -eu

: "${TT_ADDRESS:?TT_ADDRESS not set (expected ENDPOINT_IP:PORT)}"
: "${TT_HOSTNAME:?TT_HOSTNAME not set}"
: "${TT_USER:?TT_USER not set}"
: "${TT_PASS:?TT_PASS not set}"

CFG="${TT_CONFIG:-/opt/trusttunnel/client.toml}"
EP_IP="$(printf '%s' "$TT_ADDRESS" | cut -d: -f1)"
TUN_DEV="${TT_TUN_DEV:-tun0}"

log() { printf '%s\n' "$*"; }

prepare_tun() {
  # RouterOS containers do not always expose /dev/net/tun as a filesystem node,
  # even when the host kernel has TUN support.
  mkdir -p /dev/net
  if [ ! -c /dev/net/tun ]; then
    mknod /dev/net/tun c 10 200 2>/dev/null || true
    chmod 600 /dev/net/tun 2>/dev/null || true
  fi
  if [ ! -c /dev/net/tun ]; then
    log "ERROR: /dev/net/tun is unavailable. RouterOS/container kernel TUN support is missing or blocked."
    exit 1
  fi
  # Since 1.1.x the client creates the device itself with the exact name from
  # device_name; remove a stale one left from a previous run.
  ip link delete "$TUN_DEV" 2>/dev/null || true
}

# Keep compatibility with the original image: detect the current route to the
# endpoint before replacing the default route with tun0.
VIA="$(ip route get "$EP_IP" 2>/dev/null | head -n1 | sed 's/uid.*//g' | sed 's/.*via//' | awk '{print $1}' || true)"

/opt/trusttunnel/setup_wizard -m non-interactive \
  -a "$TT_ADDRESS" \
  -n "$TT_HOSTNAME" \
  -c "$TT_USER:$TT_PASS" \
  --settings "$CFG" >/dev/null || { log "ERROR: setup_wizard failed"; exit 1; }

# Preserve behavior from vardo/POPSuL image.
sed -i 's/^vpn_mode = .*/vpn_mode = "general"/' "$CFG" || true
sed -i 's/^killswitch_enabled = .*/killswitch_enabled = false/' "$CFG" || true
# Log level (stdout only; the client never writes log files).
sed -i "s/^loglevel = .*/loglevel = \"${TT_LOGLEVEL:-info}\"/" "$CFG" || true
# 1.1.x+: fixed tun name instead of a kernel-assigned one (tun0/tun1/...).
sed -i "s/^device_name = .*/device_name = \"$TUN_DEV\"/" "$CFG" || true
log "TrustTunnel config written to $CFG"

# Original default route (via veth); it is replaced by tun0 and disappears
# together with tun0 when the client exits, so restore it before restarting.
ORIG_DEFAULT="$(ip route | grep '^default' | grep -v "dev $TUN_DEV" | head -n1 || true)"

TT_PID=""
STOPPING=0
on_term() {
  STOPPING=1
  [ -z "$TT_PID" ] || kill -TERM "$TT_PID" 2>/dev/null || true
}
trap on_term TERM INT

configure_routing() {
  log "Configuring routing..."
  ip route replace default dev "$TUN_DEV" || true
  if [ -n "${VIA:-}" ]; then
    ip route add "$EP_IP" via "$VIA" 2>/dev/null || ip route replace "$EP_IP" via "$VIA" || true
  fi
  if [ -n "${TT_EXPOSE:-}" ]; then
    for net in $TT_EXPOSE; do
      log "Exposing $net via $VIA"
      ip route add "$net" via "$VIA" 2>/dev/null || ip route replace "$net" via "$VIA" || true
    done
  fi
}

# The client exits after a few failed connection attempts (e.g. WAN not up yet
# at boot). RouterOS does not restart containers by itself, so restart here.
while :; do
  if [ -n "$ORIG_DEFAULT" ]; then
    # shellcheck disable=SC2086
    ip route replace $ORIG_DEFAULT 2>/dev/null || true
  fi
  prepare_tun
  /opt/trusttunnel/trusttunnel_client -c "$CFG" &
  TT_PID=$!

  for i in $(seq 1 80); do
    ip link show "$TUN_DEV" >/dev/null 2>&1 && break
    kill -0 "$TT_PID" 2>/dev/null || break
    sleep 0.25
  done

  if ip link show "$TUN_DEV" >/dev/null 2>&1; then
    configure_routing
    log "TrustTunnel client is running with PID $TT_PID"
    log "ip ro:"
    ip ro
  fi

  RC=0
  wait "$TT_PID" || RC=$?
  # wait returns early when a trapped signal arrives; reap the client.
  [ "$STOPPING" = 1 ] && { wait "$TT_PID" 2>/dev/null || true; exit 0; }
  TT_PID=""
  [ "${TT_RESTART:-1}" = 1 ] || exit "$RC"
  log "trusttunnel_client exited (code $RC), restarting in ${TT_RESTART_DELAY:-10}s..."
  sleep "${TT_RESTART_DELAY:-10}" &
  wait $! || true
  [ "$STOPPING" = 1 ] && exit 0
done
