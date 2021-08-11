ARG           FROM_REGISTRY=ghcr.io/dubo-dubon-duponey

ARG           FROM_IMAGE_BUILDER=base:builder-bullseye-2021-08-01@sha256:f492d8441ddd82cad64889d44fa67cdf3f058ca44ab896de436575045a59604c
ARG           FROM_IMAGE_AUDITOR=base:auditor-bullseye-2021-08-01@sha256:0f9017945c84b48c5e9906f3325409ab446964a9e97c65a1e1820f2dd3ff1b2c
ARG           FROM_IMAGE_TOOLS=tools:linux-bullseye-2021-08-01@sha256:cec37383d167e274e3140f2b5db8cb80d0fb406538372f0c23ba09d97ee0b2a3
ARG           FROM_IMAGE_RUNTIME=base:runtime-bullseye-2021-08-01@sha256:edc80b2c8fd94647f793cbcb7125c87e8db2424f16b9fd0b8e173af850932b48

FROM          $FROM_REGISTRY/$FROM_IMAGE_TOOLS                                                                          AS builder-tools

#######################
# Builder assembly
#######################
FROM          --platform=$BUILDPLATFORM $FROM_REGISTRY/$FROM_IMAGE_AUDITOR                                              AS builder

RUN           mkdir -p /dist/boot/bin

COPY          --from=builder-tools  /boot/bin/caddy          /dist/boot/bin
COPY          --from=builder-tools  /boot/bin/goello-server  /dist/boot/bin
COPY          --from=builder-tools  /boot/bin/http-health    /dist/boot/bin

RUN           setcap 'cap_net_bind_service+ep' /dist/boot/bin/caddy

RUN           chmod 555 /dist/boot/bin/*; \
              epoch="$(date --date "$BUILD_CREATED" +%s)"; \
              find /dist/boot -newermt "@$epoch" -exec touch --no-dereference --date="@$epoch" '{}' +;

#######################
# Running image
#######################
FROM          $FROM_REGISTRY/$FROM_IMAGE_RUNTIME

WORKDIR       /boot/bin
ARG           PLEX_VERSION=1.23.6.4881-e2e58f321

ARG           TARGETPLATFORM

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

COPY          --from=builder --chown=$BUILD_UID:root /dist /

### Front server configuration
# Port to use
ENV           PORT=4443
ENV           PORT_HTTP=80
EXPOSE        4443
EXPOSE        80
# Log verbosity for
ENV           LOG_LEVEL="warn"
# Domain name to serve
ENV           DOMAIN="$NICK.local"
ENV           ADDITIONAL_DOMAINS=""

# Whether the server should behave as a proxy (disallows mTLS)
ENV           SERVER_NAME="DuboDubonDuponey/1.0 (Caddy/2) [$NICK]"

# Control wether tls is going to be "internal" (eg: self-signed), or alternatively an email address to enable letsencrypt
ENV           TLS="internal"
# 1.2 or 1.3
ENV           TLS_MIN=1.2
# Either require_and_verify or verify_if_given
ENV           TLS_MTLS_MODE="verify_if_given"
# Issuer name to appear in certificates
#ENV           TLS_ISSUER="Dubo Dubon Duponey"
# Either disable_redirects or ignore_loaded_certs if one wants the redirects
ENV           TLS_AUTO=disable_redirects

ENV           AUTH_ENABLED=false
# Realm in case access is authenticated
ENV           AUTH_REALM="My Precious Realm"
# Provide username and password here (call the container with the "hash" command to generate a properly encrypted password, otherwise, a random one will be generated)
ENV           AUTH_USERNAME="dubo-dubon-duponey"
ENV           AUTH_PASSWORD="cmVwbGFjZV9tZV93aXRoX3NvbWV0aGluZwo="

### mDNS broadcasting
# Enable/disable mDNS support
ENV           MDNS_ENABLED=false
# Name is used as a short description for the service
ENV           MDNS_NAME="$NICK mDNS display name"
# The service will be annonced and reachable at $MDNS_HOST.local
ENV           MDNS_HOST="$NICK"
# Type to advertise
ENV           MDNS_TYPE="_http._tcp"

# Caddy certs will be stored here
VOLUME        /certs

# Caddy uses this
VOLUME        /tmp

# Used by the backend service
VOLUME        /data

ENV           HEALTHCHECK_URL="http://127.0.0.1:10000/?healthcheck"

HEALTHCHECK   --interval=120s --timeout=30s --start-period=10s --retries=1 CMD http-health || exit 1
