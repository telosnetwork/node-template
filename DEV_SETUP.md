# Local Dev Network Tutorial


__Clone the node template repo at the root of this directory and follow along to learn how to create a local EOSIO developer network.__


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

First, generate a key pair to use for this local network's `eosio` super-user account. **NOTE** SAVE THESE KEYS for creating system accounts at bottom
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
Also, uncomment the producer API plugin
```
plugin = eosio::producer_api_plugin
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
## Create system accounts
Now make sure that you have your key pair that we initialized in the beginning of tutorial. 

If you want to double check your using the right key in your wallet simply run the command:
```bash
cleos wallet private_keys -n <YourWalletName>
```


```bash
cleos create account eosio eosio.token <OwnerKey> <ActiveKey>
cleos create account eosio eosio.bpay <OwnerKey> <ActiveKey>
cleos create account eosio eosio.vpay <OwnerKey> <ActiveKey>
cleos create account eosio eosio.msig <OwnerKey> <ActiveKey>
cleos create account eosio eosio.names <OwnerKey> <ActiveKey>
cleos create account eosio eosio.ram <OwnerKey> <ActiveKey>
cleos create account eosio eosio.ramfee <OwnerKey> <ActiveKey>
cleos create account eosio eosio.rex <OwnerKey> <ActiveKey>
cleos create account eosio eosio.saving <OwnerKey> <ActiveKey>
cleos create account eosio eosio.stake <OwnerKey> <ActiveKey>
```

## Deploy the token contract

NOTE: Can only create accounts using this command before the system contract is deployed, once it's deployed you must use `cleos system newaccount ...`
```bash
cleos create account eosio eosio.token <OwnerKey> <ActiveKey>
cd contracts/eosio.token
cleos set contract eosio.token . ./eosio.token.wasm ./eosio.token.abi
cleos push action eosio.token create '["eosio","100000000.0000 TLOS"]' -p eosio.token@active
cleos push action eosio.token issue '["eosio","100000000.0000 TLOS","Issue max supply to eosio"]' -p eosio@active
```



## Deploy the system contract
```bash
curl -X POST http://127.0.0.1:8888/v1/producer/schedule_protocol_feature_activations -d '{"protocol_features_to_activate": ["0ec7e080177b2c02b278d5088611686b49d739925a92d9bfcacd7fc6b74053bd"]}' | jq
cd contracts/eosio.system
cleos set contract eosio . ./eosio.system.wasm ./eosio.system.abi
cleos push action eosio init '[0,"4,TLOS"]' -p eosio@active
```
