from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch


PROJECT_ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = PROJECT_ROOT / "scripts"
sys.path.insert(0, str(SCRIPTS))

import hashed_cmacs
import batch_cmacs
import candid_values
import setup_route


class NfcScriptTests(unittest.TestCase):
    def test_item_candid_argument_escapes_operator_text(self):
        argument = candid_values.build_item_argument(
            ['torse "helo"', r"/images\\torse.webp", "", "ligne 1\nligne 2", "Unique"],
            [('taille "EU"', r"M\\L")],
        )
        self.assertEqual(
            argument,
            '("torse \\"helo\\"", "/images\\\\\\\\torse.webp", "", '
            '"ligne 1\\nligne 2", "Unique", vec {record {"taille \\"EU\\""; "M\\\\\\\\L"}})',
        )

    def test_nat_result_is_parsed_as_json_not_first_number(self):
        self.assertEqual(candid_values.parse_nat_json('"42"'), 42)
        self.assertEqual(candid_values.parse_nat_json("42"), 42)
        for invalid in ('"Item 42"', '{"id":"42"}', "true", "-1"):
            with self.assertRaises(ValueError):
                candid_values.parse_nat_json(invalid)

    def test_make_refuses_implicit_collection_and_item(self):
        result = subprocess.run(
            [
                "make",
                "--no-print-directory",
                "nfc-plan",
                "NFC_COLLECTION=",
                "NFC_ITEM_ID=",
            ],
            cwd=PROJECT_ROOT,
            text=True,
            capture_output=True,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("NFC_COLLECTION is required", result.stdout + result.stderr)

    def test_make_nfc_guards_do_not_require_env_or_invoke_dfx(self):
        environment = os.environ.copy()
        environment["PATH"] = "/usr/bin:/bin"
        result = subprocess.run(
            [
                "/usr/bin/make",
                "--no-print-directory",
                "-f",
                str(PROJECT_ROOT / "Makefile"),
                "nfc-plan",
                "NFC_COLLECTION=",
                "NFC_ITEM_ID=",
            ],
            cwd=PROJECT_ROOT.parent,
            env=environment,
            text=True,
            capture_output=True,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("NFC_COLLECTION is required", result.stdout + result.stderr)
        self.assertNotIn("dfx:", result.stdout + result.stderr)
        self.assertNotIn(".env:", result.stdout + result.stderr)

    def test_live_principal_pin_is_not_applied_to_local_plan(self):
        local = subprocess.run(
            [
                "make",
                "--no-print-directory",
                "-n",
                "nfc-plan",
                "NFC_COLLECTION=collection_bleu",
                "NFC_ITEM_ID=0",
            ],
            cwd=PROJECT_ROOT,
            text=True,
            capture_output=True,
            check=True,
        ).stdout
        self.assertIn("--network local", local)
        self.assertNotIn("--expected-canister-id", local)

        live = subprocess.run(
            [
                "make",
                "--no-print-directory",
                "-n",
                "nfc-plan",
                "NFC_COLLECTION=collection_bleu",
                "NFC_ITEM_ID=0",
                "NFC_NETWORK=ic",
            ],
            cwd=PROJECT_ROOT,
            text=True,
            capture_output=True,
            check=True,
        ).stdout
        self.assertIn(
            "--expected-canister-id ubnuj-uyaaa-aaaak-qudbq-cai",
            live,
        )

    def test_make_passes_an_explicit_key_mode(self):
        command = subprocess.run(
            [
                "make",
                "--no-print-directory",
                "-n",
                "nfc-program",
                "NFC_COLLECTION=collection_bleu",
                "NFC_ITEM_ID=0",
                "NFC_KEY_MODE=random",
            ],
            cwd=PROJECT_ROOT,
            text=True,
            capture_output=True,
            check=True,
        ).stdout
        self.assertIn("--key-mode random", command)
        self.assertNotIn("--random-key", command)

    def test_legacy_make_random_key_variable_stays_compatible(self):
        base_command = [
            "make",
            "--no-print-directory",
            "-n",
            "nfc-program",
            "NFC_COLLECTION=collection_bleu",
            "NFC_ITEM_ID=0",
        ]
        for legacy_value, expected_mode in (("1", "random"), ("0", "zero")):
            command = subprocess.run(
                base_command + [f"NFC_RANDOM_KEY={legacy_value}"],
                cwd=PROJECT_ROOT,
                text=True,
                capture_output=True,
                check=True,
            ).stdout
            self.assertIn(f"--key-mode {expected_mode}", command)

        invalid = subprocess.run(
            base_command + ["NFC_RANDOM_KEY=typo"],
            cwd=PROJECT_ROOT,
            text=True,
            capture_output=True,
            check=True,
        ).stdout
        self.assertIn("--key-mode invalid", invalid)

    def test_random_key_file_contains_item_mapping_and_is_private(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            key_path = setup_route.save_random_key(
                "A1" * 16,
                "collection_bleu",
                "ubnuj-uyaaa-aaaak-qudbq-cai",
                "ic",
                7,
                "Item Bleu 7",
                "04958CAA5E5E80",
                "nfc/item/7",
                Path(temporary_directory),
            )
            record = json.loads(key_path.read_text(encoding="utf-8"))

            self.assertEqual(key_path.name, "collection_bleu-item-7-04958CAA5E5E80.key")
            self.assertEqual(key_path.stat().st_mode & 0o777, 0o600)
            self.assertEqual(record["aes_key_0_hex"], "A1" * 16)
            self.assertEqual(record["collection_alias"], "collection_bleu")
            self.assertEqual(
                record["collection_principal"], "ubnuj-uyaaa-aaaak-qudbq-cai"
            )
            self.assertEqual(record["item_id"], 7)
            self.assertEqual(record["item_name"], "Item Bleu 7")
            self.assertEqual(record["tag_uid"], "04958CAA5E5E80")
            self.assertEqual(record["nfc_route"], "/nfc/item/7")

            with self.assertRaisesRegex(setup_route.EnrollmentError, "already exists"):
                setup_route.save_random_key(
                    "B2" * 16,
                    "collection_bleu",
                    "ubnuj-uyaaa-aaaak-qudbq-cai",
                    "ic",
                    7,
                    "Item Bleu 7",
                    "04958CAA5E5E80",
                    "nfc/item/7",
                    Path(temporary_directory),
                )

    def test_key_mode_is_explicit_and_legacy_random_stays_compatible(self):
        self.assertEqual(setup_route.requested_key_mode("random", False), "random")
        self.assertEqual(setup_route.requested_key_mode("zero", False), "zero")
        self.assertEqual(setup_route.requested_key_mode(None, True), "random")
        with self.assertRaisesRegex(setup_route.EnrollmentError, "cannot be combined"):
            setup_route.requested_key_mode("zero", True)

    def test_interactive_key_mode_offers_both_choices(self):
        with patch("builtins.input", return_value=""):
            self.assertEqual(setup_route.prompt_key_mode(), "random")
        with patch("builtins.input", return_value="1"):
            self.assertEqual(setup_route.prompt_key_mode(), "random")
        with patch("builtins.input", return_value="2"):
            self.assertEqual(setup_route.prompt_key_mode(), "zero")

    def test_route_normalization_matches_collection_canonical_form(self):
        self.assertEqual(setup_route.normalize_route(" /nfc/item/7/ "), "nfc/item/7")
        self.assertEqual(batch_cmacs.normalize_route(" /nfc/item/7/ "), "nfc/item/7")
        with self.assertRaises(setup_route.EnrollmentError):
            setup_route.normalize_route("nfc//item/7")
        with self.assertRaises(ValueError):
            batch_cmacs.normalize_route("nfc//item/7")
        with self.assertRaises(setup_route.EnrollmentError):
            setup_route.normalize_route("nfc/item/../7")
        with self.assertRaises(ValueError):
            batch_cmacs.normalize_route("nfc/item/../7")
        with self.assertRaises(setup_route.EnrollmentError):
            setup_route.normalize_route("nfc/item/./7")
        with self.assertRaises(ValueError):
            batch_cmacs.normalize_route("nfc/item/./7")

    def test_knitwork_v1_route_and_item_parameter_are_not_operator_choices(self):
        setup_route.validate_knitwork_binding(7, "nfc/item/7", ("item_id", "7"))
        with self.assertRaisesRegex(setup_route.EnrollmentError, "requires route"):
            setup_route.validate_knitwork_binding(7, "nfc/item/8", ("item_id", "7"))
        with self.assertRaisesRegex(
            setup_route.EnrollmentError, "requires the signed parameter"
        ):
            setup_route.validate_knitwork_binding(7, "nfc/item/7", ("item_id", "8"))

    def test_live_collection_aliases_resolve_to_the_expected_canisters(self) -> None:
        expected = {
            "collection_monayolla": "4623w-oqaaa-aaaak-qtrjq-cai",
            "collection_bleu": "ubnuj-uyaaa-aaaak-qudbq-cai",
            "collection_heloise": "jmp6g-oqaaa-aaaak-qug3q-cai",
        }
        dfx = json.loads((PROJECT_ROOT / "dfx.json").read_text())
        canister_ids = json.loads((PROJECT_ROOT / "canister_ids.json").read_text())
        makefile = (PROJECT_ROOT / "Makefile").read_text()

        for alias, principal in expected.items():
            self.assertEqual(dfx["canisters"][alias]["main"], "src/main.mo")
            self.assertEqual(canister_ids[alias]["ic"], principal)
            self.assertIn(
                f"NFC_EXPECTED_CANISTER_ID_{alias} := {principal}",
                makefile,
            )

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
