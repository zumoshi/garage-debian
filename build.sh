#!/bin/sh
set -eu

usage() {
	cat <<EOF
Usage:
  VERSION=2.4.1 ARCH=amd64 [RELEASE=1] $0          build one deb
  VERSION=2.4.1 ARCH=amd64 $0 record               pin the upstream checksum
  VERSION=2.4.1 ARCH=all $0 verify                 verify all pinned checksums
EOF
	exit 2
}

target_for_arch() {
	case "$1" in
	amd64) echo "x86_64-unknown-linux-musl" ;;
	arm64) echo "aarch64-unknown-linux-musl" ;;
	*) return 1 ;;
	esac
}

download() {
	_arch=$1
	_target=$(target_for_arch "$_arch")
	_url="https://garagehq.deuxfleurs.fr/_releases/v${VERSION}/${_target}/garage"
	mkdir -p tree/usr/bin
	_sumfile="checksums/${VERSION}.${_arch}.sha256"
	if [ -f "tree/usr/bin/garage" ] && [ -f "$_sumfile" ]; then
		_actual=$(sha256sum tree/usr/bin/garage | awk '{print $1}')
		if [ "$_actual" = "$(cat "$_sumfile")" ]; then
			echo "tree/usr/bin/garage already matches ${_sumfile}"
			return
		fi
	fi
	echo "downloading ${_url}"
	curl -fsSL -o "tree/usr/bin/garage" "$_url"
	chmod 0755 tree/usr/bin/garage
}

case "${1:-build}" in
record)
	[ -n "${VERSION:-}" ] && [ -n "${ARCH:-}" ] || usage
	download "$ARCH"
	sha256sum tree/usr/bin/garage | awk '{print $1}' > "checksums/${VERSION}.${ARCH}.sha256"
	echo "pinned checksums/${VERSION}.${ARCH}.sha256"
	;;
verify)
	[ -n "${VERSION:-}" ] || usage
	status=0
	for f in checksums/"${VERSION}".*.sha256; do
		[ -e "$f" ] || {
			echo "no pinned checksums for ${VERSION}" >&2
			exit 1
		}
		arch=${f#checksums/"${VERSION}".}
		arch=${arch%.sha256}
		download "$arch"
		expected=$(cat "$f")
		actual=$(sha256sum tree/usr/bin/garage | awk '{print $1}')
		if [ "$actual" = "$expected" ]; then
			echo "ok ${arch}"
		else
			echo "MISMATCH ${arch}: expected ${expected} got ${actual}" >&2
			status=1
		fi
	done
	exit $status
	;;
build)
	[ -n "${VERSION:-}" ] && [ -n "${ARCH:-}" ] || usage
	RELEASE=${RELEASE:-1}
	OUT=${OUT:-dist}
	target_for_arch "$ARCH" >/dev/null || usage
	download "$ARCH"
	sumfile="checksums/${VERSION}.${ARCH}.sha256"
	[ -f "$sumfile" ] || {
		echo "missing ${sumfile}; run '$0 record' once and commit it" >&2
		exit 1
	}
	expected=$(cat "$sumfile")
	actual=$(sha256sum tree/usr/bin/garage | awk '{print $1}')
	[ "$actual" = "$expected" ] || {
		echo "checksum mismatch for ${ARCH}" >&2
		exit 1
	}
	mkdir -p "$OUT"
	VERSION="$VERSION" RELEASE="$RELEASE" ARCH="$ARCH" \
		nfpm package -f nfpm.yaml -p deb \
		-t "${OUT}/garage_${VERSION}-${RELEASE}_${ARCH}.deb"
	;;
*)
	usage
	;;
esac
