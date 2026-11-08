# trusttunnel-client-mikrotik

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

## Environment variables

| Variable | Required | Default | Description |
|---|---|---|---|
| `TT_ADDRESS` | yes | | Endpoint `IP:PORT` |
| `TT_HOSTNAME` | yes | | Endpoint TLS host name |
| `TT_USER` | yes | | Username |
| `TT_PASS` | yes | | Password |
| `TT_EXPOSE` | no | | Space-separated networks that should be routed outside the tunnel (via the container's original gateway), e.g. your LAN |
| `TT_TUN_DEV` | no | `tun0` | TUN interface name |
| `TT_LOGLEVEL` | no | `info` | `error`, `warn`, `info`, `debug`, `trace` |
| `TT_RESTART` | no | `1` | Set to `0` to let the container exit when the client exits |
| `TT_RESTART_DELAY` | no | `10` | Seconds to wait before restarting the client |
| `TT_CONFIG` | no | `/opt/trusttunnel/client.toml` | Path of the generated config |

The generated config uses `vpn_mode = "general"` and `killswitch_enabled = false`.

## RouterOS example

The command syntax can differ slightly between RouterOS 7.x versions.

```routeros
/interface/veth/add name=TT-VETH address=172.31.31.2/24 gateway=172.31.31.1
/ip/address/add address=172.31.31.1/24 interface=TT-VETH

/container/envs/add list=tt key=TT_ADDRESS  value=203.0.113.10:443
/container/envs/add list=tt key=TT_HOSTNAME value=vpn.example.com
/container/envs/add list=tt key=TT_USER     value=user
/container/envs/add list=tt key=TT_PASS     value=secret
/container/envs/add list=tt key=TT_EXPOSE   value=192.168.88.0/24

/container/add remote-image=quai1rol/trusttunnel-client-mikrotik:latest \
    interface=TT-VETH envlist=tt root-dir=tt logging=yes start-on-boot=yes
```

To make sure nothing is logged to flash, check that the `container` topic goes
to a `memory` action in `/system/logging` (this is the RouterOS default).

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
