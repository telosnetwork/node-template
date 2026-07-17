#!/usr/bin/env python3
"""Refresh peer files from the Telos validator's verified endpoint data."""

from __future__ import annotations

import argparse
import json
import math
import os
import tempfile
import urllib.request
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Mapping, MutableMapping, Set

from peer_utils import OWNER_RE, validate_endpoint


DEFAULT_SOURCE = "https://validators.telos.net/validation/latest.json"


def load_document(source: str) -> Mapping[str, object]:
    if source.startswith("https://"):
        request = urllib.request.Request(
            source, headers={"User-Agent": "telos-node-template-peer-updater/1"}
        )
        with urllib.request.urlopen(request, timeout=30) as response:
            return json.load(response)
    if "://" in source:
        raise ValueError("peer data URLs must use HTTPS")
    with open(source, "r", encoding="utf-8") as handle:
        return json.load(handle)


def collect_verified(
    document: Mapping[str, object], field: str
) -> MutableMapping[str, Set[str]]:
    endpoints: MutableMapping[str, Set[str]] = defaultdict(set)
    producers = document.get("producers")
    if not isinstance(producers, list):
        raise ValueError("validator document has no producers array")

    for producer in producers:
        if not isinstance(producer, dict):
            continue
        owner = producer.get("owner")
        if not isinstance(owner, str) or not OWNER_RE.fullmatch(owner):
            raise ValueError(f"invalid producer account name: {owner!r}")
        checks = producer.get(field, [])
        if not isinstance(checks, list):
            continue
        for check in checks:
            if not isinstance(check, dict) or check.get("verified") is not True:
                continue
            endpoint = check.get("endpoint")
            if not isinstance(endpoint, str):
                continue
            endpoint = endpoint.strip()
            validate_endpoint(endpoint)
            endpoints[endpoint].add(owner)

    if not endpoints:
        raise ValueError(f"validator document returned no verified endpoints for {field}")
    return endpoints


def render(
    network: str,
    generated_at: str,
    endpoints: Mapping[str, Set[str]],
    source_label: str,
) -> str:
    lines = [
        f"# {network.capitalize()} peers generated from {source_label}",
        f"# Validator data generated at: {generated_at}",
        "# Only endpoints marked verified by the validator are included.",
        "# Curate for geographic/operator diversity and monitor continuously.",
        "# Private producers should peer with operator-controlled vote relays,",
        "# not directly with this public list.",
        "",
    ]
    for endpoint in sorted(endpoints, key=lambda item: (sorted(endpoints[item]), item)):
        owners = ", ".join(sorted(endpoints[endpoint]))
        lines.append(f"# {owners}")
        lines.append(f"p2p-peer-address = {endpoint}")
    return "\n".join(lines) + "\n"


def atomic_write(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=str(path.parent))
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            handle.write(content)
        os.replace(temporary, path)
    except BaseException:
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass
        raise


def validate_generated_at(value: object, max_age_hours: float, allow_stale: bool) -> str:
    if not isinstance(value, str) or not value or "\n" in value or "\r" in value:
        raise ValueError("validator document has an invalid generatedAt timestamp")
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError as error:
        raise ValueError("validator document has an invalid generatedAt timestamp") from error
    if parsed.tzinfo is None:
        raise ValueError("validator generatedAt timestamp has no timezone")
    age_hours = (datetime.now(timezone.utc) - parsed.astimezone(timezone.utc)).total_seconds() / 3600
    if age_hours < -1:
        raise ValueError("validator generatedAt timestamp is unexpectedly in the future")
    if age_hours > max_age_hours and not allow_stale:
        raise ValueError(
            f"validator data is {age_hours:.1f} hours old; use --allow-stale only after review"
        )
    return value


def endpoint_count(content: str) -> int:
    return sum(1 for line in content.splitlines() if line.startswith("p2p-peer-address = "))


def guard_peer_count(
    network: str, old_count: int, new_count: int, allow_large_change: bool
) -> None:
    minimum = max(3, math.ceil(old_count / 2)) if old_count else 3
    if new_count < minimum and not allow_large_change:
        raise ValueError(
            f"refusing large {network} peer drop ({old_count} -> {new_count}); "
            "review and pass --allow-large-change if intentional"
        )


def source_label(source: str) -> str:
    if source == DEFAULT_SOURCE:
        return DEFAULT_SOURCE
    if source.startswith("https://"):
        if "\n" in source or "\r" in source:
            raise ValueError("peer data source contains a line break")
        return source
    return "a locally supplied validator JSON file"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--source",
        default=DEFAULT_SOURCE,
        help="validator JSON URL or local file (default: %(default)s)",
    )
    parser.add_argument(
        "--output-root",
        type=Path,
        default=Path(__file__).resolve().parents[1],
        help="repository root containing mainnet/ and testnet/",
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help="report whether generated files differ without writing them",
    )
    parser.add_argument(
        "--max-age-hours",
        type=float,
        default=48.0,
        help="maximum validator-data age (default: %(default)s)",
    )
    parser.add_argument(
        "--allow-stale",
        action="store_true",
        help="accept validator data older than --max-age-hours after manual review",
    )
    parser.add_argument(
        "--allow-large-change",
        action="store_true",
        help="allow a generated peer list to shrink by more than 50%%",
    )
    args = parser.parse_args()

    if not math.isfinite(args.max_age_hours) or args.max_age_hours <= 0:
        raise ValueError("--max-age-hours must be a positive finite number")

    document = load_document(args.source)
    generated_at = validate_generated_at(
        document.get("generatedAt"), args.max_age_hours, args.allow_stale
    )

    network_fields = {
        "mainnet": "p2pEndpointChecks",
        "testnet": "p2pEndpointChecksTestNet",
    }
    rendered = {}
    for network, field in network_fields.items():
        content = render(
            network,
            generated_at,
            collect_verified(document, field),
            source_label(args.source),
        )
        destination = args.output_root / network / "peers.ini"
        old_content = destination.read_text(encoding="utf-8") if destination.exists() else ""
        old_count = endpoint_count(old_content)
        new_count = endpoint_count(content)
        guard_peer_count(network, old_count, new_count, args.allow_large_change)
        rendered[network] = (destination, old_content, content)

    changed = False
    for network, (destination, old_content, content) in rendered.items():
        if old_content == content:
            print(f"unchanged: {destination}")
            continue
        changed = True
        if args.check:
            print(f"out of date: {destination}")
        else:
            atomic_write(destination, content)
            print(f"updated: {destination}")

    return 1 if args.check and changed else 0


if __name__ == "__main__":
    raise SystemExit(main())
