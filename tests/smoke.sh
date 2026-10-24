#!/bin/bash
# Install/upgrade/remove/purge cycle for a built garage deb on a disposable
# Debian host. Destructive to that host's garage package and to instances
# named smoke-*.
#
#   tests/smoke.sh root@garage-test.lan dist/garage_2.4.1-1_amd64.deb
#
# The host must run systemd and have curl. Port range 3910-3923 must be free.
set -euo pipefail

if [ "${1:-}" != --on-target ]; then
	[ $# -eq 2 ] || {
		echo "usage: $0 <ssh-host> <deb>" >&2
		exit 2
	}
	host=$1 deb=$2
	status=0
	if lintian --fail-on error,warning,info --info "$deb"; then
		echo "ok   lintian clean"
	else
		echo "FAIL lintian"
		status=1
	fi
	ssh "$host" 'rm -rf /tmp/garage-smoke && mkdir /tmp/garage-smoke'
	scp -q "$0" "$host:/tmp/garage-smoke/smoke.sh"
	scp -q "$deb" "$host:/tmp/garage-smoke/garage.deb"
	ssh "$host" bash /tmp/garage-smoke/smoke.sh --on-target /tmp/garage-smoke/garage.deb || status=1
	exit $status
fi

deb=$2
work=$(dirname "$deb")
srv=/srv/garage-smoke
fails=0

check() {
	local desc=$1
	shift
	if "$@"; then
		echo "ok   $desc"
	else
		echo "FAIL $desc"
		fails=$((fails + 1))
	fi
}

die() {
	echo "ERROR $*" >&2
	exit 2
}

# Instance name -> port base. s3 = base, rpc = base+1, admin = base+3.
declare -A base=([smoke-run]=3910 [smoke-stopped]=3920)

make_instance() {
	local name=$1 b=${base[$1]}
	install -d -o garage -g garage -m 0750 "$srv/$name" "$srv/$name/meta" "$srv/$name/data"
	cat >"/etc/garage/$name.toml" <<EOF
metadata_dir = "$srv/$name/meta"
data_dir = "$srv/$name/data"
replication_factor = 1
rpc_bind_addr = "127.0.0.1:$((b + 1))"
rpc_public_addr = "127.0.0.1:$((b + 1))"
rpc_secret_file = "/etc/garage/$name.rpc_secret"

[s3_api]
s3_region = "garage"
api_bind_addr = "127.0.0.1:$b"

[admin]
api_bind_addr = "127.0.0.1:$((b + 3))"
EOF
	chown root:garage "/etc/garage/$name.toml"
	chmod 0640 "/etc/garage/$name.toml"
	openssl rand -hex 32 >"/etc/garage/$name.rpc_secret"
	chown garage:garage "/etc/garage/$name.rpc_secret"
	chmod 0600 "/etc/garage/$name.rpc_secret"
	mkdir -p "/etc/systemd/system/garage@$name.service.d"
	printf '[Service]\nReadWritePaths=%s\n' "$srv/$name" \
		>"/etc/systemd/system/garage@$name.service.d/override.conf"
}

remove_instances() {
	local name
	for name in "${!base[@]}"; do
		systemctl disable --now "garage@$name.service" >/dev/null 2>&1 || true
		rm -rf "/etc/garage/$name.toml" "/etc/garage/$name.rpc_secret" \
			"/etc/systemd/system/garage@$name.service.d" "${srv:?}/$name"
	done
	rmdir "$srv" 2>/dev/null || true
	systemctl daemon-reload
}

health() {
	curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$((${base[$1]} + 3))/health" || true
}

healthy() {
	for _ in $(seq 30); do
		[ "$(health "$1")" = 200 ] && return 0
		sleep 1
	done
	return 1
}

active() { systemctl is-active --quiet "garage@$1.service"; }
prop() { systemctl show -p "$2" --value "garage@$1.service"; }
mode_is() { [ "$(stat -c '%a %U:%G' "$1")" = "$2" ]; }
not() { ! "$@"; }
writable() { prop "$1" ReadWritePaths | tr ' ' '\n' | grep -qx -- "$2"; }
env_has() { prop "$1" Environment | tr ' ' '\n' | grep -q -- "^$2="; }
installed() { dpkg-query -W -f '${db:Status-Status}' garage 2>/dev/null | grep -qx installed; }
user_exists() { id garage >/dev/null 2>&1; }
garage_reads() { runuser -u garage -- cat "$@" >/dev/null; }

