#!/usr/bin/env bash
set -o errexit -o errtrace -o functrace -o nounset -o pipefail

info="$(curl --proto '=https' --tlsv1.2 -sSfL https://plex.tv/pms/downloads/5.json)"
version="$(printf "%s" "$info" | jq -rc .computer.Linux.version)"
cacheroot=context/cache/"$version"

geturl(){
  local url
  case "$1" in
    "linux/amd64")
      url="$(printf "%s" "$info" | jq -rc '.computer.Linux.releases[] | select( .build == "linux-x86_64") | select( .distro == "debian" ) | .url ')"
    ;;
    "linux/386")
      url="$(printf "%s" "$info" | jq -rc '.computer.Linux.releases[] | select( .build == "linux-x86") | select( .distro == "debian" ) | .url ')"
    ;;
    "linux/arm64")
      url="$(printf "%s" "$info" | jq -rc '.computer.Linux.releases[] | select( .build == "linux-aarch64") | select( .distro == "debian" ) | .url ')"
    ;;
    "linux/arm/v7")
      url="$(printf "%s" "$info" | jq -rc '.computer.Linux.releases[] | select( .build == "linux-armv7neon") | select( .distro == "debian" ) | .url ')"
    ;;
  esac
  echo "$url"
}

for platform in linux/amd64 linux/arm64 linux/arm/v7 linux/386; do
  mkdir -p "${cacheroot}/$platform"
  if ! curl --proto '=https' --tlsv1.2 -sSfL -o "${cacheroot}/$platform"/plex.deb "$(geturl "${platform}")"; then
    rm -f "${cacheroot}/$platform"/plex.deb
    printf >&2 "Failed to download bits!\n"
    exit 1
  fi
done
