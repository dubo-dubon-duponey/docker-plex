ARG           BUILDER_BASE=dubodubonduponey/base:builder
ARG           RUNTIME_BASE=dubodubonduponey/base:runtime

#######################
# Extra builder for healthchecker
#######################
# hadolint ignore=DL3006,DL3029
FROM          --platform=$BUILDPLATFORM $BUILDER_BASE                                                                   AS builder-healthcheck

ARG           GIT_REPO=github.com/dubo-dubon-duponey/healthcheckers
ARG           GIT_VERSION=51ebf8ca3d255e0c846307bf72740f731e6210c3
ARG           BUILD_TARGET=./cmd/http
ARG           BUILD_OUTPUT=http-health

WORKDIR       $GOPATH/src/$GIT_REPO
RUN           git clone git://$GIT_REPO .
RUN           git checkout $GIT_VERSION
# hadolint ignore=DL4006
RUN           env GOOS=linux GOARCH="$(printf "%s" "$TARGETPLATFORM" | sed -E 's/^[^/]+\/([^/]+).*/\1/')" go build -v -ldflags "-s -w" \
                -o /dist/boot/bin/"$BUILD_OUTPUT" "$BUILD_TARGET"

#######################
# Running image
#######################
# hadolint ignore=DL3006
FROM          $RUNTIME_BASE

WORKDIR       /boot/bin
ARG           PLEX_VERSION=1.20.5.3600-47c0d9038
# XXX verify why this is not set by the base image
ARG           TARGETPLATFORM

USER          root

# Custom package in
COPY          "./cache/$PLEX_VERSION/$TARGETPLATFORM/plex.deb" /tmp
RUN           dpkg -i --force-confold /tmp/plex.deb

# All of this is required solely by the init script
RUN           apt-get update -qq \
              && apt-get install -qq --no-install-recommends \
                curl=7.64.0-4+deb10u1 \
                xmlstarlet=1.6.1-2 \
                uuid-runtime=2.33.1-0.1   \
                dnsutils=1:9.11.5.P4+dfsg-5.1+deb10u2 \
              && apt-get -qq autoremove       \
              && apt-get -qq clean            \
              && rm -rf /var/lib/apt/lists/*  \
              && rm -rf /tmp/*                \
              && rm -rf /var/tmp/*

USER          dubo-dubon-duponey

# Change home directory for plex
# RUN         usermod -d /config plex

# COPY        entrypoint.sh .

# Environment
ENV DBDB_LOGIN=""
ENV DBDB_PASSWORD=""
ENV DBDB_MAIL=""
ENV DBDB_ADVERTISE_IP=""
ENV DBDB_ADVERTISE_PORT=""
ENV DBDB_ADVERTISE_DOMAIN=""
ENV DBDB_SERVER_NAME=""

# Ports
EXPOSE      32400/tcp
# Unexposed, because we don't need them
# 3005/tcp 8324/tcp 32469/tcp 1900/udp 32410/udp 32412/udp 32413/udp 32414/udp

# Volumes we need
VOLUME      /transcode
VOLUME      /data
# VOLUME      /certs

# Declare healthcheck
HEALTHCHECK --interval=5s --timeout=2s --retries=20 \
  CMD curl --connect-timeout 15 --silent --show-error --fail "http://localhost:32400/identity" >/dev/null || exit 1