finish() {
	remove_instances
	dpkg -i "$deb" >/dev/null || echo "ERROR could not reinstall $deb" >&2
}
trap finish EXIT

remove_instances

echo "# install"
dpkg -i "$deb" >/dev/null || die "dpkg -i $deb failed"
check "/etc/garage is 0750 root:garage after install" mode_is /etc/garage "750 root:garage"
check "/var/lib/garage is 0750 garage:garage after install" mode_is /var/lib/garage "750 garage:garage"
systemd-tmpfiles --create
check "/etc/garage is 0750 root:garage after systemd-tmpfiles --create" mode_is /etc/garage "750 root:garage"

make_instance smoke-run
make_instance smoke-stopped
systemctl daemon-reload
check "unit does not make /etc/garage writable" not writable smoke-run /etc/garage
check "unit does not set GARAGE_CONFIG_FILE" not env_has smoke-run GARAGE_CONFIG_FILE
check "unit keeps ProtectSystem=strict" [ "$(prop smoke-run ProtectSystem)" = strict ]
check "drop-in grants the data path" writable smoke-run "$srv/smoke-run"

systemctl enable --now garage@smoke-run.service 2>/dev/null
systemctl enable garage@smoke-stopped.service 2>/dev/null
active smoke-run || die "garage@smoke-run did not start: $(journalctl -u garage@smoke-run -n 20 --no-pager)"
for _ in $(seq 30); do
	node=$(garage -c /etc/garage/smoke-run.toml node id -q 2>/dev/null) && break
	sleep 1
done
[ -n "${node:-}" ] || die "smoke-run never answered on rpc"
garage -c /etc/garage/smoke-run.toml layout assign -z dc1 -c 1G "${node%@*}" >/dev/null
garage -c /etc/garage/smoke-run.toml layout apply --version 1 >/dev/null
check "running instance answers /health 200" healthy smoke-run
check "enabled-but-stopped instance is inactive before upgrade" not active smoke-stopped

echo "# upgrade"
rm -rf "$work/repack"
dpkg-deb -R "$deb" "$work/repack"
sed -i 's/^Version: .*/&+smoke1/' "$work/repack/DEBIAN/control"
dpkg-deb -b "$work/repack" "$work/garage-next.deb" >/dev/null
pid_before=$(prop smoke-run MainPID)
since_before=$(prop smoke-run ActiveEnterTimestampMonotonic)
dpkg -i "$work/garage-next.deb" >/dev/null || die "upgrade to $(dpkg-deb -f "$work/garage-next.deb" Version) failed"
pid_after=$(prop smoke-run MainPID)
since_after=$(prop smoke-run ActiveEnterTimestampMonotonic)
check "upgrade gave the running instance a new MainPID ($pid_before -> $pid_after)" [ "$pid_after" != "$pid_before" ]
check "upgrade re-entered active state for the running instance" [ "$since_after" != "$since_before" ]
check "running instance is active after upgrade" active smoke-run
check "running instance answers /health 200 after upgrade" healthy smoke-run
check "upgrade left the stopped instance stopped" not active smoke-stopped

echo "# remove"
dpkg -r garage >/dev/null || die "dpkg -r garage failed"
check "remove stopped the running instance" not active smoke-run
check "remove deleted /usr/bin/garage" [ ! -e /usr/bin/garage ]
check "remove kept the instance config" [ -f /etc/garage/smoke-run.toml ]
check "remove kept the instance secret" [ -f /etc/garage/smoke-run.rpc_secret ]
check "remove kept the instance data" [ -d "$srv/smoke-run/meta" ]
check "remove kept the garage user" user_exists

echo "# purge"
dpkg -P garage >/dev/null || die "dpkg -P garage failed"
check "purge removed the package" not installed
check "purge kept the garage user" user_exists
check "purge kept admin-written instance config" [ -f /etc/garage/smoke-run.toml ]
check "purge kept instance data" [ -d "$srv/smoke-run/meta" ]

echo "# reinstall"
dpkg -i "$deb" >/dev/null || die "reinstall failed"
check "/etc/garage is 0750 root:garage after reinstall" mode_is /etc/garage "750 root:garage"
systemctl start garage@smoke-run.service
check "instance starts again after reinstall and answers /health 200" healthy smoke-run
check "garage user can read its config and secret" \
	garage_reads /etc/garage/smoke-run.toml /etc/garage/smoke-run.rpc_secret

echo "# $fails failed"
[ "$fails" -eq 0 ]
