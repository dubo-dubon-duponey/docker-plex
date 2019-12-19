#!/usr/bin/env bash
set -o errexit -o errtrace -o functrace -o nounset -o pipefail

export TITLE="Plex"
export DESCRIPTION="A dubo image for Plex"
export IMAGE_NAME="plex"
export PLATFORMS="${PLATFORMS:-linux/amd64,linux/arm64,linux/arm/v7}" # No v6

# shellcheck source=/dev/null
. "$(cd "$(dirname "${BASH_SOURCE[0]:-$PWD}")" 2>/dev/null 1>&2 && pwd)/helpers.sh"
