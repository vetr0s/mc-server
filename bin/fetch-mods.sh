#!/bin/bash
# Resolve Modrinth slugs to jars for MC_VERSION and sync them into a directory.
# Stale jars are deleted, so the directory always matches the list exactly.
set -uo pipefail

list="$1"
dest="$2"
: "${MC_VERSION:?MC_VERSION not set}"

mkdir -p "$dest"
keep=""
missing=""

while read -r slug; do
	case "$slug" in ''|\#*) continue ;; esac

	resolved=$(curl -sf -G "https://api.modrinth.com/v2/project/$slug/version" \
		--data-urlencode "game_versions=[\"$MC_VERSION\"]" \
		--data-urlencode 'loaders=["fabric"]' \
		| jq -r 'sort_by(.date_published) | reverse
		         | map(.files[] | select(.primary))
		         | if length == 0 then empty else .[0] | "\(.filename)\t\(.url)" end')

	if [ -z "$resolved" ]; then
		missing="$missing $slug"
		continue
	fi

	filename=${resolved%%$'\t'*}
	url=${resolved#*$'\t'}
	keep="$keep$filename"$'\n'

	if [ -f "$dest/$filename" ]; then
		printf '  have %s\n' "$filename"
	else
		printf '  get  %s\n' "$filename"
		curl -sfL -o "$dest/$filename" "$url" || { echo "download failed: $slug" >&2; exit 1; }
	fi
done < "$list"

for jar in "$dest"/*.jar; do
	[ -e "$jar" ] || continue
	base=$(basename "$jar")
	printf '%s\n' "$keep" | grep -qxF "$base" || { printf '  drop %s\n' "$base"; rm -f "$jar"; }
done

if [ -n "$missing" ]; then
	echo >&2
	echo "No $MC_VERSION build published for:$missing" >&2
	echo "Remove it from $list or pin MC_VERSION to a release it supports." >&2
	exit 1
fi
