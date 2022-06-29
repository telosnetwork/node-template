Set LOCALIZE_LOG=true in node_config and set the nodeos and cleos binaries to be the name of the binary without a specific path:
```
BUILD_ROOT="/path/to/binaries/2.0.4"
CLIENT_BIN="cleos"
NODEOS_BIN="nodeos"
CPU="0"
LOCALIZE_LOG=true
```
Don't bother with the directories setup, with the log localized, the whole node will be contained within this `node-template` repo's directory


To reset the node, either remove or rename the `data` directory

First, generate a key to use for this local network's `eosio` super-user account
```bash
cleos create key --to-console
```

Create a dev wallet, save this password:
```bash
cleos wallet create -n dev --to-console
```

Import the key into cleos, paste the private key when prompted:
```bash
cleos wallet import -n dev
```

Then generate a new `genesis.json` file
```bash
nodeos --extract-genesis-json genesis.json
```

Edit the genesis.json and set the `initial_key` to the key that you generated above for `eosio`:
```bash
vi genesis.json
```

Edit the config.ini to configure this node to produce blocks as `eosio`
```bash
vi config.ini
```
and change these two, seting the key to be the one you generated above
```
producer-name = eosio
signature-provider = EOS6nrS...=KEY:5HxQ...
```

Start the node for the first time
```bash
./start.sh --enable-stale-production --genesis-json genesis.json
```

Observe it is now producing blocks, change the name of the log file depending if you renamed this repo directory
```bash
tail -f node-template.log
```

Stop the node
```bash
./stop.sh
```

Start the node in dev mode, this is how you will start the node from now on:
```bash
./start.sh --enable-stale-production
```
