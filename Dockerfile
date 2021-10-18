ARG           FROM_REGISTRY=ghcr.io/dubo-dubon-duponey

ARG           FROM_IMAGE_BUILDER=base:builder-bullseye-2021-10-15@sha256:33e021267790132e63be2cea08e77d64ec5d0434355734e94f8ff2d90c6f8944
ARG           FROM_IMAGE_AUDITOR=base:auditor-bullseye-2021-10-15@sha256:eb822683575d68ccbdf62b092e1715c676b9650a695d8c0235db4ed5de3e8534
ARG           FROM_IMAGE_TOOLS=tools:linux-bullseye-2021-10-15@sha256:e8ec2d1d185177605736ba594027f27334e68d7984bbfe708a0b37f4b6f2dbd7
ARG           FROM_IMAGE_RUNTIME=base:runtime-bullseye-2021-10-15@sha256:7072702dab130c1bbff5e5c4a0adac9c9f2ef59614f24e7ee43d8730fae2764c

FROM          $FROM_REGISTRY/$FROM_IMAGE_TOOLS                                                                          AS builder-tools

#######################
# Builder assembly
#######################
FROM          --platform=$BUILDPLATFORM $FROM_REGISTRY/$FROM_IMAGE_AUDITOR                                              AS assembly

ARG           TARGETARCH

RUN           mkdir -p /dist/boot/bin

COPY          --from=builder-tools  /boot/bin/caddy           /dist/boot/bin
COPY          --from=builder-tools  /boot/bin/goello-server-ng   /dist/boot/bin
COPY          --from=builder-tools  /boot/bin/http-health     /dist/boot/bin

RUN           setcap 'cap_net_bind_service+ep'                /dist/boot/bin/caddy

RUN           RUNNING=true \
              RO_RELOCATIONS=true \
              STATIC=true \
                dubo-check validate /dist/boot/bin/caddy

RUN           RUNNING=true \
              STATIC=true \
                dubo-check validate /dist/boot/bin/goello-server-ng; \
                dubo-check validate /dist/boot/bin/http-health

RUN           chmod 555 /dist/boot/bin/*; \
              epoch="$(date --date "$BUILD_CREATED" +%s)"; \
              find /dist/boot -newermt "@$epoch" -exec touch --no-dereference --date="@$epoch" '{}' +;

#######################
# Running image
#######################
FROM          $FROM_REGISTRY/$FROM_IMAGE_RUNTIME

ARG           TARGETPLATFORM

# Env so that it's available at runtime
ENV           PLEX_VERSION=1.24.4.5081-e362dc1ee

WORKDIR       /boot/bin

USER          root

# Custom package in
COPY          "./cache/$PLEX_VERSION/$TARGETPLATFORM/plex.deb" /tmp
RUN           dpkg -i --force-confold /tmp/plex.deb

# All of this is required solely by the init script
RUN           --mount=type=secret,uid=100,id=CA \
              --mount=type=secret,uid=100,id=CERTIFICATE \
              --mount=type=secret,uid=100,id=KEY \
              --mount=type=secret,uid=100,id=GPG.gpg \
              --mount=type=secret,id=NETRC \
              --mount=type=secret,id=APT_SOURCES \
              --mount=type=secret,id=APT_CONFIG \
              apt-get update -qq && \
              apt-get install -qq --no-install-recommends \
                curl=7.74.0-1.3+b1 \
                xmlstarlet=1.6.1-2.1 \
                uuid-runtime=2.36.1-8 \
                dnsutils=1:9.16.15-1 \
              && apt-get -qq autoremove       \
              && apt-get -qq clean            \
              && rm -rf /var/lib/apt/lists/*  \
              && rm -rf /tmp/*                \
              && rm -rf /var/tmp/*

USER          dubo-dubon-duponey

# Change home directory for plex
# RUN         usermod -d /config plex

# Environment
ENV           DBDB_LOGIN=""
ENV           DBDB_PASSWORD=""
ENV           DBDB_MAIL=""
ENV           DBDB_ADVERTISE_IP=""
ENV           DBDB_ADVERTISE_PORT=""
ENV           DBDB_ADVERTISE_DOMAIN=""
ENV           DBDB_SERVER_NAME=""

# Ports
#EXPOSE      32400/tcp
# Unexposed, because we don't need them
# 3005/tcp 8324/tcp 32469/tcp 1900/udp 32410/udp 32412/udp 32413/udp 32414/udp
# Volumes we need

ENV           NICK="plex"

COPY          --from=assembly --chown=$BUILD_UID:root /dist /

### Front server configuration
# Port to use
ENV           PORT_HTTPS=443
ENV           PORT_HTTP=80
EXPOSE        443
EXPOSE        80
# Log verbosity for
ENV           LOG_LEVEL="warn"
# Domain name to serve
ENV           DOMAIN="$NICK.local"
ENV           ADDITIONAL_DOMAINS="https://*.debian.org"
# Whether the server should behave as a proxy (disallows mTLS)
ENV           SERVER_NAME="DuboDubonDuponey/1.0 (Caddy/2) [$NICK]"
# Control wether tls is going to be "internal" (eg: self-signed), or alternatively an email address to enable letsencrypt - use "" to disable TLS entirely
ENV           TLS="internal"
# 1.2 or 1.3
ENV           TLS_MIN=1.3
# Issuer name to appear in certificates
#ENV           TLS_ISSUER="Dubo Dubon Duponey"
# Either disable_redirects or ignore_loaded_certs if one wants the redirects
ENV           TLS_AUTO=disable_redirects
# Either require_and_verify or verify_if_given, or "" to disable mTLS altogether
ENV           MTLS="require_and_verify"
# Root certificate to trust for mTLS
ENV           MTLS_TRUST="/certs/mtls_ca.crt"
# Realm for authentication - set to "" to disable authentication entirely
ENV           AUTH="My Precious Realm"
# Provide username and password here (call the container with the "hash" command to generate a properly encrypted password, otherwise, a random one will be generated)
ENV           AUTH_USERNAME="dubo-dubon-duponey"
ENV           AUTH_PASSWORD="cmVwbGFjZV9tZV93aXRoX3NvbWV0aGluZwo="
### mDNS broadcasting
# Type to advertise
ENV           MDNS_TYPE="_http._tcp"
# Name is used as a short description for the service
ENV           MDNS_NAME="$NICK mDNS display name"
# The service will be annonced and reachable at $MDNS_HOST.local (set to empty string to disable mDNS announces entirely)
ENV           MDNS_HOST="$NICK"
# Also announce the service as a workstation (for example for the benefit of coreDNS mDNS)
ENV           MDNS_STATION=true
# Caddy certs will be stored here
VOLUME        /certs
# Caddy uses this
VOLUME        /tmp
# Used by the backend service
VOLUME        /data
ENV           HEALTHCHECK_URL="http://127.0.0.1:10000/?healthcheck"

HEALTHCHECK   --interval=120s --timeout=30s --start-period=10s --retries=1 CMD http-health || exit 1
