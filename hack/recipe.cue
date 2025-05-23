package cake

import (
	"duponey.cloud/scullery"
	"duponey.cloud/buildkit/types"
)


cakes: {
  image: scullery.#Cake & {
		recipe: {
			input: {
				from: {
					registry: * "docker.io/dubodubonduponey" | string
				}
			}

			process: {
				platforms: [
					types.#Platforms.#AMD64,
					types.#Platforms.#ARM64,
					// types.#Platforms.#V7,
					// tired of building that useless shite
					// types.#Platforms.#I386,
				]
			}

			output: {
				images: {
					names: [...string] | * ["plex"],
					tags: [...string] | * ["latest"]
				}
			}

			metadata: {
				title: string | * "Dubo Plex",
				description: string | * "A dubo image for Plex",
			}
		}
  }
}

injectors: {
	suite: * "bookworm" | =~ "^(?:bullseye|bookworm|trixie|sid)$" @tag(suite, type=string)
	date: * "2025-05-01" | =~ "^[0-9]{4}-[0-9]{2}-[0-9]{2}$" @tag(date, type=string)
	platforms: string @tag(platforms, type=string)
	registry: * "registry.local" | string @tag(registry, type=string)
}

cakes: image: recipe: {
	input: from: registry: injectors.registry

	output: images: tags: [injectors.suite + "-" + injectors.date, injectors.suite + "-latest", "latest"]
	metadata: ref_name: injectors.suite + "-" + injectors.date
}

// Allow hooking-in a UserDefined environment as icing
UserDefined: scullery.#Icing

cakes: image: icing: UserDefined
