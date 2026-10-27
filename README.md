# garage-debian

Debian packaging for [Garage](https://garagehq.deuxfleurs.fr), the
S3-compatible self-hosted object storage by Deuxfleurs. Targets Debian 13
(trixie). The deb ships upstream's official static musl binary, a
`garage@.service` systemd template unit for running multiple instances, a
dedicated `garage` system user (sysusers.d), and hardened defaults. It builds
with [nfpm](https://nfpm.goreleaser.com) in GitHub Actions.

The package does not start anything by itself. Create instances as
`garage@<name>.service` with configs at `/etc/garage/<name>.toml`, or install
the `openmediavault-garage` plugin, which manages instances for you.

## Build

One-time per release, pin the upstream checksums (both architectures):

```sh
VERSION=2.4.1 ARCH=amd64 ./build.sh record
VERSION=2.4.1 ARCH=arm64 ./build.sh record
git add checksums
```

Then build:

```sh
make build                       # dist/garage_2.4.1-1_amd64.deb
ARCH=arm64 ./build.sh            # needs nfpm on PATH, or NFPM=/path/to/nfpm
```

The package version comes from the top entry of `debian/changelog`.
`RELEASE` defaults to that entry's Debian revision, and the build fails when
`VERSION-RELEASE` does not match it. Add a changelog entry for each release.

`make build` downloads nfpm from its pinned GitHub release into `.tools/` and
checks it against `checksums/nfpm_*.sha256`. To move to a new nfpm, change
`NFPM_VERSION` in the `Makefile` and commit the sha256 of the new
`Linux_x86_64` tarball from the release's `checksums.txt`. The garage binary
is checksum-verified against `checksums/` on every build.

## CI

`.github/workflows/build.yml` runs on tags `v*` and on manual dispatch with a
version input. It produces `garage_<v>-<release>_amd64.deb` and `..._arm64.deb` and
attaches them to the GitHub release on tag builds.

## Test

`tests/smoke.sh` runs lintian on a built deb, then installs it on a
disposable Debian 13 host over ssh. It checks the `/etc/garage` mode, the
unit hardening, that an upgrade restarts running instances and leaves stopped
ones stopped, and the remove, purge and reinstall cycle. It replaces the
host's garage package and leaves the tested deb installed.

```sh
tests/smoke.sh root@garage-test.lan dist/garage_2.4.1-1_amd64.deb
```

## Install

```sh
apt install ./garage_2.4.1-1_amd64.deb
```

Hand-run an instance:

```sh
zcat /usr/share/doc/garage/examples/garage.toml.gz 2>/dev/null || cat /usr/share/doc/garage/examples/garage.toml
# edit, save as /etc/garage/myinst.toml
chown root:garage /etc/garage/myinst.toml
chmod 0640 /etc/garage/myinst.toml
mkdir -p /etc/systemd/system/garage@myinst.service.d
printf '[Service]\nReadWritePaths=/path/to/metadata /path/to/data\n' \
  > /etc/systemd/system/garage@myinst.service.d/override.conf
systemctl daemon-reload
systemctl enable --now garage@myinst
```

`ProtectSystem=strict` is active in the base unit, so every path Garage must
write needs a `ReadWritePaths` entry in the instance drop-in. The base unit
allows only `/var/lib/garage`, so paths under it need no drop-in.
`/etc/garage` is `0750 root:garage` and read-only to the service.

## Design notes

- The binary is the upstream musl static build, byte-identical to the release
  artifact, checksum-pinned in-tree. No Rust toolchain in CI.
- Upstream Arch packaging (binary + unit + sysusers + tmpfiles) was the model;
  the difference is the template unit for multi-instance use.
- Secrets (`rpc_secret`, admin tokens) are not written by this package.
  Whatever creates `/etc/garage/<name>.toml` owns them; Garage refuses
  secret files that are not mode 0600, so the OMV plugin renders them
  0600 owned by the `garage` user.

License: the Garage binary is AGPL-3.0, (c) Deuxfleurs. Packaging glue in
this repo is provided under the same terms.
