# Telos node template files
Examples to simplify running a Telos node.  These examples assume you're running Ubuntu 18.04

## Setup directories
Create a directory to store nodes and binaries in, setup a log directory and set their permissions.  Let's assume your user is named `telos` and you want to store everything in a directory named `/telos`
```shell
sudo mkdir /telos
sudo mkdir /var/log/nodeos
sudo chown telos: /telos
sudo chown telos: /var/log/nodeos
```

## Download this template
To create a new node at /telos/nodes/testnet1:
```shell
mkdir -p /telos/nodes/testnet1
cd /telos/nodes/testnet1
curl -L https://api.github.com/repos/telosnetwork/node-template/tarball/master | tar -xvz --strip=1
```

## Setup peers

Copy the contents of the peers.ini from mainnet/testnet directory into the config.ini from the template, adding/removing peers to suit your region/needs
```shell
echo >> config.ini
echo "#TESTNET PEERS:" >> config.ini
cat testnet/peers.ini >> config.ini
```

## Install eosio binaries (if needed)
Pick a version to download from https://github.com/EOSIO/eos/releases
```shell
wget https://github.com/EOSIO/eos/releases/download/v2.0.6/eosio_2.0.6-1-ubuntu-18.04_amd64.deb
sudo apt install eosio_2.0.6-1-ubuntu-18.04_amd64.deb
```

## Move binaries
Now find where the binaries installed and move them to somewhere that won't be changed when you install the next version, it's likely they are in `/usr/opt/eosio/`, this will allow you to run a different version on this same machine
```shell
mkdir -p /telos/eosio
cp -a /usr/opt/eosio/2.0.6 /telos/eosio/
```

## Set node version
Now you know the path to the binaries, change that in the `node_config` file
```shell
vi /telos/nodes/testnet1/node_config
```
And set the `BUILD_ROOT` variable
```
BUILD_ROOT="/telos/eosio/bin/2.0.6"
```

## Setup config.ini
### Review
Review the config.ini file to get familiar with it, adjust as needed

### Set the ports
Make sure you set the ports to ones that are not already in use on this server by other nodes

## Start the node from genesis to begin the sync
```shell
cd /telos/nodes/testnet1
./start.sh --genesis-json ./testnet/genesis.json
```
