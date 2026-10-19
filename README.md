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
VERSION=2.4.1 ARCH=amd64 ./build.sh   # dist/garage_2.4.1-1_amd64.deb
VERSION=2.4.1 ARCH=arm64 ./build.sh
```

Needs `nfpm` (`deb [trusted=yes] https://apt.fury.io/goreleaser/ /`) and
`curl`. Builds are checksum-verified against `checksums/`, which CI enforces.

## CI

`.github/workflows/build.yml` runs on tags `v*` and on manual dispatch with a
version input. It produces `garage_<v>-1_amd64.deb` and `..._arm64.deb` and
attaches them to the GitHub release on tag builds.

## Install

```sh
apt install ./garage_2.4.1-1_amd64.deb
```

Hand-run an instance:

```sh
zcat /usr/share/doc/garage/examples/garage.toml.gz 2>/dev/null || cat /usr/share/doc/garage/examples/garage.toml
# edit, save as /etc/garage/myinst.toml
printf '[Service]\nReadWritePaths=/var/lib/garage\n' \
  > /etc/systemd/system/garage@myinst.service.d/override.conf
systemctl daemon-reload
systemctl enable --now garage@myinst
```

`ProtectSystem=strict` is active in the base unit, so every path Garage must
write needs a `ReadWritePaths` entry in the instance drop-in. The base unit
allows `/etc/garage` and `/var/lib/garage`.

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
