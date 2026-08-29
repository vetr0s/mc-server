#!/bin/bash
# Merge server-settings.properties into server/server.properties, then force
# the bind address. Keys absent from the settings file keep Minecraft's value.
set -euo pipefail

settings="$1"
target="$2"
: "${BIND_IP:?BIND_IP not set}" "${PORT:?PORT not set}"

touch "$target"

set_key() {
	awk -v k="$1" -v v="$2" -F= '
		$1 == k { print k "=" v; seen = 1; next }
		{ print }
		END { if (!seen) print k "=" v }
	' "$target" > "$target.tmp" && mv "$target.tmp" "$target"
}

while IFS= read -r line; do
	case "$line" in ''|\#*) continue ;; esac
	set_key "${line%%=*}" "${line#*=}"
done < "$settings"

set_key server-ip "$BIND_IP"
set_key server-port "$PORT"

printf 'bound to %s:%s\n' "$BIND_IP" "$PORT"
