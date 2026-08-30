# mc-server

A Fabric Minecraft server that listens only on a Tailscale tailnet.

Minecraft 26.2, Fabric loader 0.19.3. The server binds to the machine's
tailnet address instead of `0.0.0.0`, so there is no port to forward and
nothing reachable from the open internet. Access is controlled by who is on
the tailnet, not by a whitelist or a password.

## Connecting

The server runs on `hermes` and listens on `100.88.125.105:25565`.

Both addresses work from any device on the tailnet:

    100.88.125.105:25565
    hermes.tailac0752.ts.net:25565

Use the tailnet address even when playing on `hermes` itself. `localhost` will
not connect, because the server is not bound to the loopback interface.

Players need the client mods in `client/mods`. Run `make client-mods` to
download the current set, then copy the jars into the player's
`.minecraft/mods` directory. Client and server must run the same Minecraft
version or the client is rejected at login.

## Adding a player

Share the machine with them. Do not invite them into the tailnet as a user.
Sharing is a separate mechanism and it gives them one device instead of all
of them.

They need their own Tailscale account, which is free and can use a different
login provider than yours.

1. They install Tailscale on the machine they will play on and sign in.
2. Open the [admin console](https://login.tailscale.com/admin/machines).
3. Find `hermes`, open the `...` menu, choose Share.
4. Enter their email, or copy the share link and send it.
5. They open the link and accept. `hermes` appears in their Tailscale client.
6. They add a Minecraft server pointing at `100.88.125.105:25565`.

Give them the IP and not the MagicDNS name. Shared nodes resolve differently
depending on the other tailnet's DNS settings, and the IP always works.

They also need the jars from `client/mods` and Minecraft 26.2. A version
mismatch is rejected at login.

Sharing works per device, not per port, so by default a shared user reaches
every port on `hermes`. To limit them to the game, replace the default
allow-all rule in Access Controls:

```json
{
  "acls": [
    {"action": "accept", "src": ["autogroup:member"], "dst": ["*:*"]},
    {"action": "accept", "src": ["their@email.com"], "dst": ["hermes:25565"]}
  ]
}
```

## Running it

    make start      # detached in tmux
    make console    # attach to the console, ctrl-b d to detach
    make stop       # sends 'stop' and waits for the world to save
    make logs       # tail server/logs/latest.log
    make backup     # snapshot the world, safe while players are online
    make regen-world SEED=<seed>   # back up, wipe, and reseed the world

    make install-service   # start automatically at login
    make status     # tailnet address, session, listener, sleep setting

`make` on its own lists every target.

Always stop with `make stop`. It waits for the save to finish. Killing the
tmux session or the java process directly loses whatever has not been written
to disk.

## Changing the seed

    make regen-world SEED=<seed>

This backs up the current world with `make backup`, deletes `server/world`,
and writes `level-seed` into `server/server.properties`. The next `make start`
generates the new world. It refuses while the server is running, because
deleting the world under a live server corrupts the save.

The old world stays in `backups/` as a dated tarball. Nothing else is touched,
so the mods, settings, and service install carry over unchanged.

The seed lands in `server/server.properties`, which is gitignored, so it is
not recorded in the repo. Note it down if you want to regenerate the same
world later.

## Keeping it up with the lid closed

macOS sleeps on lid close, which drops every player. Disable it once:

    sudo pmset -a disablesleep 1

This survives reboots. `make status` reports whether it is set. Keep the
machine on power, because the setting stops the sleep and not the battery
drain.

To start the server automatically, install the LaunchAgent once:

    make install-service     # start at login
    make uninstall-service   # stop doing that

This is a LaunchAgent and not a LaunchDaemon, so it runs at login rather than
at boot. That is deliberate. The Tailscale app on macOS is per-user, so before
someone logs in there is no tunnel and no address to bind to. The agent waits
up to two minutes for Tailscale to report Running, then hands off to
`make start`. If the tunnel never comes up it gives up instead of starting a
server that cannot bind. It also does nothing when the server is already
running, so it is safe to trigger twice.

Its output goes to `server/logs/launchd.log`, which is where to look if the
server is missing after a reboot.

## Things that will bite you later

**Tailscale must be up before the server starts.** `make start` resolves the
bind address from `tailscale ip -4`. With Tailscale down there is no address,
and preflight fails instead of falling back to a public bind. This is
deliberate. Start Tailscale, then start the server.

**Backups are manual.** `make backup` writes a dated tarball to `backups/`
and keeps the last 10. Nothing runs it on a schedule, so it only happens when
you type it. Add a cron entry or a LaunchAgent if you want it automatic.
`backups/` is gitignored and sits on the same disk as the world, so copy the
tarballs somewhere else to survive a disk failure.

**Bumping the Minecraft version breaks mods.** Change `MC_VERSION` in
`config.mk` and run `make mods`. Every slug in `mods.txt` is resolved against
that version at fetch time, so no CDN links need editing. Mods lag a new
Minecraft release by days or weeks, and `make mods` exits non-zero naming any
that have no build yet. Wait, or drop the mod.

**FerriteCore is not installed.** It had no 26.2 build when this was set up.
Add `ferritecore` back to `mods.txt` once one exists.

**Sodium for 26.2 is an alpha.** It is the only published build. Expect
rendering bugs on the client.

**RCON is off.** Minecraft silently disables RCON when `rcon.password` is
empty and only mentions it in a startup warning. Set a password in
`server-settings.properties` before turning it on for a Discord bot.

**Relayed connections are slower than direct ones.** `tailscale ping hermes`
from the other machine says which one you get. Tailscale always prefers a
direct connection and falls back to DERP when hole punching fails, so there is
no flag that forces direct. You remove whatever blocks it instead. Check, in
order: the macOS firewall is not blocking the Tailscale system extension,
`tailscale netcheck` on the other machine reports `UDP: true` and
`MappingVariesByDestIP: false`, and the router has UPnP or NAT-PMP on so
`PortMapping` is not empty. A relayed link still works and is playable.

**If a player cannot connect**, check `make status` first for the listener.
If the server is listening and they still fail, allow Java through the
firewall:

    sudo /usr/libexec/ApplicationFirewall/socketfilterfw --add /usr/bin/java

## Layout

    config.mk                   versions, heap size, bind address, port
    mods.txt                    server mods, one Modrinth slug per line
    client-mods.txt             client mods, same format
    server-settings.properties  merged into server.properties on every run
    bin/fetch-mods.sh           resolves slugs to jars, deletes stale ones
    bin/inject-settings.sh      merges settings, forces the bind address
    bin/backup.sh               dated world snapshot, holds writes during tar
    bin/boot-start.sh           waits for Tailscale, then starts, run by launchd
    backups/                    world tarballs, gitignored
    server/                     runtime, gitignored
    client/mods/                jars to hand to players, gitignored

Edit `server-settings.properties` rather than `server/server.properties`.
Every run overwrites the keys listed there. Keys not listed keep whatever
Minecraft generated.

Mods are named by Modrinth slug and resolved to a jar at fetch time. The
fetcher deletes jars that are no longer in the list, because a leftover copy
of an older build crashes Fabric at load.

## Requirements

Java 25, Tailscale, tmux, and the `jq`, `curl`, and `make` that ship with
macOS. There is no Python and nothing to install with pip.

Minecraft 26.2 asks for Java 25 specifically, not merely 21 or newer. This
machine has jdk-25 at `/Library/Java/JavaVirtualMachines/jdk-25.jdk`.
