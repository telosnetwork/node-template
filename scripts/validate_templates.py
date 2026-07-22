#!/usr/bin/env python3
"""Validate security and Savanna invariants in node-template profiles."""

from __future__ import annotations

import json
from pathlib import Path
from typing import Dict, List, Set

from peer_utils import validate_endpoint


ROOT = Path(__file__).resolve().parents[1]
CHAIN_IDS = {
    "mainnet": "4667b205c6838ef70ff7988f6e8257e8be0e1284a2f59699054a018f743b1d11",
    "testnet": "1eaa0824707c8c16bd25145493bf062aecddfeb56c736f6ba6397f3195f33c9f",
}


class ValidationError(RuntimeError):
    pass


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValidationError(message)


def settings(path: Path) -> Dict[str, List[str]]:
    result: Dict[str, List[str]] = {}
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        require("=" in line, f"{path}: invalid setting line: {raw_line!r}")
        key, value = (part.strip() for part in line.split("=", 1))
        result.setdefault(key, []).append(value)
    return result


def one(path: Path, config: Dict[str, List[str]], key: str) -> str:
    values = config.get(key, [])
    require(len(values) == 1, f"{path}: expected one {key}, got {values}")
    return values[0]


def absent(path: Path, config: Dict[str, List[str]], *keys: str) -> None:
    for key in keys:
        require(key not in config, f"{path}: unsafe/unexpected setting present: {key}")


def require_plugins(path: Path, config: Dict[str, List[str]], expected: Set[str]) -> None:
    plugins = set(config.get("plugin", []))
    missing = expected - plugins
    require(not missing, f"{path}: missing required plugins: {sorted(missing)}")


def require_loopback(path: Path, config: Dict[str, List[str]], key: str) -> None:
    endpoint = one(path, config, key)
    require(
        endpoint.startswith("127.0.0.1:") or endpoint.startswith("[::1]:"),
        f"{path}: {key} must bind to loopback, got {endpoint}",
    )


def common_security(path: Path, config: Dict[str, List[str]]) -> None:
    text = path.read_text(encoding="utf-8")
    for forbidden in (
        "access-control-allow-origin",
        "access-control-allow-headers",
        "chain-id",
        "contracts-console",
        "enable-stale-production",
        "p2p-max-nodes-per-host",
        "trace-history-debug-mode",
        "verbose-http-errors",
        "wasm-runtime",
    ):
        require(forbidden not in config, f"{path}: forbidden production default: {forbidden}")
    require("EOS" not in text, f"{path}: legacy EOS-format placeholder found")
    require_loopback(path, config, "http-server-address")
    require(
        one(path, config, "chain-state-db-size-mb") == "32768",
        f"{path}: chain-state database must use the reviewed 32768 MiB baseline",
    )
    protocol_features = one(path, config, "protocol-features-dir")
    prefix = "/var/lib/telos/"
    suffix = "/protocol_features"
    require(
        protocol_features.startswith(prefix) and protocol_features.endswith(suffix),
        f"{path}: protocol-features-dir must be writable instance data storage",
    )
    instance = protocol_features[len(prefix) : -len(suffix)]
    require(bool(instance) and "/" not in instance, f"{path}: protocol-features-dir must be instance-specific")


def validate_producer(path: Path, backup: bool = False) -> None:
    config = settings(path)
    common_security(path, config)
    require(one(path, config, "vote-threads") == "4", f"{path}: producer must use 4 vote threads")
    require(
        one(path, config, "production-pause-vote-timeout-ms") == "6000",
        f"{path}: production vote-timeout guard must remain 6000ms",
    )
    p2p = one(path, config, "p2p-listen-endpoint")
    require(not p2p.startswith(("0.0.0.0:", "[::]:")), f"{path}: producer P2P must be private")

    finalizers_dir = one(path, config, "finalizers-dir")
    require(
        finalizers_dir.startswith("/var/lib/telos/finalizers/"),
        f"{path}: finalizers-dir must use persistent instance-specific storage",
    )
    require(
        finalizers_dir != "/var/lib/telos/finalizers/",
        f"{path}: finalizers-dir must be instance-specific",
    )
    require("/tmp/" not in finalizers_dir, f"{path}: finalizers-dir cannot be temporary")
    require("producer-name" in config, f"{path}: missing producer-name")

    providers = config.get("signature-provider", [])
    require(len(providers) == 2, f"{path}: expected exactly one K1 and one BLS provider")
    require(any("PUB_K1" in provider for provider in providers), f"{path}: missing K1 provider")
    require(
        any("PUB_BLS" in provider and "=KEY:<PVT_BLS" in provider for provider in providers),
        f"{path}: missing direct KEY BLS provider",
    )
    require_plugins(
        path,
        config,
        {
            "eosio::http_plugin",
            "eosio::chain_plugin",
            "eosio::chain_api_plugin",
            "eosio::net_plugin",
            "eosio::producer_plugin",
        },
    )
    if backup:
        require(
            one(path, config, "pause-on-startup") == "true",
            f"{path}: backup must pause block production on startup",
        )
    else:
        require("pause-on-startup" not in config, f"{path}: primary cannot start paused")


