#!/usr/bin/env bash
set -o errexit -o errtrace -o functrace -o nounset -o pipefail

[ -w /certs ] || {
  printf >&2 "/certs is not writable. Check your mount permissions.\n"
  exit 1
}

[ -w /tmp ] || {
  printf >&2 "/tmp is not writable. Check your mount permissions.\n"
  exit 1
}

[ -w /data ] || {
  printf >&2 "/data is not writable. Check your mount permissions.\n"
  exit 1
}

# Helpers
case "${1:-run}" in
  # Short hand helper to generate password hash
  "hash")
    shift
    printf >&2 "Generating password hash\n"
    caddy hash-password -algorithm bcrypt "$@"
    exit
  ;;
  # Helper to get the ca.crt out (once initialized)
  "cert")
    if [ "${TLS:-}" == "" ]; then
      printf >&2 "Your container is not configured for TLS termination - there is no local CA in that case."
      exit 1
    fi
    if [ "${TLS:-}" != "internal" ]; then
      printf >&2 "Your container uses letsencrypt - there is no local CA in that case."
      exit 1
    fi
    if [ ! -e /certs/pki/authorities/local/root.crt ]; then
      printf >&2 "No root certificate installed or generated. Run the container so that a cert is generated, or provide one at runtime."
      exit 1
    fi
    cat /certs/pki/authorities/local/root.crt
    exit
  ;;
  "run")
    # Bonjour the container if asked to. While the PORT is no guaranteed to be mapped on the host in bridge, this does not matter since mDNS will not work at all in bridge mode.
    if [ "${MDNS_ENABLED:-}" == true ]; then
      goello-server -json "$(printf '[{"Type": "%s", "Name": "%s", "Host": "%s", "Port": %s, "Text": {}}]' "$MDNS_TYPE" "$MDNS_NAME" "$MDNS_HOST" "$PORT")" &
    fi

    # If we want TLS and authentication, start caddy in the background
    if [ "${TLS:-}" ]; then
      HOME=/tmp/caddy-home caddy run -config /config/caddy/main.conf --adapter caddyfile &
    fi
  ;;
esac

# XXX cleanup plex/plexmediaserver.pid if there on start

# Environment
DBDB_LOGIN=${DBDB_LOGIN:-unknown}
DBDB_PASSWORD=${DBDB_PASSWORD:-}
DBDB_MAIL=${DBDB_MAIL:-unknown@unknown.com}
DBDB_SERVER_NAME=${DBDB_SERVER_NAME:-Some name}
# dig +short host-home.farcloser.world | grep -E "^[0-9.]+$"
# dig A +short powacroquette.synology.me
DBDB_ADVERTISE_IP=${DBDB_ADVERTISE_IP:-$(dig +short myip.opendns.com @resolver1.opendns.com || true)}
DBDB_ADVERTISE_DOMAIN=${DBDB_ADVERTISE_DOMAIN:-}
DBDB_ADVERTISE_PORT=${DBDB_ADVERTISE_PORT:-}

# Server conf
export PLEX_MEDIA_SERVER_APPLICATION_SUPPORT_DIR="/data/Library/Application Support"
export PLEX_MEDIA_SERVER_HOME=/usr/lib/plexmediaserver
export PLEX_MEDIA_SERVER_MAX_PLUGIN_PROCS=6
export PLEX_MEDIA_SERVER_MAX_STACK_SIZE=3000
export PLEX_MEDIA_SERVER_TMPDIR=/tmp
export PLEX_MEDIA_SERVER_USE_SYSLOG=false

# Info
export PLEX_MEDIA_SERVER_INFO_VENDOR=Docker
export PLEX_MEDIA_SERVER_INFO_DEVICE="Docker Container"
export PLEX_MEDIA_SERVER_INFO_MODEL
export PLEX_MEDIA_SERVER_INFO_PLATFORM_VERSION
PLEX_MEDIA_SERVER_INFO_MODEL="$(uname -m)"
PLEX_MEDIA_SERVER_INFO_PLATFORM_VERSION="$(uname -r)"

# XML attribute manipulation
dc::xml::get(){
  local key="$1"
  local root="${2:-/}"
  local file="${3:-/dev/stdin}"

  xmlstarlet sel -T -t -m "$root" -v "@${key}" -n "$file"
}

dc::xml::set(){
  local key="$1"
  local value="$2"
  local root="${3:-/}"
  local file="${4:-/dev/stdin}"

  local count

  count="$(xmlstarlet sel -t -v "count($root/@${key})" "$file")"
  count=$((count + 0))
  if [ "$count" -gt 0 ]; then
    xmlstarlet ed --inplace --update "$root/@$key" -v "$value" "$file"
  else
    xmlstarlet ed --inplace --insert "$root"  --type attr -n "$key" -v "$value" "$file"
  fi
}

