ARG           FROM_REGISTRY=docker.io/dubodubonduponey

ARG           FROM_IMAGE_BUILDER=base:builder-bookworm-2024-03-01
ARG           FROM_IMAGE_AUDITOR=base:auditor-bookworm-2024-03-01
ARG           FROM_IMAGE_TOOLS=tools:linux-bookworm-2024-03-01
ARG           FROM_IMAGE_RUNTIME=base:runtime-bookworm-2024-03-01

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
              STATIC=true \
                dubo-check validate /dist/boot/bin/http-health
RUN           RUNNING=true \
              STATIC=true \
                dubo-check validate /dist/boot/bin/goello-server-ng

RUN           RUNNING=true \
              RO_RELOCATIONS=true \
                dubo-check validate /dist/boot/bin/caddy

RUN           chmod 555 /dist/boot/bin/*; \
              epoch="$(date --date "$BUILD_CREATED" +%s)"; \
              find /dist/boot -newermt "@$epoch" -exec touch --no-dereference --date="@$epoch" '{}' +;

#######################
# Running image
#######################
FROM          $FROM_REGISTRY/$FROM_IMAGE_RUNTIME

ARG           TARGETPLATFORM

# Env so that it's available at runtime
ENV           PLEX_VERSION=1.40.1.8227-c0dd5a73e

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
                curl=7.88.1-10+deb12u5 \
                xmlstarlet=1.6.1-3 \
                uuid-runtime=2.38.1-5+b1 \
                dnsutils=1:9.18.24-1 \
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

ENV           _SERVICE_NICK="plex"
ENV           _SERVICE_TYPE="_http._tcp"

COPY          --from=assembly --chown=$BUILD_UID:root /dist /

#####
# Global
#####
# Log verbosity (debug, info, warn, error, fatal)
ENV           LOG_LEVEL="warn"
# Domain name to serve
ENV           DOMAIN="$_SERVICE_NICK.local"

#####
# Mod mDNS
#####
# Whether to disable mDNS broadcasting or not
ENV           MOD_MDNS_ENABLED=true
# Name is used as a short description for the service
ENV           MOD_MDNS_NAME="$_SERVICE_NICK display name"
# The service will be annonced and reachable at MOD_MDNS_HOST.local
ENV           MOD_MDNS_HOST="$_SERVICE_NICK"

#####
# Mod mTLS
#####
# Whether to enable client certificate validation or not (Caddy only for now - since ghost would use OPA instead)
ENV           MOD_MTLS_ENABLED=false
# Either require_and_verify or verify_if_given
ENV           MOD_MTLS_MODE="verify_if_given"

#####
# Mod Basic Auth
#####
# Whether to enable basic auth
ENV           MOD_BASICAUTH_ENABLED=false
# Realm displayed for auth
ENV           MOD_BASICAUTH_REALM="My Precious Realm"
# Provide username and password here (call the container with the "hash" command to generate a properly encrypted password, otherwise, a random one will be generated)
ENV           MOD_BASICAUTH_USERNAME="dubo-dubon-duponey"
ENV           MOD_BASICAUTH_PASSWORD="cmVwbGFjZV9tZV93aXRoX3NvbWV0aGluZwo="

#####
# Mod HTTP
#####
# Whether to disable the HTTP mod altogether
ENV           MOD_HTTP_ENABLED=true
# Control wether tls is going to be "internal" (eg: self-signed), or alternatively an email address to enable letsencrypt
ENV           MOD_HTTP_TLS_MODE="internal"

#####
# Advanced settings
#####
# Service type
ENV           ADVANCED_MOD_MDNS_TYPE="$_SERVICE_TYPE"
# Also announce the service as a workstation (for example for the benefit of coreDNS mDNS)
ENV           ADVANCED_MOD_MDNS_STATION=true
# Root certificate to trust for client cert verification
ENV           ADVANCED_MOD_MTLS_TRUST="/certs/pki/authorities/local/root.crt"
# Ports for http and https - recent changes in docker make it no longer necessary to have caps, plus we have our NET_BIND_SERVICE cap set anyhow - it's 2021, there is no reason to keep on venerating privileged ports
ENV           ADVANCED_MOD_HTTP_PORT=443
ENV           ADVANCED_MOD_HTTP_PORT_INSECURE=80
# By default, tls should be restricted to 1.3 - you may downgrade to 1.2+ for compatibility with older clients (webdav client on macos, older browsers)
ENV           ADVANCED_MOD_HTTP_TLS_MIN=1.3
# Name advertised by Caddy in the server http header
ENV           ADVANCED_MOD_HTTP_SERVER_NAME="DuboDubonDuponey/1.0 (Caddy/2)"
# ACME server to use (for testing)
# Staging
# https://acme-staging-v02.api.letsencrypt.org/directory
# Plain
# https://acme-v02.api.letsencrypt.org/directory
# PKI
# https://pki.local
ENV           ADVANCED_MOD_HTTP_TLS_SERVER="https://acme-v02.api.letsencrypt.org/directory"
# Either disable_redirects or ignore_loaded_certs if one wants the redirects
ENV           ADVANCED_MOD_HTTP_TLS_AUTO=disable_redirects
# Whether to disable TLS and serve only plain old http
ENV           ADVANCED_MOD_HTTP_TLS_ENABLED=true
# Additional domains aliases
ENV           ADVANCED_MOD_HTTP_ADDITIONAL_DOMAINS=""

#####
# Wrap-up
#####
EXPOSE        443
EXPOSE        80

# Caddy certs will be stored here
VOLUME        /certs
# Caddy uses this
VOLUME        /tmp
# Used by the backend service
VOLUME        /data

ENV           HEALTHCHECK_URL="http://127.0.0.1:10000/?healthcheck"

HEALTHCHECK   --interval=120s --timeout=30s --start-period=10s --retries=1 CMD http-health || exit 1
