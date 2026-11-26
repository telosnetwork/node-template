# TelosZero node templates

Security-focused templates for Telos block producers, vote relays, APIs, and
SHiP nodes. These instructions assume Savanna instant finality is already live.
They do **not** include the one-time Lightspeed/Savanna activation or
`switchtosvnn` choreography.

Start with the full
[Telos BP setup guide](https://docs.telos.net/nodes/bp-nodes/setting-up-telos-validator-nodes/)
and read [FINALIZER.md](FINALIZER.md) before configuring any producer-capable
host.

## Supported software

The latest published artifact is
[TelosZero Core 1.4.1](https://github.com/telosnetwork/teloszero-core/releases/tag/teloszero-v1.4.1):

```text
Package: teloszero-core_1.4.1_amd64.deb
SHA-256: d9c8b841690270ab65e3b7aa267417c19af0d629c88a60323bd79e798166ecdc
Package install and local testnet startup checked on Ubuntu 24.04, x86-64
```

Use the exact tagged artifact approved for the target network. Do not replace
it with Leap, a random Spring build, or the `main` branch.

```bash
cd /tmp
curl -fLO https://github.com/telosnetwork/teloszero-core/releases/download/teloszero-v1.4.1/teloszero-core_1.4.1_amd64.deb
echo 'd9c8b841690270ab65e3b7aa267417c19af0d629c88a60323bd79e798166ecdc  teloszero-core_1.4.1_amd64.deb' \
  | sha256sum --check --strict
sudo apt-get update
sudo apt-get install -y ./teloszero-core_1.4.1_amd64.deb jq

nodeos --full-version
cleos version client
spring-util version full
```

Installing the package may replace historical `leap`, `spring`, or
`antelope-spring` packages that provide the same commands.

## Choose one role per instance

| Profile | Purpose | Signing keys | Vote threads |
|---|---|---|---|
| `producer` | Private BP producer and finalizer | Dedicated K1 plus unique BLS | `4` |
| `backup-producer` | Synced failover, with K1 production paused | Same dedicated K1 plus a different BLS | `4` |
| `vote-relay` | Public/private sentry that carries blocks and finalizer votes | None | `4` |
| `api` | Read-only RPC behind a TLS proxy | None | `0` |
| `ship` | State History endpoint restricted to indexers | None | `0` |

A relay without positive `vote-threads` drops Savanna votes instead of
forwarding them. API and SHiP nodes outside the vote path explicitly use zero.
Do not combine public API, SHiP, or indexing workloads with a private producer.

## Production topology

Use a private primary producer, a private backup producer, and at least two
independent relay paths. The producer HTTP API binds to loopback, and its P2P
listener accepts only BP-controlled relays. Public peers belong on relays, APIs,
and SHiP nodes—not directly on the producer.

Every producer-capable host needs:

- the BP's dedicated K1 block-signing key;
- its own BLS finalizer key, never shared with another host;
- a local, persistent `finalizers-dir` outside disposable chain data;
- a complete, never-rolled-back `safety.dat` for that BLS key.

See [REQUIREMENTS.md](REQUIREMENTS.md) for the infrastructure baseline.

## Create the service account and directories

The supplied service and examples use these paths:

```text
/etc/telos/mainnet-primary/              configuration
/var/lib/telos/mainnet-primary/          chain data
/var/lib/telos/finalizers/mainnet-primary/ finalizer safety state
/var/lib/telos/keys/                     protected key-generation output
```

```bash
id -u telos >/dev/null 2>&1 \
  || sudo useradd --system --home-dir /var/lib/telos --shell /usr/sbin/nologin telos

sudo install -d -o root -g telos -m 0750 /etc/telos/mainnet-primary
sudo install -d -o telos -g telos -m 0750 /var/lib/telos/mainnet-primary
sudo install -d -o telos -g telos -m 0700 /var/lib/telos/finalizers/mainnet-primary
sudo install -d -o telos -g telos -m 0700 /var/lib/telos/keys
```

Never place a finalizer directory on `tmpfs`, NFS, a snapshot-restored volume,
or storage shared by two `nodeos` instances. Give every network/instance its own
directory.

The role profiles put the writable `protocol-features-dir` under the instance's
data directory. This allows `/etc/telos/<instance>` and its key-bearing
configuration to remain root-owned and read-only to the `telos` service account.

## Generate the BLS key before rendering

Generate the BLS key on the producer host under the `telos` account:

```bash
sudo -u telos sh -c '
  umask 077
  key_file=/var/lib/telos/keys/finalizer-mainnet-primary.txt
  test ! -e "$key_file" || { echo "Refusing to overwrite $key_file" >&2; exit 1; }
  spring-util bls create key --file "$key_file"
'
```

The file contains three labeled values: `Private key`, `Public key`, and
`Proof of Possession`. Use its public and private values in the producer profile,
then follow [FINALIZER.md](FINALIZER.md) for registration and verification.

Do not pass that three-line output file to `spring-util bls create pop`; that
command expects a file containing only a raw private key.

## Render and install a role profile

Render a network/role combination to a new file. The renderer annotates the
expected chain ID for post-start verification and, for non-producer roles,
appends the current verified public peer list. `chain-id` is not a valid
`nodeos` configuration option; the chain is selected by its genesis/snapshot
state and verified through `get_info`.

```bash
./scripts/render-config.sh mainnet producer mainnet-primary /tmp/telos-producer.ini
```

Replace every `<PLACEHOLDER>` in the rendered file. A producer must retain both
signature providers:

```ini
producer-name = <BP_ACCOUNT>
signature-provider = <PUB_K1_BLOCK_KEY>=KEY:<PVT_K1_BLOCK_KEY>
signature-provider = <PUB_BLS_FINALIZER_KEY>=KEY:<PVT_BLS_FINALIZER_KEY>
vote-threads = 4
finalizers-dir = /var/lib/telos/finalizers/mainnet-primary
production-pause-vote-timeout-ms = 6000
chain-state-db-size-mb = 32768
```

Do not use the BP account active key as the K1 block-signing key. Do not set
`production-pause-vote-timeout-ms = 0`; the default guard pauses production
when finalizer votes disappear. TelosZero's 1024 MiB chain-state default is too
small for current Telos state, so every profile uses 32768 MiB; keep it below
usable physical RAM and raise it deliberately as measured chain state grows.

Install the reviewed files:

```bash
sudo install -o root -g telos -m 0640 /tmp/telos-producer.ini \
  /etc/telos/mainnet-primary/config.ini
sudo install -o root -g telos -m 0640 logging.json \
  /etc/telos/mainnet-primary/logging.json
```

The tracked root `config.ini` is the same fail-closed mainnet producer example
for existing users of this repository. It must not start until its placeholders
are replaced. Keep completed configurations and all key material out of Git.

## Bootstrap and run with systemd

Use a recent snapshot from a trusted provider and verify any published
checksum. Import it with the same user and paths as the service:

> **Warning — replacing an already scheduled producer:** Before starting either
> the snapshot import or the service on a replacement host, add
> `pause-on-startup = true` (or render the `backup-producer` role). This pauses
> K1 block production while still allowing finalizer voting. Prove the old K1
> signer is stopped and fenced, and use a new BLS key with its own safety
> history, before removing the pause and restarting. Never enable the same K1
> key on two hosts at once, and never share or reuse a BLS key between hosts.

```bash
sudo -u telos /usr/bin/nodeos \
  --config-dir /etc/telos/mainnet-primary \
  --data-dir /var/lib/telos/mainnet-primary \
  --snapshot /var/lib/telos/mainnet-primary/snapshots/<snapshot-file>.bin
```

Run this in the foreground only for the first import, confirm it loaded the
snapshot into the intended data directory, then stop it cleanly with `Ctrl-C`.
Savanna does not change the existing mainnet or testnet genesis files, but a
snapshot is the normal BP bootstrap path. Start the service without `--snapshot`:

```bash
sudo install -o root -g root -m 0644 systemd/telos-nodeos@.service \
  /etc/systemd/system/telos-nodeos@.service
sudo systemctl daemon-reload
sudo systemctl enable --now telos-nodeos@mainnet-primary
sudo systemctl status telos-nodeos@mainnet-primary
sudo journalctl -u telos-nodeos@mainnet-primary -f
```

Verify the local chain before any on-chain key registration:

```bash
curl -s http://127.0.0.1:8888/v1/chain/get_info | jq '{
  chain_id,
  server_full_version_string,
  head_block_num,
  last_irreversible_block_num,
  head_block_time,
  head_block_producer
}'
```

Required checks:

- the chain ID exactly matches `mainnet/chain-id.txt` or `testnet/chain-id.txt`;
- the approved full version is running;
- head and irreversible blocks advance and the node reaches network head;
- both relay paths stay connected;
- logs contain no key parsing, safety-file, fork, or persistent vote errors.

Then register/update the producer account from a separate control/signing host,
not from the producer:

```bash
cleos -u "$RPC" system regproducer \
  "$BP_ACCOUNT" "$BLOCK_SIGNING_PUBLIC_KEY" "$BP_URL" "$BP_LOCATION" \
  -p "$BP_ACCOUNT@active"
```

`BP_LOCATION` is a numeric `uint16`, not a city name. Complete finalizer
registration and active-policy verification in [FINALIZER.md](FINALIZER.md)
before accepting an active schedule slot.

## Manual compatibility scripts

`start.sh` and `stop.sh` remain for development and existing clone-per-node
deployments. Configure `node_config`, replace every placeholder in `config.ini`,
and run `./start.sh`. The script refuses duplicate starts and production use of
`--enable-stale-production`; `stop.sh` validates the PID and waits for a clean
SIGINT shutdown. Systemd is the production recommendation.

## Refresh public peers

The checked-in peer lists are generated from endpoints currently marked
verified by [validators.telos.net](https://validators.telos.net/), deduplicated,
and validated for syntax:

```bash
./scripts/update-peers.py
```

Validator verification is a point-in-time signal, not an availability or trust
guarantee. Curate peers for operator and geographic diversity, monitor them, and
keep private producers behind BP-controlled vote relays.

## Validate a change

```bash
./scripts/validate.sh
```

The validation checks JSON and shell syntax, canonical chain IDs, peer syntax,
role separation, private producer HTTP, BLS/K1 providers, vote-thread settings,
SHiP finality history, and finalizer-safety paths. CI runs the same command.

## Steady-state readiness gate

This repository presumes instant finality is live. Before enabling production,
`cleos get finalizer_info` must return a non-null active policy and advancing
tracked votes for active finalizers. If the target chain has no active native
policy, stop: it has not reached the steady state assumed by these templates.