# Preferences manipulation
plex::preferences::init(){
  local prefFile="${PLEX_MEDIA_SERVER_APPLICATION_SUPPORT_DIR}/Plex Media Server/Preferences.xml"
  [ -e "$prefFile" ] && return

  printf >&2 "Creating pref shell\n"

  mkdir -p "$PLEX_MEDIA_SERVER_APPLICATION_SUPPORT_DIR/Plex Media Server"
  printf '<?xml version="1.0" encoding="utf-8"?>\n<Preferences/>\n' > "${prefFile}"
#  cat > "${prefFile}" <<-EOF
#<?xml version="1.0" encoding="utf-8"?>
#<Preferences/>
#EOF
}

plex::preferences::read(){
  local prefFile="${PLEX_MEDIA_SERVER_APPLICATION_SUPPORT_DIR}/Plex Media Server/Preferences.xml"

  printf >&2 "Reading pref %s\n" "$1"

  dc::xml::get "$1" "Preferences" "$prefFile"
}

plex::preferences::write(){
  local prefFile="${PLEX_MEDIA_SERVER_APPLICATION_SUPPORT_DIR}/Plex Media Server/Preferences.xml"

  printf >&2 "Writing pref %s=%s\n" "$1" "$2"

  dc::xml::set "$1" "$2" "Preferences" "$prefFile"
}

plex::start(){
  printf >&2 "Starting Plex Media Server."
  rm -f "${PLEX_MEDIA_SERVER_APPLICATION_SUPPORT_DIR}/Plex Media Server/plexmediaserver.pid"
  # XXX LD_LIB is problematic with capabilities
  export LD_LIBRARY_PATH=/usr/lib/plexmediaserver:/usr/lib/plexmediaserver/lib
  exec /usr/lib/plexmediaserver/Plex\ Media\ Server "$@"
}

# If the first run completed successfully, start and go
if [ -e /data/.firstRun ]; then
  plex::start "$@"
  exit
fi

# Ensure we have a shell pref file
plex::preferences::init

# Setup Server's client identifier
serial="$(plex::preferences::read "MachineIdentifier")"
if [ ! "$serial" ]; then
  serial="$(uuidgen)"
  plex::preferences::write "MachineIdentifier" "$serial"
fi

clientId="$(plex::preferences::read "ProcessedMachineIdentifier")"
if [ ! "$clientId" ]; then
  clientId="$(printf "%s-Plex Media Server" "$serial" | sha1sum | cut -b 1-40)"
  plex::preferences::write "ProcessedMachineIdentifier" "$clientId"
fi

# Get server token and only turn claim token into server token if we have former but not latter.
token="$(plex::preferences::read "PlexOnlineToken")"

