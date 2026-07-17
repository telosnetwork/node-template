import importlib.util
import sys
import unittest
from datetime import datetime, timezone
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
SPEC = importlib.util.spec_from_file_location(
    "update_peers", ROOT / "scripts" / "update-peers.py"
)
assert SPEC is not None and SPEC.loader is not None
update_peers = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(update_peers)


class UpdatePeersTests(unittest.TestCase):
    def document(self, owner="producer1111", endpoint="peer.example:9876"):
        return {
            "generatedAt": datetime.now(timezone.utc).isoformat(),
            "producers": [
                {
                    "owner": owner,
                    "p2pEndpointChecks": [
                        {"endpoint": endpoint, "verified": True}
                    ],
                }
            ],
        }

    def test_collects_verified_endpoint(self):
        endpoints = update_peers.collect_verified(self.document(), "p2pEndpointChecks")
        self.assertEqual(endpoints, {"peer.example:9876": {"producer1111"}})

    def test_rejects_owner_comment_injection(self):
        with self.assertRaisesRegex(ValueError, "invalid producer account"):
            update_peers.collect_verified(
                self.document(owner="safeowner\nplugin = eosio::producer_plugin"),
                "p2pEndpointChecks",
            )

    def test_rejects_endpoint_injection(self):
        with self.assertRaisesRegex(ValueError, "invalid P2P endpoint"):
            update_peers.collect_verified(
                self.document(endpoint="peer.example:9876\nproducer-name = attacker"),
                "p2pEndpointChecks",
            )

    def test_rejects_timestamp_comment_injection(self):
        with self.assertRaisesRegex(ValueError, "invalid generatedAt"):
            update_peers.validate_generated_at(
                "2026-07-16T00:00:00+00:00\nplugin = malicious", 48, False
            )

    def test_rejects_stale_timestamp(self):
        with self.assertRaisesRegex(ValueError, "hours old"):
            update_peers.validate_generated_at("2020-01-01T00:00:00+00:00", 48, False)

    def test_rejects_large_peer_drop(self):
        with self.assertRaisesRegex(ValueError, "refusing large mainnet peer drop"):
            update_peers.guard_peer_count("mainnet", 20, 9, False)

    def test_labels_local_source_without_injecting_path(self):
        self.assertEqual(
            update_peers.source_label("/tmp/operator-input.json"),
            "a locally supplied validator JSON file",
        )


if __name__ == "__main__":
    unittest.main()
