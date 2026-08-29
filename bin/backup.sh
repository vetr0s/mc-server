#!/bin/bash
# Snapshot the world to a dated tarball. If the server is running, flush and
# hold writes for the duration, otherwise the archive can catch a half-written
# region file and restore to a corrupt world.
set -euo pipefail

server="$1"
dest="$2"
session="$3"
keep="${KEEP:-10}"

world="$server/world"
log="$server/logs/latest.log"
[ -d "$world" ] || { echo "no world at $world" >&2; exit 1; }
mkdir -p "$dest"

stamp=$(date +%Y%m%d-%H%M%S)
archive="$dest/world-$stamp.tar.gz"
live=0
tmux has-session -t "$session" 2>/dev/null && live=1

send() { tmux send-keys -t "$session" "$1" Enter; }

# Wait for a line to appear past the mark, so we do not match an older save.
wait_for() {
	local pattern=$1 mark=$2 i
	for i in $(seq 1 60); do
		[ "$(wc -l < "$log")" -gt "$mark" ] && \
			tail -n +"$((mark + 1))" "$log" | grep -q "$pattern" && return 0
		sleep 0.5
	done
	return 1
}

if [ "$live" = 1 ]; then
	mark=$(wc -l < "$log")
	# save-on must run even if the tar below dies, or the server never
	# writes to disk again until it is restarted.
	trap 'send "save-on"' EXIT
	send "save-off"
	send "save-all flush"
	wait_for "Saved the game" "$mark" || { echo "server did not confirm the save" >&2; exit 1; }
fi

tar -czf "$archive" -C "$server" world
[ "$live" = 1 ] && { trap - EXIT; send "save-on"; }

printf '%s  (%s)\n' "$archive" "$(du -h "$archive" | cut -f1)"

# Prune oldest first, keeping $keep.
count=$(ls -1 "$dest"/world-*.tar.gz 2>/dev/null | wc -l | tr -d ' ')
if [ "$count" -gt "$keep" ]; then
	ls -1 "$dest"/world-*.tar.gz | head -n "$((count - keep))" | while read -r old; do
		printf 'pruned %s\n' "$(basename "$old")"
		rm -f "$old"
	done
fi
