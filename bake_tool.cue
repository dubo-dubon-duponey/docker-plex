package bake

command: {
  image: #Dubo & {
    args: {
      BUILD_TITLE: "Plex"
      BUILD_DESCRIPTION: "A dubo image for Plex based on \(args.DEBOOTSTRAP_SUITE) (\(args.DEBOOTSTRAP_DATE))"
    }

    platforms: [
      AMD64,
      ARM64,
      V7,
    ]
  }
}