PLEX_CLAIM=
if [ ! "${token}" ] && [ "$DBDB_LOGIN" ] && [ "$DBDB_PASSWORD" ]; then
  authtoken="$(curl -s -X POST \
    --data-urlencode "login=$DBDB_LOGIN" \
    --data-urlencode "password=$DBDB_PASSWORD" \
    -H "Cookie: plex_tv_client_identifier=$clientId" \
    "https://plex.tv/api/v2/users/signin?X-Plex-Product=Plex%20Auth%20App&X-Plex-Version=3.24.0&X-Plex-Client-Identifier=$clientId&X-Plex-Platform=Chrome&X-Plex-Platform-Version=61.0&X-Plex-Device=OSX&X-Plex-Device-Name=Plex%20Web%20%28Chrome%29&X-Plex-Device-Screen-Resolution=1167x1057%2C1920x1200" \
    | grep -oP '(?<=authToken=")[^"]+')"

  PLEX_CLAIM=$(curl -s \
    -H "X-Plex-Client-Identifier: $clientId" \
    -H "X-Plex-Token: $authtoken" \
    https://plex.tv/api/claim/token.json | grep -oP "(?<=claim-)[^\"]+")
fi

# https://plex.tv/api/claim/subscribe?X-Plex-Product=Plex%20Web&X-Plex-Version=3.108.2&X-Plex-Client-Identifier=zgddlh84ron98pw0jw6stf1i&X-Plex-Platform=Chrome&X-Plex-Platform-Version=76.0&X-Plex-Sync-Version=2&X-Plex-Features=external-media&X-Plex-Model=bundled&X-Plex-Device=OSX&X-Plex-Device-Name=Chrome&X-Plex-Device-Screen-Resolution=1836x1299%2C3008x1692&X-Plex-Token=55vAuCc_1WyRumhj7xUu&X-Plex-Language=en

#if [ "$PLEX_CLAIM" ] && [ ! "$token" ]; then
#  printf >&2 "Attempting to obtain server token from claim token\n"
#  loginInfo="$(curl -X POST \
#        -H "X-Plex-Client-Identifier: $clientId" \
#        -H 'X-Plex-Product: Plex Media Server'\
#        -H 'X-Plex-Version: 1.1' \
#        -H 'X-Plex-Provides: server' \
#        -H 'X-Plex-Platform: Linux' \
#        -H 'X-Plex-Platform-Version: 1.0' \
#        -H 'X-Plex-Device-Name: PlexMediaServer' \
#        -H 'X-Plex-Device: Linux' \
#        "https://plex.tv/api/claim/exchange?token=${PLEX_CLAIM}")"
#  token="$(printf "%s" "$loginInfo" | sed -n 's/.*<authentication-token>\(.*\)<\/authentication-token>.*/\1/p')"
#
#  printf >&2 "Token obtained: %s\n" "$token"
#fi

[ ! "$PLEX_CLAIM" ]         || plex::preferences::write "PlexOnlineToken"   "$PLEX_CLAIM"
plex::preferences::write "AcceptedEULA"             1
plex::preferences::write "ManualPortMappingMode"    1
plex::preferences::write "ManualPortMappingPort"    443
plex::preferences::write "DlnaEnabled"              0
plex::preferences::write "PlexOnlineUsername"       "$DBDB_LOGIN"
plex::preferences::write "PlexOnlineMail"           "$DBDB_MAIL"
plex::preferences::write "FriendlyName"             "$DBDB_SERVER_NAME"

plex::preferences::write "PublishServerOnPlexOnlineKey" 1
plex::preferences::write "PlexOnlineHome"           1
plex::preferences::write "OldestPreviousVersion"    "legacy"
[ ! "$DBDB_ADVERTISE_DOMAIN" ] || plex::preferences::write "customCertificateDomain"  "$DBDB_ADVERTISE_DOMAIN"
[ ! "$DBDB_ADVERTISE_PORT" ] || plex::preferences::write "ManualPortMappingMode" "1"
[ ! "$DBDB_ADVERTISE_PORT" ] || plex::preferences::write "ManualPortMappingPort" "$DBDB_ADVERTISE_PORT"

[ ! "$DBDB_ADVERTISE_IP" ] || plex::preferences::write "customConnections" "$DBDB_ADVERTISE_IP"
plex::preferences::write "GdmEnabled"               0
plex::preferences::write "sendCrashReports"         0
plex::preferences::write "TranscoderTempDirectory" "/tmp/transcode"


touch /data/.firstRun
printf >&2 "Plex Media Server first run setup complete\n"

tail -F "$PLEX_MEDIA_SERVER_APPLICATION_SUPPORT_DIR/Plex Media Server/Logs/Plex Transcoder Statistics.log" &
# Not super satisfying... but then tail -F *.log is not going to cut it
for watch_this in \
  com.plexapp.agents.plexthememusic.log \
  com.plexapp.agents.imdb.log \
  com.plexapp.agents.thetvdb.log \
  com.plexapp.agents.fanarttv.log \
  com.plexapp.system.log \
  com.plexapp.agents.none.log \
  tv.plex.agents.music.log \
  com.plexapp.agents.lastfm.log \
  tv.plex.agents.movie.log \
  com.plexapp.agents.localmedia.log \
  com.plexapp.agents.movieposterdb.log \
  com.plexapp.agents.lyricfind.log \
  com.plexapp.agents.htbackdrops.log \
  tv.plex.agents.series.log \
  com.plexapp.agents.opensubtitles.log \
  com.plexapp.agents.themoviedb.log \
  org.musicbrainz.agents.music.log; do
  tail -F "$PLEX_MEDIA_SERVER_APPLICATION_SUPPORT_DIR/Plex Media Server/Logs/PMS Plugin Logs/$watch_this" &
done

plex::start "$@"

# As generated by a working server
# AnonymousMachineIdentifier="50d88b84-ecc9-4d50-a872-b7a2eea5859d"
# MetricsEpoch="1"
# LastAutomaticMappedPort="0"
# DvrIncrementalEpgLoader="0"
# CertificateUUID="ea2e0a83cc7a4d7491c88b580a2258a8"
# CertificateVersion="2"
# PubSubServer="184.105.148.82"
# PubSubServerRegion="sjc"
# PubSubServerPing="12"
# FSEventLibraryUpdatesEnabled="1"
# LanguageInCloud="1"/>

# XXX old notes
#  DlnaReportTimeline="0"
#  FSEventLibraryPartialScanEnabled="1"
#  ScannerLowPriority="1"
#  ScheduledLibraryUpdateInterval="900"
#	ScheduledLibraryUpdatesEnabled="1"
#  customCertificateKey=""
#	customCertificatePath="/certs/plex.pfx"/>
