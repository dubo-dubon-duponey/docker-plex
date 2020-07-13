variable "REGISTRY" {
  default = "docker.io"
}

target "default" {
  inherits = ["shared"]
  args = {
    BUILD_TITLE = "Plex"
    BUILD_DESCRIPTION = "A dubo image for Plex"
  }
  tags = [
    "${REGISTRY}/dubodubonduponey/plex",
  ]
  # No v6 with Plex
  platforms = [
    "linux/amd64",
    "linux/arm64",
    "linux/arm/v7",
  ]
}
