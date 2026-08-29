# Single source of truth for the server build. Every target reads from here.

MC_VERSION       := 26.2
FABRIC_LOADER    := 0.19.3
FABRIC_INSTALLER := 1.1.2

# Heap. This box has 16 GB; 6 GB leaves room for macOS and a client.
MEMORY := 6G

# The server listens only on the tailnet. Empty means "resolve from tailscale",
# which is what you want: the IP follows the node instead of being pinned here.
BIND_IP :=
PORT    := 25565
