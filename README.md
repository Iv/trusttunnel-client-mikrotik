# trusttunnel-client-mikrotik

**English** | [Русский](https://github.com/Iv/trusttunnel-client-mikrotik/blob/main/README.ru.md)

Minimal Docker image of the [TrustTunnel client](https://github.com/TrustTunnel/TrustTunnelClient)
for MikroTik RouterOS containers.

- Source: [github.com/Iv/trusttunnel-client-mikrotik](https://github.com/Iv/trusttunnel-client-mikrotik)
- Docker Hub: [`quai1rol/trusttunnel-client-mikrotik`](https://hub.docker.com/r/quai1rol/trusttunnel-client-mikrotik)

- **Platforms:** `linux/arm64` (hAP ax2, ax3, …) and `linux/arm/v7` (hAP ac2, ac3, …).
- **Small:** ~10 MB. The upstream binaries are static, so the base image is just
  `busybox:musl` plus the CA bundle.
- **Easy on the flash:** the client writes no log files. Everything goes to stdout,
  which RouterOS keeps in its memory log when the container has `logging=yes`.
  The only file written at runtime is the generated `client.toml`, once per start.
- **Restarts itself:** the client exits after a few failed connection attempts
  (for example when the WAN is not up yet at boot). The entrypoint restores the
  original default route and starts the client again.
- **Env-compatible** with `vardo/trusttunnel-client-mikrotik`.

The idea and the first version of the RouterOS instructions come from
[`vardo/trusttunnel-client-mikrotik`](https://hub.docker.com/r/vardo/trusttunnel-client-mikrotik).
This image is a rework of it: a newer client, a much smaller image so it fits on the
internal flash of devices without USB storage, a restart loop, and failover examples.

## Environment variables

| Variable | Required | Default | Description |
|---|---|---|---|
| `TT_ADDRESS` | yes | | Endpoint `IP:PORT` |
| `TT_HOSTNAME` | yes | | Endpoint TLS host name |
| `TT_USER` | yes | | Username |
| `TT_PASS` | yes | | Password |
| `TT_EXPOSE` | no | | Space-separated networks routed outside the tunnel (via the container's original gateway), e.g. your LAN. Not needed with the NAT setup below |
| `TT_TUN_DEV` | no | `tun0` | TUN interface name |
| `TT_IPV6` | no | `0` | Set to `1` to carry IPv6 through the tunnel (`has_ipv6` and the `2000::/3` route) |
| `TT_LOGLEVEL` | no | `info` | `error`, `warn`, `info`, `debug`, `trace` |
| `TT_RESTART` | no | `1` | Set to `0` to let the container exit when the client exits |
| `TT_RESTART_DELAY` | no | `10` | Seconds to wait before restarting the client |
| `TT_CONFIG` | no | `/opt/trusttunnel/client.toml` | Path of the generated config |

The generated config uses `vpn_mode = "general"` and `killswitch_enabled = false`.

## RouterOS setup

Tested on hAP ac³ (armv7, 128 MB flash, 256 MB RAM) with RouterOS 7.25. No USB disk is
needed: the image takes about 7 MB on flash. The syntax can differ slightly between
RouterOS 7.x versions.

Addresses used below (replace with your own):

| | |
|---|---|
| RouterOS side of the veth | `172.31.31.1/24` |
| Container | `172.31.31.2/24` |
| TrustTunnel endpoint | `203.0.113.10:443`, host name `vpn.example.com` |

### 1. Enable containers

`device-mode` needs a physical confirmation (reset button or power cycle), see the
[RouterOS container docs](https://help.mikrotik.com/docs/spaces/ROS/pages/84901929/Container).
Installing the package reboots the router.

```routeros
/system/device-mode/update container=yes
/system/package/enable container
/system/package/apply-changes
```

### 2. Trust Docker Hub's TLS certificate

Without it the pull fails with `SSL: no trusted CA certificate found`. Either enable the
built-in trust store:

```routeros
/certificate/settings/set builtin-trust-store=all
```

or import only the roots Docker Hub needs: Amazon Root CA 1 and Starfield Services
Root G2 (registry), ISRG Root X1 (auth and layer CDN). Download them on a PC, then
copy them to the router:

```sh
curl -fsSLO https://www.amazontrust.com/repository/AmazonRootCA1.pem
curl -fsSLO https://www.amazontrust.com/repository/SFSRootCAG2.pem
curl -fsSLO https://letsencrypt.org/certs/isrgrootx1.pem
scp AmazonRootCA1.pem SFSRootCAG2.pem isrgrootx1.pem admin@ROUTER:
```

```routeros
/certificate/import file-name=AmazonRootCA1.pem passphrase=""
/certificate/import file-name=SFSRootCAG2.pem passphrase=""
/certificate/import file-name=isrgrootx1.pem passphrase=""
```

### 3. Keep image pulls off the flash (optional)

The downloaded layers are unpacked into the container's root dir anyway. A RAM disk for
the temporary files avoids writing every layer to flash twice.

```routeros
/disk/add type=tmpfs tmpfs-max-size=48M slot=ram comment="container pull tmp (RAM)"
/container/config/set tmpdir=ram
```

### 4. Network: veth and NAT

```routeros
/interface/veth/add name=TT-VETH address=172.31.31.2/24 gateway=172.31.31.1
/ip/address/add address=172.31.31.1/24 interface=TT-VETH

# Masquerade everything sent into the container: the container then sees a single
# source address (172.31.31.1) and replies go back without extra routes inside it.
/ip/firewall/nat/add chain=srcnat out-interface=TT-VETH action=masquerade comment="trusttunnel container"
```

The container reaches the endpoint through the router's normal WAN masquerade. If your
`forward` chain ends with a drop, also allow `src-address=172.31.31.2`.

The endpoint IP must always be routed through the WAN, never through the tunnel.
This is automatic unless you send a default route or a big prefix list (BGP, address
lists) through the container. Then add a direct route:

```routeros
/ip/route/add dst-address=203.0.113.10/32 gateway=WAN_GATEWAY comment="trusttunnel endpoint direct"
```

### 5. Container

`TT_ADDRESS` must be an IP address, not a host name.

```routeros
/container/envs/add list=tt key=TT_ADDRESS  value=203.0.113.10:443
/container/envs/add list=tt key=TT_HOSTNAME value=vpn.example.com
/container/envs/add list=tt key=TT_USER     value=user
/container/envs/add list=tt key=TT_PASS     value=secret

/container/add remote-image=quai1rol/trusttunnel-client-mikrotik:latest \
    interface=TT-VETH envlist=tt root-dir=tt logging=yes start-on-boot=yes comment=trusttunnel
/container/start [find comment=trusttunnel]
```

Check the log. A working tunnel shows `VPN_SS_CONNECTED` and `Successfully connected to endpoint`:

```routeros
/log/print where topics~"container"
```

From the container itself:

```routeros
/container/shell [find comment=trusttunnel] cmd="wget -qO- https://api.ipify.org"
```

To make sure nothing is logged to flash, check that the `container` topic goes
to a `memory` action in `/system/logging` (this is the RouterOS default).

### 6. Route something through it

The gateway is the container IP (`172.31.31.2`), not the interface. Start with a single
address and check the exit IP from a LAN host:

```routeros
/ip/route/add dst-address=1.0.0.1/32 gateway=172.31.31.2 comment="tt-probe: health check via trusttunnel"
```

```sh
curl -s https://1.0.0.1/cdn-cgi/trace | grep ^ip=    # must show the VPN exit IP
```

ICMP is not carried through the tunnel, so test with TCP (curl, fetch), not ping.

### 7. Failover to another VPN

The veth interface is always up while the container runs, even when the tunnel is
down, so `check-gateway` and interface state can't detect an outage. Use netwatch with
a TCP check through the tunnel, and mark the routes it should switch with a comment
prefix (`tt-failover`).

The setup below routes a BGP prefix list (or any other routes) through a virtual next
hop `10.255.99.1`. That next hop is resolved through TrustTunnel first and through
another VPN (`sstp-vr` here) as a backup:

```routeros
# BGP input filter (or static routes): gateway = virtual next hop
/routing/filter/rule/add chain=bgp-in rule="set gw 10.255.99.1; accept;"

# Next hop: TrustTunnel (primary), SSTP (backup). scope=10 is needed for recursive resolution.
/ip/route/add dst-address=10.255.99.1/32 gateway=172.31.31.2 distance=1 scope=10 target-scope=10 \
    comment="tt-failover: next hop via trusttunnel"
/ip/route/add dst-address=10.255.99.1/32 gateway=sstp-vr distance=2 scope=10 target-scope=10 \
    comment="next hop via sstp (backup)"

# Policy-routing table: the same idea for a default route
/routing/table/add name=xoxo fib
/ip/route/add dst-address=0.0.0.0/0 routing-table=xoxo gateway=172.31.31.2 distance=1 \
    comment="tt-failover: xoxo via trusttunnel"
/ip/route/add dst-address=0.0.0.0/0 routing-table=xoxo gateway=sstp-vr distance=2 \
    comment="xoxo via sstp (backup)"

# Health probe: 1.0.0.1 always through the tunnel, never leaking to the WAN
/ip/route/add dst-address=1.0.0.1/32 gateway=172.31.31.2 distance=1 comment="tt-probe: via trusttunnel"
/ip/route/add dst-address=1.0.0.1/32 blackhole distance=2 comment="tt-probe: never leak to WAN"

/tool/netwatch/add name=tt-health type=tcp-conn host=1.0.0.1 port=443 interval=10s timeout=5s \
    up-script="/ip/route/enable [find comment~\"^tt-failover\"]; :log info \"tt-health: UP\"" \
    down-script="/ip/route/disable [find comment~\"^tt-failover\"]; :log warning \"tt-health: DOWN\""
```

How it behaves:

- tunnel down while the container runs: netwatch goes `down` within 10–20 s, the
  `tt-failover` routes are disabled and traffic moves to the backup. When the tunnel is
  back, the routes are enabled again;
- container stopped: the veth goes down, the routes through `172.31.31.2` become
  inactive by themselves, and the backup takes over immediately.

Keep everything the backup itself depends on (for example the BGP session's peer
network, or the endpoint IP) on routes that do not go through the container.

## Publishing (GitHub Actions)

[`.github/workflows/publish.yml`](.github/workflows/publish.yml) builds `linux/arm64` + `linux/arm/v7`
and pushes `:<version>` and `:latest` to Docker Hub:

- on push to `main` that changes the image files (builds the version in `VERSION`);
- manually (*Actions → Publish to Docker Hub → Run workflow*), optionally with a version;
- weekly: if upstream has a newer **stable** release, it builds it and commits the new `VERSION`.

It also syncs this README to the Docker Hub overview.

Repository settings needed:

- variable `DOCKERHUB_USERNAME` = `quai1rol`;
- secret `DOCKERHUB_TOKEN` = a Docker Hub access token. **Read & Write** is enough to push;
  **Read, Write, Delete** is needed to update the Docker Hub description.

## Building locally

The release tarballs are downloaded on the host into `dist/`, then built with buildx:

```sh
./build.sh                   # build the version from VERSION
./build.sh 1.1.11 --push     # build and push :1.1.11 and :latest
```

`build.sh` uses the buildx builder named `tt-builder`. Set `BUILDER=<name>` to use
a different one. The builder needs QEMU/binfmt for arm64 and arm/v7.
