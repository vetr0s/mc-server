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

Share the machine rather than adding the person to the tailnet. In the
[admin console](https://login.tailscale.com/admin/machines), open the `...`
menu on `hermes` and choose Share. They make their own free Tailscale account,
accept the share, and connect to `100.88.125.105:25565`.

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
    make status     # tailnet address, session, listener, sleep setting

`make` on its own lists every target.

Always stop with `make stop`. It waits for the save to finish. Killing the
tmux session or the java process directly loses whatever has not been written
to disk.

## Keeping it up with the lid closed

macOS sleeps on lid close, which drops every player. Disable it once:

    sudo pmset -a disablesleep 1

This survives reboots. `make status` reports whether it is set. Keep the
machine on power, because the setting stops the sleep and not the battery
drain.

The server does not start on boot. After a restart or a logout the tmux
session is gone and you run `make start` again. Set up a LaunchAgent if that
becomes annoying.

## Things that will bite you later

**Tailscale must be up before the server starts.** `make start` resolves the
bind address from `tailscale ip -4`. With Tailscale down there is no address,
and preflight fails instead of falling back to a public bind. This is
deliberate. Start Tailscale, then start the server.

**Backups do not exist.** `server/world` is gitignored and nothing copies it
anywhere. One bad command or one disk failure ends the world. Copy it
somewhere while the server is stopped.

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
