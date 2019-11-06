#######################
# Extra builder for healthchecker
#######################
FROM          --platform=$BUILDPLATFORM dubodubonduponey/base:builder                                                   AS builder-healthcheck

ARG           HEALTH_VER=51ebf8ca3d255e0c846307bf72740f731e6210c3

WORKDIR       $GOPATH/src/github.com/dubo-dubon-duponey/healthcheckers
RUN           git clone git://github.com/dubo-dubon-duponey/healthcheckers .
RUN           git checkout $HEALTH_VER
RUN           arch="${TARGETPLATFORM#*/}"; \
              env GOOS=linux GOARCH="${arch%/*}" go build -v -ldflags "-s -w" -o /dist/bin/http-health ./cmd/http

RUN           chmod 555 /dist/bin/*

#######################
# Running image
#######################
FROM        debian:buster-slim

LABEL       dockerfile.copyright="Dubo Dubon Duponey <dubo-dubon-duponey@jsboot.space>"

ARG         DEBIAN_FRONTEND="noninteractive"
ENV         TERM="xterm" LANG="C.UTF-8" LC_ALL="C.UTF-8"
# XXX tzdata
RUN         apt-get update -qq && \
            apt-get install -qq --no-install-recommends \
              ca-certificates=20190110 \
              curl=7.64.0-4 \
              xmlstarlet=1.6.1-2 \
              uuid-runtime=2.33.1-0.1   && \
            apt-get -qq autoremove      && \
            apt-get -qq clean           && \
            rm -rf /var/lib/apt/lists/* && \
            rm -rf /tmp/*               && \
            rm -rf /var/tmp/*

WORKDIR     /dubo-dubon-duponey

# plex
ARG         PLEX_VERSION=1.16.5.1554-1e5ff713d

ARG         TARGETPLATFORM

COPY        "./cache/$PLEX_VERSION/$TARGETPLATFORM/plex.deb" /tmp
RUN         dpkg -i --force-confold /tmp/plex.deb

# Change home directory for plex
RUN         usermod -d /config plex

COPY        entrypoint.sh .

# Environment
ENV DBDB_LOGIN=""
ENV DBDB_PASSWORD=""
ENV DBDB_MAIL=""
ENV DBDB_ADVERTISE_IP=""
ENV DBDB_SERVER_NAME=""
ENV DBDB_UID=""
ENV DBDB_GID=""

# Ports
EXPOSE      32400/tcp
# Unexposed, because we don't need them
# 3005/tcp 8324/tcp 32469/tcp 1900/udp 32410/udp 32412/udp 32413/udp 32414/udp

# Volumes we need
VOLUME      /config
VOLUME      /transcode
VOLUME      /data
# VOLUME      /certs

# Declare healthcheck
HEALTHCHECK --interval=5s --timeout=2s --retries=20 \
  CMD curl --connect-timeout 15 --silent --show-error --fail "http://localhost:32400/identity" >/dev/null || exit 1

ENTRYPOINT  ["./entrypoint.sh"]
