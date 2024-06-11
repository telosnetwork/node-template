# Node requirements

## Node capabilities/ports
- P2P: The peer-to-peer protocol used for nodes communicating blocks with each other.
- API: Serving the http API, should be put behind nginx/haproxy terminating SSL and available on a public facing DNS record.  If the node is started from a snapshot, it will not be able to satisfy /v1/chain/get_block requests from prior to the snapshot.
- State history: This provides a websocket stream used for getting all chain history in binary form, it is typically combined with other tools that are ABI aware and can do the decoding.  Similar to http api, if started from a snapshot, the node will not be able to provide any history from prior to that snapshot block.

## Producer nodes
A producer node should not be exposed to the public internet and for this reason can be started from a snapshot without any significant downsides.  It should be connected via P2P with other nodes for the validator and have a curated list of other nearby/reliable validator's public P2P endpoints.

## Multiple nodes per host
It is not uncommon to run more than one node on a single physical host.  Take care to not create port conflicts or the nodes will not start.  Consider the resource utilization numbers below when deciding how best to organize nodes, leaving plenty of room for growth.

## Resource utilization
Node usage can grow over time. Here are the current numbers for mainnet usage as of 1/16/2023:

### CPU
Nodeos is generally a single-threaded process, with multithreading only for signature verification.  It's best to run nodeos on a high-frequency CPU (over 4GHz turbo boost, with optimizations as described [in this article](https://github.com/poplexity/bp-performance))

### Disk
It is critical that state is stored on fast IO hardware (SSD/NVMe) but blocks and state-history are acceptable to run on slower HDD drives.  There is a default setting that will shut the node down gracefully when it's storage reaches 90% capacity.  One of the most common contributors to disk usage is the log file, so without logrotate configured it's best to keep an eye on the log file and `echo "" > nodeos.log` when disk capacity becomes a concern.
```text
State: 3.4G (all nodes will have this)
Blocks: 262G (full blocks since genesis, this would start at 0 if you start from a snapshot)
State history: 750G (full state-history since genesis, this would start at 0 if you start from a snapshot)
```

### Ram
A single node uses 2.4G of RAM currently this can at any time jump up to the on-chain max which is 36G however that would mean that all RAM would have been bought AND used by accounts which is highly unlikely as the price of RAM approaches infinity as the supply approaches 0 (bancor algorithm).
