# Production requirements

A post-Savanna BP continuously signs finalizer votes as well as producing its
scheduled blocks. Size and secure the complete producer-to-relay path.

## Required topology

| Role | Exposure | Finalizer behavior |
|---|---|---|
| Primary producer | Private | Unique BLS key, `vote-threads = 4`, persistent safety state |
| Backup producer | Private and paused until handoff | Different BLS key and independent safety state |
| Two or more relay/sentry paths | P2P as required | No keys; `vote-threads = 4` |
| Control/signing host | Restricted administration | Holds BP account authority; no finalizer |
| API/SHiP nodes | Public only through hardened proxies | No keys; `vote-threads = 0` unless deliberately a relay |

Avoid a single provider, firewall, switch, region, or transit link that can
isolate the producer. Do not place primary and backup producers in one fault
domain, and do not run public API/indexing workloads on a private producer.

## Planning baseline

These are operational starting points, not consensus constants. Benchmark the
approved TelosZero artifact under replay and peak load, then leave substantial
headroom.

| Resource | Producer baseline |
|---|---|
| CPU | Modern high-clock x86-64 with at least 8 dedicated cores |
| Memory | 64 GB ECC recommended; never size chain state above usable RAM |
| Storage | Enterprise NVMe with power-loss protection and growth headroom |
| Network | Redundant, low-latency 1 Gbit/s or better paths |
| Clock | Multiple NTP sources with drift and clock-jump alerts |
| Power | Redundant power where available and tested graceful shutdown |
| OS | The supported Ubuntu release for the approved package |

TelosZero uses chain, network, and vote worker pools. Do not pin the entire
process to one CPU. Size API, SHiP, archive, and indexer storage from measured
retention requirements rather than stale repository figures. The supplied
profiles set `chain-state-db-size-mb = 32768` because the 1024 MiB software
default is insufficient; keep that capacity below usable RAM and monitor growth.

## Persistent finalizer storage

`finalizers-dir` contains consensus-critical `safety.dat`. It must be:

- on persistent local storage outside the disposable chain data directory;
- owned by the `nodeos` service user and mode `0700`;
- monitored for write, checksum, permission, latency, and capacity failures;
- excluded from cross-host replication and generic restore automation;
- preserved in place through normal restarts, replays, and snapshot recovery.

Never copy or roll back `safety.dat`, share it over NFS, or reuse its BLS key on
another host. A chain snapshot does not recover finalizer voting history.

## Key custody

- Keep BP owner/active authorities off producer hosts.
- Use a dedicated K1 block-signing key, not the account active key.
- Generate one BLS key per producer-capable host and never export it to another.
- Protect completed key-bearing configs as `root:telos` with mode `0640`; keep
  writable protocol-feature files under the instance data directory.
- Pre-register a distinct backup BLS key before an emergency.

TelosZero 1.2.x BLS keys use the direct `KEY` provider, so host and file
protection are part of the signing boundary.

## Network and service security

- Bind producer HTTP to loopback and allow producer P2P only from controlled relays.
- Set `vote-threads = 4` on every relay hop carrying finalizer traffic.
- Maintain two independent inbound/outbound vote paths.
- Put public HTTP behind TLS, rate limiting, and request filtering.
- Never expose `producer_api_plugin` or `net_api_plugin` directly to the internet.
- Restrict SHiP endpoints to trusted indexers.
- Curate public peers for operator and geographic diversity; monitor continuously.

## Monitoring and retention

Monitor process/version/checksum, head and LIB, native policy generation,
tracked-vote freshness, production pauses, missed blocks, both relay paths,
resource saturation, disk/inodes, finalizer writes, clock drift, configuration
changes, and unexpected `regfinkey`/`actfinkey`/`delfinkey` transactions.

Use journald retention or managed log rotation. Never reclaim space by truncating
a live log manually. Alert an operator who can execute the tested rotation and
failover runbook whenever the BP is scheduled.

Exercise on testnet at least quarterly and before a major release: artifact
upgrade, vote propagation, activation of the backup BLS key, positive shutdown
of the primary, exclusive K1 handoff, and recovery with a new key when safety
history is unavailable.
