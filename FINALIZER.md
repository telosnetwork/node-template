# Savanna finalizer operations

A Telos BP's producer `nodeos` has two signing responsibilities after Savanna:

- its K1 key signs scheduled blocks;
- its BLS key signs finalizer votes that form quorum certificates.

The finalizer is part of `nodeos`, not a separate daemon.

## Non-negotiable safety rules

1. Generate a unique BLS key for every producer instance.
2. Never share a BLS private key across hosts, networks, or instances.
3. Keep `finalizers/safety.dat` on persistent local storage outside chain data.
4. Never copy `safety.dat` to another host or restore an older version.
5. If safety state is missing, corrupt, stale, or uncertain for a used key,
   retire that key and activate a never-used key.
6. Configure and sync a replacement host/key before activating it on-chain.
7. Never delete an active key. Rotate and verify the replacement first.

These rules prevent a finalizer from signing conflicting branches without its
complete voting history.

## Generate and configure the first key

On the producer host:

```bash
sudo install -d -o telos -g telos -m 0700 /var/lib/telos/keys
sudo install -d -o telos -g telos -m 0700 /var/lib/telos/finalizers/mainnet-primary

sudo -u telos sh -c '
  umask 077
  key_file=/var/lib/telos/keys/finalizer-mainnet-primary.txt
  test ! -e "$key_file" || { echo "Refusing to overwrite $key_file" >&2; exit 1; }
  spring-util bls create key --file "$key_file"
'
```

The output file contains:

```text
Private key: PVT_BLS_...
Public key: PUB_BLS_...
Proof of Possession: SIG_BLS_...
```

Add the BLS provider alongside the K1 provider:

```ini
producer-name = <BP_ACCOUNT>
signature-provider = <PUB_K1_BLOCK_KEY>=KEY:<PVT_K1_BLOCK_KEY>
signature-provider = <PUB_BLS_FINALIZER_KEY>=KEY:<PVT_BLS_FINALIZER_KEY>
vote-threads = 4
finalizers-dir = /var/lib/telos/finalizers/mainnet-primary
production-pause-vote-timeout-ms = 6000
```

BLS supports the direct `KEY` provider in TelosZero 1.2.x; it cannot be loaded
through `keosd`. Install `config.ini` as `root:telos` with mode `0640` so the
service can read but cannot rewrite the key-bearing configuration.

Start and fully sync the producer before registration. A missing `safety.dat`
is expected only on the first start of a never-used key. Once the key votes,
the key and its continuously updated safety history must remain together.

## Register the first finalizer key

The BP must already be a registered producer. Run these transactions from the
separate control/signing host:

```bash
export RPC=https://mainnet.telos.net
export BP_ACCOUNT=<BP_ACCOUNT>
export FINALIZER_PUBLIC_KEY=<PUB_BLS_FINALIZER_KEY>
export FINALIZER_POP=<SIG_BLS_PROOF_OF_POSSESSION>

cleos -u "$RPC" push action eosio regfinkey \
  "$(jq -nc \
    --arg name "$BP_ACCOUNT" \
    --arg key "$FINALIZER_PUBLIC_KEY" \
    --arg pop "$FINALIZER_POP" \
    '{finalizer_name:$name,finalizer_key:$key,proof_of_possession:$pop}')" \
  -p "$BP_ACCOUNT@active"
```

The first registered key automatically becomes active in the contract table.
Do not call `actfinkey` for the initial key; it is for switching to a later,
already registered key.

## Verify the table, native policy, and votes

Join the BP's active key ID to the registered key:

```bash
ACTIVE_ID="$(
  cleos -u "$RPC" get table eosio eosio finalizers --limit 1000 \
    | jq -r --arg bp "$BP_ACCOUNT" \
      '.rows[] | select(.finalizer_name == $bp) | .active_key_id'
)"

cleos -u "$RPC" get table eosio eosio finkeys --limit 1000 \
  | jq --arg bp "$BP_ACCOUNT" --arg id "$ACTIVE_ID" '
      .rows[]
      | select(.finalizer_name == $bp and (.id | tostring) == $id)
    '
```

The returned `finalizer_key` must match the configured BLS public key. A row in
`finkeys` alone proves registration, not active-policy membership or voting.

```bash
cleos -u "$RPC" get finalizer_info \
  | jq --arg bp "$BP_ACCOUNT" '{
      active_generation: .active_finalizer_policy.generation,
      threshold: .active_finalizer_policy.threshold,
      active: [
        .active_finalizer_policy.finalizers[]?
        | select(.description == $bp)
      ],
      pending: [
        .pending_finalizer_policy.finalizers[]?
        | select(.description == $bp)
      ],
      last_vote: [
        .last_tracked_votes[]?
        | select(.description == $bp)
      ]
    }'
```