def validate_nonproducer(path: Path, role: str, vote_threads: str) -> None:
    config = settings(path)
    common_security(path, config)
    require(
        one(path, config, "vote-threads") == vote_threads,
        f"{path}: unexpected vote-threads for {role}",
    )
    absent(path, config, "producer-name", "signature-provider", "finalizers-dir", "pause-on-startup")
    require(
        "eosio::producer_plugin" not in set(config.get("plugin", [])),
        f"{path}: nonproducer profile loads producer_plugin",
    )

    required = {"eosio::chain_plugin", "eosio::net_plugin"}
    if role in {"api", "ship"}:
        required |= {"eosio::http_plugin", "eosio::chain_api_plugin"}
    if role == "ship":
        required.add("eosio::state_history_plugin")
    require_plugins(path, config, required)

    if role in {"api", "ship"}:
        require(
            one(path, config, "api-accept-transactions") == "false",
            f"{path}: read-only service must reject submitted transactions",
        )
    if role == "ship":
        require(one(path, config, "trace-history") == "true", f"{path}: trace history disabled")
        require(one(path, config, "chain-state-history") == "true", f"{path}: chain history disabled")
        require(one(path, config, "finality-data-history") == "true", f"{path}: finality history disabled")
        require_loopback(path, config, "state-history-endpoint")


def validate_peers(path: Path) -> None:
    endpoints: List[str] = []
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        require(line.startswith("p2p-peer-address = "), f"{path}: invalid line: {line}")
        endpoint = line.split("=", 1)[1].strip()
        try:
            validate_endpoint(endpoint)
        except ValueError as error:
            raise ValidationError(f"{path}: {error}") from error
        endpoints.append(endpoint)
    require(bool(endpoints), f"{path}: no peers")
    require(len(endpoints) == len(set(endpoints)), f"{path}: duplicate endpoints")


def validate_logging() -> None:
    path = ROOT / "logging.json"
    with path.open(encoding="utf-8") as handle:
        logging = json.load(handle)
    appenders = {item["name"]: item for item in logging.get("appenders", [])}
    loggers = {item["name"]: item for item in logging.get("loggers", [])}
    for name in {"default", "net_plugin_impl", "producer_plugin", "vote"}:
        require(name in loggers, f"{path}: missing {name} logger")
    vote = loggers["vote"]
    require(vote.get("enabled") is True, f"{path}: vote logger is disabled")
    require(bool(vote.get("appenders")), f"{path}: vote logger has no appender")
    for name in vote["appenders"]:
        require(name in appenders, f"{path}: vote logger references unknown appender {name}")
        require(appenders[name].get("enabled") is True, f"{path}: vote appender {name} is disabled")


def main() -> None:
    for network, expected in CHAIN_IDS.items():
        actual = (ROOT / network / "chain-id.txt").read_text(encoding="utf-8").strip()
        require(actual == expected, f"{network}: unexpected chain ID {actual}")
        with (ROOT / network / "genesis.json").open(encoding="utf-8") as handle:
            json.load(handle)
        validate_peers(ROOT / network / "peers.ini")

    validate_logging()
    validate_producer(ROOT / "config.ini")
    validate_producer(ROOT / "profiles/producer.ini.example")
    validate_producer(ROOT / "profiles/backup-producer.ini.example", backup=True)
    validate_nonproducer(ROOT / "profiles/vote-relay.ini.example", "vote-relay", "4")
    validate_nonproducer(ROOT / "profiles/api.ini.example", "api", "0")
    validate_nonproducer(ROOT / "profiles/ship.ini.example", "ship", "0")

    service = (ROOT / "systemd/telos-nodeos@.service").read_text(encoding="utf-8")
    require("--config-dir=/etc/telos/%i" in service, "systemd unit lacks instance config path")
    require("--data-dir=/var/lib/telos/%i" in service, "systemd unit lacks instance data path")

    print("template validation passed")


if __name__ == "__main__":
    main()
