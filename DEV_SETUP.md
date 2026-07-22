# Local development

The production profiles in this repository target existing Telos networks where
Savanna instant finality is already active. They are not a network-bootstrap
tutorial.

For local protocol, system-contract, or finalizer development, use the test
harness and bootstrap procedures from the exact tagged
[TelosZero Core source](https://github.com/telosnetwork/teloszero-core). Those
tests establish the required protocol features, system state, finalizer policy,
and BLS voting conditions; a single `--enable-stale-production` command does not.

`--enable-stale-production` is acceptable only on an isolated local chain that
cannot connect to mainnet or testnet. `start.sh` refuses it by default. To use it
for that isolated purpose, set `ALLOW_STALE_PRODUCTION=true` in `node_config` and
bind all HTTP/P2P listeners to loopback.

The compiled contract artifacts under `contracts/` are retained only for
historical compatibility. They predate the current Telos finalizer actions and
must not be deployed to Telos mainnet, testnet, or a current Savanna test network.
Build identified contract sources reproducibly instead.
