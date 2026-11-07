# Minimal TrustTunnel client image for MikroTik RouterOS containers.
# The upstream binaries are static & stripped, so the runtime base is just
# busybox (sh, ip, sed, ...) + the CA bundle.
#
# Release tarballs are fetched on the host into dist/ (see build.sh).

FROM --platform=$BUILDPLATFORM alpine:3.22 AS fetch
ARG TARGETARCH
ARG TARGETVARIANT
RUN apk add --no-cache ca-certificates
COPY dist/ /dist/
RUN case "${TARGETARCH}${TARGETVARIANT}" in \
      arm64)  A=aarch64 ;; \
      armv7)  A=armv7 ;; \
      *) echo "unsupported arch ${TARGETARCH}${TARGETVARIANT}"; exit 1 ;; \
    esac \
 && mkdir /out /x && tar -xzf /dist/tt-$A.tgz -C /x \
 && cp /x/trusttunnel_client-*/trusttunnel_client /x/trusttunnel_client-*/setup_wizard /out/ \
 && chmod 755 /out/*

FROM busybox:1.37-musl
ARG VERSION
LABEL org.opencontainers.image.title="trusttunnel-client-mikrotik" \
      org.opencontainers.image.description="Minimal TrustTunnel Client for MikroTik RouterOS containers (arm64/armv7); logs to stdout only" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.source="https://github.com/TrustTunnel/TrustTunnelClient"

COPY --from=fetch /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt
COPY --from=fetch /out/ /opt/trusttunnel/
COPY --chmod=755 entrypoint.sh /entrypoint.sh
WORKDIR /opt/trusttunnel

ENTRYPOINT ["/entrypoint.sh"]
