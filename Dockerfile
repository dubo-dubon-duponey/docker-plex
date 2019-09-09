##########################
# Building image
##########################
FROM        debian:buster-slim                                                                            AS builder

LABEL       dockerfile.copyright="Dubo Dubon Duponey <dubo-dubon-duponey@jsboot.space>"

# Install dependencies and tools
ARG         DEBIAN_FRONTEND="noninteractive"
ENV         TERM="xterm" LANG="C.UTF-8" LC_ALL="C.UTF-8"
RUN         apt-get update              > /dev/null && \
            apt-get dist-upgrade -y                 && \
            apt-get install -y tzdata curl xmlstarlet uuid-runtime                                        > /dev/null

WORKDIR     /build

ARG         VERSION=1.16.2.1321-ad17d5f9e
# v1.22.1.0 = b18125de1e53927af65e249d12c4cd71849c4122
ARG         S6_OVERLAY_VERSION=v1.22.1.0
ARG         TARGETPLATFORM

RUN \
# Update and get dependencies
    apt-get update && \
# Cleanup
    apt-get -y autoremove && \
    apt-get -y clean && \
    rm -rf /var/lib/apt/lists/* && \
    rm -rf /tmp/* && \
    rm -rf /var/tmp/*

RUN suffix=amd64 && { [ "$TARGETPLATFORM" != "arm64" ] || suffix=aarch64 } && { [ "$TARGETPLATFORM" != "arm/v7" ] || suffix=armhf } && \
    curl -J -L -o /tmp/s6-overlay-amd64.tar.gz https://github.com/just-containers/s6-overlay/releases/download/${S6_OVERLAY_VERSION}/s6-overlay-${suffix}.tar.gz && \
    tar xzf /tmp/s6-overlay-${suffix}.tar.gz -C / && \

# Add user
    useradd -U -d /config -s /bin/false plex && \
    usermod -G users plex && \

# Setup directories
    mkdir -p \
      /config \
      /transcode \
      /data \


ENV CHANGE_CONFIG_DIR_OWNERSHIP="true"
ENV HOME="/config"

COPY root/ /

# Get the deb for that platform and install it
COPY "./cache/$VERSION/$TARGETPLATFORM/plex.deb" /tmp
RUN dpkg -i --force-confold /tmp/plex.deb

# Declare healthcheck
HEALTHCHECK --interval=5s --timeout=2s --retries=20 \
  CMD curl --connect-timeout 15 --silent --show-error --fail "http://localhost:32400/identity" >/dev/null || exit 1

# Volumes we need
VOLUME /config
VOLUME /transcode
VOLUME /data
# VOLUME /certs

# Ports
EXPOSE 32400/tcp
# Unexposed, because we don't need them
# 3005/tcp 8324/tcp 32469/tcp 1900/udp 32410/udp 32412/udp 32413/udp 32414/udp

ENTRYPOINT ["/init"]
