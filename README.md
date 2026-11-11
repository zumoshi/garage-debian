# garage-debian

A Debian package for [Garage](https://garagehq.deuxfleurs.fr), the
S3-compatible object storage from Deuxfleurs.

It installs Garage on Debian 13 trixie and lets you run one or more instances
as systemd services, each with its own config under `/etc/garage/`.

This package is a building block. It does not start a server by itself. If
you use OpenMediaVault, install the
[openmediavault-garage](https://github.com/zumoshi/openmediavault-garage)
plugin instead. It creates and manages instances for you.

## What you get

- the upstream static `garage` binary
- `garage@.service`, a template unit for any number of instances
- a `garage` system user and group
- `/etc/garage`, owned by `root:garage`, mode 0750
- an example config and the Debian docs

## Requirements

- Debian 13 trixie
- amd64 for the published deb. The build script also supports arm64.

## Install

Download the latest deb and install it:

```sh
wget -qO- https://api.github.com/repos/zumoshi/garage-debian/releases/latest \
  | grep -o 'https://[^"]*amd64.deb' | head -1 | xargs wget
sudo apt install ./garage_*_amd64.deb
```

Nothing starts yet.

## Run one instance

Garage needs a config, a secret, a data directory, and a layout before it can
serve S3. This is the minimum for a single node.

### 1. Create the directories and the RPC secret

```sh
sudo install -d -o garage -g garage -m 0750 /var/lib/garage/myinst
sudo install -d -o garage -g garage -m 0750 \
  /var/lib/garage/myinst/meta /var/lib/garage/myinst/data
sudo install -m 0600 -o garage -g garage /dev/null \
  /etc/garage/myinst.rpc_secret
head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n' |
  sudo tee /etc/garage/myinst.rpc_secret >/dev/null
sudo chown garage:garage /etc/garage/myinst.rpc_secret
sudo chmod 0600 /etc/garage/myinst.rpc_secret
```

### 2. Write the config

Replace the admin token with a long random string, for example the output of
`head -c 32 /dev/urandom | base64`.

```sh
sudo tee /etc/garage/myinst.toml >/dev/null <<'EOF'
metadata_dir = "/var/lib/garage/myinst/meta"
data_dir = "/var/lib/garage/myinst/data"
db_engine = "lmdb"
replication_factor = 1
rpc_bind_addr = "127.0.0.1:3901"
rpc_secret_file = "/etc/garage/myinst.rpc_secret"

[s3_api]
s3_region = "garage"
api_bind_addr = "[::]:3900"

[admin]
api_bind_addr = "127.0.0.1:3903"
admin_token = "replace-with-a-long-random-token"
EOF
sudo chown root:garage /etc/garage/myinst.toml
sudo chmod 0640 /etc/garage/myinst.toml
```

Any path outside `/var/lib/garage` needs a `ReadWritePaths` drop-in. See
[Paths outside /var/lib/garage](#paths-outside-varlibgarage).

### 3. Start it

```sh
sudo systemctl enable --now garage@myinst
sudo systemctl status garage@myinst
curl http://127.0.0.1:3903/health
```

### 4. Assign the layout

The first column of `garage status` is the node ID.

```sh
sudo -u garage garage -c /etc/garage/myinst.toml status
sudo -u garage garage -c /etc/garage/myinst.toml \
  layout assign -z dc1 -c 1T <node-id>
sudo -u garage garage -c /etc/garage/myinst.toml \
  layout apply --version 1
```

### 5. Create a key and a bucket

Save the secret that `key create` prints. Then point an S3 client at
`http://<host>:3900` with region `garage`.

```sh
sudo -u garage garage -c /etc/garage/myinst.toml key create my-key
sudo -u garage garage -c /etc/garage/myinst.toml bucket create my-bucket
sudo -u garage garage -c /etc/garage/myinst.toml \
  bucket allow --read --write --owner my-bucket --key my-key
```

The Garage documentation describes every option at
[garagehq.deuxfleurs.fr](https://garagehq.deuxfleurs.fr/documentation/reference-manual/configuration/).

## Paths outside /var/lib/garage

The unit runs with `ProtectSystem=strict` and can write only to
`/var/lib/garage`. If you put metadata or data somewhere else, add a drop-in:

```sh
sudo mkdir -p /etc/systemd/system/garage@myinst.service.d
sudo tee /etc/systemd/system/garage@myinst.service.d/override.conf >/dev/null <<'EOF'
[Service]
ReadWritePaths=/srv/garage/meta /srv/garage/data
EOF
sudo systemctl daemon-reload
sudo systemctl restart garage@myinst
```

The `garage` user must also be able to write the paths.

## Upgrade

Install the new deb over the old one:

```sh
sudo apt install ./garage_<new-version>_amd64.deb
```

Running instances restart. Stopped instances stay stopped.

## Remove

```sh
sudo apt remove garage
```

This stops the instances and removes the package. Your configs in
`/etc/garage` and your data stay. Reinstall the package to start them again.

`apt purge garage` removes the package files. It does not delete your configs
or data.

## Verify the download

Every release has a signed checksum file. Download the public key from
`keys/release-signing.asc` in this repository.

```sh
gpg --import release-signing.asc
gpg --verify SHA256SUMS.asc SHA256SUMS
sha256sum -c SHA256SUMS
```

Compare the key fingerprint with `keys/README.md`.

## Troubleshooting

- `systemctl status garage@<name>` and `journalctl -u garage@<name>` show why
  the unit stopped.
- `sudo garage -c /etc/garage/<name>.toml status` talks to the running node.
- `Permission denied` on a data path usually means the path is outside
  `/var/lib/garage` and has no `ReadWritePaths` drop-in, or the `garage` user
  cannot write it.
- `Address already in use` means another instance uses the same port. Give
  each instance its own S3, RPC, and admin port.
- Garage refuses secret files that are not mode 0600.

## Development

Build, test, release, and design notes are in
[CONTRIBUTING.md](CONTRIBUTING.md).

## License

The Garage binary is AGPL-3.0, copyright Deuxfleurs and the Garage
contributors. The packaging in this repository is under the same terms. The
full text is in [LICENSE](LICENSE).
