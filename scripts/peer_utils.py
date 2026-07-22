"""Shared validation for P2P endpoint and producer-account input."""

import re


ENDPOINT_RE = re.compile(
    r"^(?:[A-Za-z0-9](?:[A-Za-z0-9.-]{0,251}[A-Za-z0-9])?|"
    r"\[[0-9A-Fa-f:]+\]|(?:\d{1,3}\.){3}\d{1,3}):(\d{1,5})$"
)
OWNER_RE = re.compile(r"^[a-z1-5.]{1,12}$")


def validate_endpoint(endpoint: str) -> int:
    match = ENDPOINT_RE.fullmatch(endpoint)
    if not match:
        raise ValueError(f"invalid P2P endpoint: {endpoint!r}")
    port = int(match.group(1))
    if not 1 <= port <= 65535:
        raise ValueError(f"invalid P2P port in endpoint: {endpoint!r}")
    return port
