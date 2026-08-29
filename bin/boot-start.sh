#!/bin/bash
# Started by launchd at login. The bind address comes from Tailscale, which is
# a per-user app that may still be connecting when this fires, so wait for the
# tunnel before handing off to make.
set -uo pipefail

repo="$1"
# launchd gives a minimal PATH. tmux lives in Homebrew, tailscale in /usr/local.
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

cd "$repo" || exit 1

if tmux has-session -t mc-server 2>/dev/null; then
	echo "$(date '+%F %T') already running, nothing to do"
	exit 0
fi

for i in $(seq 1 60); do
	state=$(tailscale status --json 2>/dev/null | sed -n 's/.*"BackendState": *"\([^"]*\)".*/\1/p' | head -1)
	[ "$state" = "Running" ] && break
	sleep 2
done

if [ "${state:-}" != "Running" ]; then
	echo "$(date '+%F %T') tailscale not up after 120s, not starting"
	exit 1
fi

echo "$(date '+%F %T') tailscale up, starting server"
exec make start