For a BP in the active producer schedule, verify that:

- the expected key is in the active native policy;
- a pending policy appears only during a schedule/key transition;
- the tracked vote uses the expected key;
- vote block number and timestamp advance on repeated checks;
- the vote generation converges to the active policy generation;
- head and irreversible blocks keep advancing.

A standby BP does not enter the native active policy until it enters the active
producer schedule.

```bash
cleos -u "$RPC" get info | jq '{
  head_block_num,
  last_irreversible_block_num,
  lib_lag: (.head_block_num - .last_irreversible_block_num)
}'
```

Alert on a non-advancing LIB, stale votes, or sustained deviation from the
network baseline rather than one universal lag threshold.

## Carry votes through relays

Every `nodeos` hop between the private producer and peer finalizers must have:

```ini
plugin = eosio::chain_plugin
plugin = eosio::net_plugin
vote-threads = 4
```

Relays have no `producer-name`, K1 key, BLS key, or finalizer directory. A TCP
P2P connection alone does not prove votes are propagating; verify advancing
tracked votes across both independent relay paths.

## Pre-stage and fail over to a backup

The backup profile contains `pause-on-startup = true`. This pauses K1 block
production only; it does not make sharing a BLS key safe.

1. Generate a different, never-used BLS key on the backup host.
2. Configure only the backup with that key and its own local finalizer directory.
3. Start and sync the backup with production paused.
4. Register its key with `regfinkey`; because another key is active, the new
   key remains inactive.
5. Confirm it exists in `finkeys` without replacing `active_key_id`.
6. Test the complete handoff on testnet.

For failover, activate the backup BLS key and wait until it is in the active
native policy with advancing tracked votes. Then stop the primary and positively
confirm it is down. Remove `pause-on-startup = true` from the backup, restart it,
and verify the exclusive K1 handoff. Never run the same K1 key on two unpaused
producers and never copy the primary's `safety.dat` to the backup.

## Rotate a key

For a same-host rotation, generate a never-used key on that host, load both old
and new BLS providers there, restart, sync, and register the new key. Then
activate it. For a host migration, never copy the old key or safety state; use
the pre-staged backup/new-key procedure above instead.

```bash
export NEW_FINALIZER_PUBLIC_KEY=<PUB_BLS_NEW_KEY>

cleos -u "$RPC" push action eosio actfinkey \
  "$(jq -nc \
    --arg name "$BP_ACCOUNT" \
    --arg key "$NEW_FINALIZER_PUBLIC_KEY" \
    '{finalizer_name:$name,finalizer_key:$key}')" \
  -p "$BP_ACCOUNT@active"
```

Do not stop at transaction inclusion or the `finalizers` table update. Re-run
`get finalizer_info` until the new key moves through any pending policy into the
active policy and its tracked votes advance.

Only then delete the old inactive registration:

```bash
export OLD_FINALIZER_PUBLIC_KEY=<PUB_BLS_OLD_KEY>

cleos -u "$RPC" push action eosio delfinkey \
  "$(jq -nc \
    --arg name "$BP_ACCOUNT" \
    --arg key "$OLD_FINALIZER_PUBLIC_KEY" \
    '{finalizer_name:$name,finalizer_key:$key}')" \
  -p "$BP_ACCOUNT@active"
```

Remove the retired private provider when operationally safe. Retain/quarantine
its logs and safety state for incident review; never reuse the old key.

## Recover from missing or uncertain safety state

If `safety.dat` is missing, corrupt, rolled back, or uncertain for a BLS key
that may have voted:

1. Stop the affected `nodeos` immediately.
2. Do not restart that BLS key.
3. Quarantine its directory; do not copy it elsewhere.
4. Configure a never-used BLS key with a fresh local finalizer directory.
5. Register if necessary, activate it, and wait for native-policy membership
   and advancing tracked votes.
6. Restore chain state from a trusted snapshot if needed, without restoring old
   finalizer safety state.
7. Delete the retired registration only after the replacement is active.

A private-key backup alone is not sufficient recovery state.

## Monitoring and decommissioning

Alert on process restarts, unexpected versions, stale head/LIB, missing policy
membership, non-advancing votes, production pauses, relay loss, missed blocks,
clock drift, finalizer-directory errors, and unexpected finalizer-key actions.

To decommission, continue voting until the BP is absent from both the producer
schedule and active native policy. Confirm with `get finalizer_info`, delete only
inactive registered keys, and securely retire local providers and safety state.
Do not unregister a scheduled producer and immediately delete its current key.
