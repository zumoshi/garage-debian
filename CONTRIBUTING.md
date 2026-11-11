# Contributing to garage-debian

This file is for people building, testing, or releasing the package. For
installing and running Garage, see [README.md](README.md).

## Building

The build uses [nfpm](https://nfpm.goreleaser.com) to make the deb. The
version comes from the top entry of `debian/changelog`.

Pin the upstream checksums once per release. `make verify` checks every
pinned architecture; CI builds amd64 only.

```sh
VERSION=2.5.0 ARCH=amd64 ./build.sh record
VERSION=2.5.0 ARCH=arm64 ./build.sh record
git add checksums
```

Then build:

```sh
make build                       # dist/garage_2.5.0-1_amd64.deb
ARCH=arm64 ./build.sh            # needs nfpm on PATH, or NFPM=/path/to/nfpm
```

`RELEASE` defaults to the changelog's Debian revision. The build fails when
`VERSION-RELEASE` does not match the changelog entry.

`make build` downloads nfpm from its pinned GitHub release into `.tools/` and
checks it against `checksums/nfpm_*.sha256`. To move to a new nfpm, change
`NFPM_VERSION` in the `Makefile` and commit the sha256 of the new
`Linux_x86_64` tarball from the release's `checksums.txt`. The build verifies
the garage binary against `checksums/` on every build.

## Checks

`make check` and `make lint` run their tools in Docker.

```sh
make check    # actionlint, shellcheck, no private keys tracked
make verify   # every pinned upstream checksum of this version
make lint     # builds the amd64 deb, then runs trixie's lintian
```

The `Makefile` pins nfpm and the actionlint image. `ci/tools.Dockerfile`
pins the trixie image for lintian and shellcheck. The workflows pin actions
by commit SHA.

## Smoke test

`tests/smoke.sh` runs lintian on a built deb, then installs it on a
disposable Debian 13 host over ssh. It checks the `/etc/garage` mode and the
unit hardening. It checks that an upgrade restarts running instances and
leaves stopped ones stopped. It also checks remove, purge, and reinstall.
The script replaces the host's garage package and leaves the tested deb
installed.

```sh
tests/smoke.sh root@garage-test.lan dist/garage_2.5.0-1_amd64.deb
```

## CI

`.github/workflows/build.yml` runs on every push and pull request. It calls
the same make targets you run locally: `make check`, `make verify`, and
`make lint`. The `package` job uploads the deb as an artifact.

`.github/workflows/upstream.yml` is manual. It checks the upstream release
feed and opens a draft PR with the new changelog entry and checksums. Use the
`upstream` workflow in the Actions tab, or run `ci/upstream-check.sh` locally
with `--dry-run`.

## Releasing

Push a tag `v<version>-<release>` that equals the top `debian/changelog`
entry, for example `v2.5.0-1`, or `v2.5.0-2` for a packaging-only fix. CI
fails when the tag and the changelog disagree.

After the checks pass, the `sign` job writes `SHA256SUMS` for the deb and a
detached `SHA256SUMS.asc`. It signs with the key in `GPG_PRIVATE_KEY` and
takes the passphrase from `GPG_PASSPHRASE`, if set. It verifies the signature
against `keys/`. The `publish` job attaches the deb, `SHA256SUMS`, and
`SHA256SUMS.asc` to the GitHub release. Only `sign` sees the secrets, and
only `publish` can write to the repository. Pull requests never reach either
job.

The public key is `keys/release-signing.asc`. The private half lives in the
`release` environment, not in this repository. `make check` fails if private
key material is ever committed.

The first release of a new upstream version needs the checksums pinned and a
changelog entry. A packaging-only fix uses a higher Debian revision, such as
`2.5.0-2`, and does not need new upstream checksums.

## Repository layout

- `build.sh` downloads and pins the upstream binary, then calls nfpm
- `nfpm.yaml` describes the package contents
- `debian/` holds `changelog` and the source format
- `tree/` is the filesystem tree that goes into the deb
- `checksums/` pins the upstream binaries and nfpm
- `ci/` holds the workflow helper scripts and the tools image
- `tests/smoke.sh` is the disposable-host test
- `keys/` holds the public release signing key

## Design notes

- The binary is the upstream musl static build, byte-identical to the release
  artifact and checksum-pinned in-tree. No Rust toolchain in CI.
- Upstream Arch packaging shipped the binary, the unit, sysusers, and
  tmpfiles. This package uses the same layout, plus a template unit for
  multi-instance use.
- The package does not write secrets. It leaves `rpc_secret` and admin tokens
  to whatever creates `/etc/garage/<name>.toml`. Garage refuses secret files
  that are not mode 0600, so the OMV plugin renders them 0600 owned by the
  `garage` user.

## License

The Garage binary is AGPL-3.0, copyright Deuxfleurs and the Garage
contributors. The packaging in this repository is under the same terms. The
full text is in [LICENSE](LICENSE).
