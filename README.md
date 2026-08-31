# mc-server

A Fabric Minecraft server that listens only on a Tailscale tailnet. The server
binds to the machine's Tailscale IPv4 address instead of `0.0.0.0`. There is no
public port to forward.

This repo manages the server, mods, backups, and a macOS LaunchAgent. Runtime
files and worlds stay out of git.

## Requirements

- macOS
- Java 25
- Tailscale
- tmux
- `jq`, `curl`, and `make`

Set the Minecraft and Fabric versions in `config.mk`. Minecraft 26.2 requires
Java 25.

## Setup

Connect the host to Tailscale first. Then fetch the server and client mods:

```sh
make mods
make client-mods
```

Players need the same Minecraft version and the jars produced under
`client/mods/`. Give them the host's Tailscale address and server port.

The server does not listen on loopback. `localhost` will not work unless you
change the bind setting.

## Running it

```sh
make start                     # start in a detached tmux session
make console                   # attach; press ctrl-b d to detach
make stop                      # save the world and stop
make logs                      # follow server/logs/latest.log
make status                    # show address, listener, session, and sleep state
make backup                    # snapshot the world while the server is running
make regen-world SEED=<seed>   # back up, replace, and reseed the world
```

Run `make` to list every target.

Always stop the server with `make stop`. It waits for the world save to finish.
Killing Java or the tmux session can lose unwritten state.

## Configuration

Edit `config.mk` for versions, heap size, port, and bind behavior. Edit
`server-settings.properties` for Minecraft settings. Each start merges that
file into the generated `server/server.properties`.

Mods are listed by Modrinth slug in `mods.txt` and `client-mods.txt`. The fetcher
resolves compatible jars for the configured Minecraft version and removes jars
that are no longer listed.

## Backups and world replacement

`make backup` writes a dated world archive under `backups/` and keeps the last
10. The command pauses writes while it creates the archive, so it is safe to run
with players online.

Backups are manual and stay on the same disk as the server. Copy them elsewhere
if they need to survive a disk failure.

`make regen-world SEED=<seed>` refuses to run while the server is active. It
backs up the current world before replacing it. The seed is written to the
gitignored runtime properties file.

## Starting at login

```sh
make install-service
make uninstall-service
```

The service is a LaunchAgent. It runs after login because the macOS Tailscale
app belongs to the logged-in user. The agent waits up to two minutes for
Tailscale to report `Running`. It exits without starting Minecraft if the
tunnel never appears.

macOS normally sleeps when a laptop lid closes. `make status` reports the sleep
setting, but this repo does not change it automatically.

## Layout

```text
config.mk                   versions, memory, address, and port
mods.txt                    server-side Modrinth slugs
client-mods.txt             client-side Modrinth slugs
server-settings.properties  settings merged into the runtime file
bin/fetch-mods.sh           resolves slugs and removes stale jars
bin/inject-settings.sh      merges settings and forces the bind address
bin/backup.sh               creates a dated world archive
bin/boot-start.sh           waits for Tailscale, then starts the server
backups/                    world archives, gitignored
server/                     runtime and world, gitignored
client/mods/                client jars, gitignored
```
