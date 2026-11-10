#!/bin/sh
# Checks the upstream Garage release feed and, unless --dry-run is given,
# adds the changelog entry and pins the checksums for the new version.
#
# Usage:
#   ci/upstream-check.sh [--dry-run] [version]
#
# With no version, the latest stable release is used. Prints latest, current
# and changed. When GITHUB_OUTPUT is set, writes version, url and changed
# there for the workflow.
set -eu

api="https://git.deuxfleurs.fr/api/v1/repos/Deuxfleurs/garage/releases?limit=20"
dry_run=0
if [ "${1:-}" = "--dry-run" ]; then
	dry_run=1
	shift
fi
requested=${1:-}

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
curl -fsSL "$api" -o "$tmp"

info=$(python3 - "$tmp" "$requested" <<'PY'
import json
import sys

releases = json.load(open(sys.argv[1]))
requested = sys.argv[2].lstrip("v")
usable = [r for r in releases if not r["draft"] and not r["prerelease"]]
if requested:
    match = [r for r in usable if r["tag_name"].lstrip("v") == requested]
    if not match:
        sys.exit(f"no release for {requested}")
    release = match[0]
else:
    if not usable:
        sys.exit("no stable upstream release found")
    release = usable[0]
print(release["tag_name"].lstrip("v"))
print(release["html_url"])
PY
)
latest=$(printf '%s\n' "$info" | sed -n '1p')
url=$(printf '%s\n' "$info" | sed -n '2p')

current=$(./build.sh version)
current=${current%-*}

changed=false
if dpkg --compare-versions "$latest" gt "$current"; then
	changed=true
fi

if [ -n "${GITHUB_OUTPUT:-}" ]; then
	{
		echo "version=$latest"
		echo "url=$url"
		echo "changed=$changed"
	} >>"$GITHUB_OUTPUT"
fi
printf 'latest=%s current=%s changed=%s\n' "$latest" "$current" "$changed"

[ "$changed" = true ] || exit 0

entry=$(cat <<EOF
garage (${latest}-1) trixie; urgency=medium

  * Package upstream release ${latest}. Release notes:
    ${url}

 -- bor <me@bor691.ir>  $(date -R)
EOF
)

if [ "$dry_run" -eq 1 ]; then
	printf '\n%s\n' "$entry"
	exit 0
fi

{
	printf '%s\n\n' "$entry"
	cat debian/changelog
} >debian/changelog.new
mv debian/changelog.new debian/changelog

VERSION=$latest ARCH=amd64 ./build.sh record
VERSION=$latest ARCH=arm64 ./build.sh record

if [ -f README.md ]; then
	sed -i "s/${current}/${latest}/g" README.md
fi
