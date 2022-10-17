# Telos node template files
Examples to simplify running a Telos node.  These examples assume you're running Ubuntu 18.04

For a local dev node, check out the [Dev setup](DEV_SETUP.md)

## Setup directories
Create a directory to store nodes and binaries in, setup a log directory and set their permissions.  Let's assume your user is named `telos` and you want to store everything in a directory named `/telos`

Note, if you wish to have the node keep it's logs in it's own node directory, you can skip the creation and chown of the /var/log/nodeos directory
```shell
sudo mkdir /telos
sudo mkdir /var/log/nodeos
sudo chown telos: /telos
sudo chown telos: /var/log/nodeos
```

## Install packages
```
sudo apt install schedtool
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

Pick a version to download from https://github.com/EOSIO/eos/releases
You can find more up to date peers via the [EOS Nation](https://eosnation.io/) BP validator tool for either [testnet](https://validate.eosnation.io/telostest/) or [mainnet](https://validate.eosnation.io/telos/)

## Install latest Leap AntelopeIO binaries (if needed)
Pick a version to download from https://github.com/AntelopeIO/leap/releases

Select a stable release, likely the `latest` tagged one (not RC/Release Candidate) which is built for your OS Version
```shell
wget https://github.com/AntelopeIO/leap/releases/download/v3.1.2/leap-3.1.2-ubuntu22.04-x86_64.deb
sudo apt install ./leap-3.1.2-ubuntu22.04-x86_64.deb
```

## Move binaries
Now find where the binaries installed and move the nodeos binary to somewhere that won't be changed when you install the next version, it's likely they are in `/usr/bin`, this will allow you to run a different version on this same machine

The strategy here is that in the `/telos/leap` directory you have a directory for each version you may want to run on this machine, inside each directory is the `nodeos` binary matching that version.  To update nodes you'll just have to change the version in the specific node's `node_config` file and restart it, as well as take any other measures needed for that version upgrade (reindex, etc..)

Note, installing the `.deb` file will put all the binaries (`nodeos`,`cleos`,`keosd`) in your path, if you simply use the binary name (e.g. `nodeos` without a path) it will use the most recently installed version.  For the purposes of running a node, the only binary which needs to be copied and versioned in this way would be `nodeos`
```shell
mkdir -p /telos/leap/3.1.2
cp -a /usr/bin/nodeos /telos/leap/3.1.2/
```

## Setup node_config
### For each of these settings, you'll make changes in the `node_config` file
```shell
vi /telos/nodes/testnet1/node_config
```

### Set node version
Now you know the path to the binaries, change that in the `node_config` file, set the `BUILD_ROOT` variable
```
BUILD_ROOT="/telos/leap/3.1.2"
```

### Distribute CPU load
The `start.sh` script will pin the `nodeos` process to a specific CPU core, this optimizes performance.  If you are running multiple nodes on the same host and do not change this setting you will have all nodes fighting over the same CPU core so you should make sure each node has a different value set.

To determine how many cores you have, run `cat /proc/cpuinfo | grep processor` and then pick one that's not already configured on other nodes and set it in the `node_config` file:
```
CPU="0"
```

### Optional: Configure to write logs locally to the node's directory if you prefer instead of the system-wide `/var/log/nodeos` path as mentioned above
Set the `LOCALIZE_LOG` flag to true in the `node_config` file
```
LOCALIZE_LOG=true
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

## Configure public access
This assumes the node operator has reasonable system administration skills, which should be expected of a Telos block producer.
### P2P
Point DNS at the server and expose the p2p port (`p2p-listen-endpoint`), this is your seed/p2p endpoint and is only tcp, it does not require anything in front of it.  If you wish you can use a tcp load balancer such as haproxy in front of the p2p, then you'll point the DNS at the load balancer.
### API
Install something like nginx or haproxy and point DNS at it for your API endpoint, configure it for SSL.

A popular option is to put nginx in front of it using auto-renewing and free SSL certs from Let's Encrypt - https://www.digitalocean.com/community/tutorials/how-to-secure-nginx-with-let-s-encrypt-on-ubuntu-18-04

You'll want to configure nginx in this case for a reverse proxy, and point it at your `http-server-address`
