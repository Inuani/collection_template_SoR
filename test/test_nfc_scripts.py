from __future__ import annotations

import sys
import unittest
from pathlib import Path


SCRIPTS = Path(__file__).resolve().parents[1] / "scripts"
sys.path.insert(0, str(SCRIPTS))

import hashed_cmacs
import setup_route


class NfcScriptTests(unittest.TestCase):
    def test_counter_crypto_encoding_is_little_endian(self) -> None:
        self.assertEqual(hashed_cmacs.counter_to_little_endian_hex(1), "010000")
        self.assertEqual(hashed_cmacs.counter_to_little_endian_hex(256), "000100")

    def test_generator_returns_the_requested_number_of_hashes(self) -> None:
        values = hashed_cmacs.generate_hashes(
            3,
            "04958CAA5E5E80",
            "00000000000000000000000000000000",
        )
        self.assertEqual(len(values), 3)
        self.assertTrue(all(len(value) == 64 for value in values))

    def test_static_item_parameter_precedes_dynamic_fields_and_cmac_is_last(self) -> None:
        formed = setup_route.form_sdm_payload(
            "https://ubnuj-uyaaa-aaaak-qudbq-cai.raw.icp0.io/nfc/item/0",
            ("item_id", "0"),
        )
        payload = bytes(formed["payload"])
        body = payload[7:]

        self.assertIn(b"?item_id=0&uid=", body)
        self.assertLess(body.index(b"item_id=0"), body.index(b"uid="))
        self.assertLess(body.index(b"uid="), body.index(b"ctr="))
        self.assertLess(body.index(b"ctr="), body.index(b"cmac="))
        self.assertEqual(payload[formed["uid_offset"] : formed["uid_offset"] + 14], b"\0" * 14)
        self.assertEqual(
            payload[formed["counter_offset"] : formed["counter_offset"] + 6],
            b"\0" * 6,
        )
        self.assertEqual(payload[formed["mac_offset"] :], b"\0" * 16)


if __name__ == "__main__":
    unittest.main()
