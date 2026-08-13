#!/usr/bin/env python3
"""Generate the SHA-256 hashes used to validate NTAG 424 DNA SDM MACs."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

from cryptography.hazmat.primitives import cmac
from cryptography.hazmat.primitives.ciphers import algorithms


def _decode_hex(value: str, *, expected_bytes: int, label: str) -> bytes:
    if len(value) != expected_bytes * 2:
        raise ValueError(f"{label} must contain exactly {expected_bytes * 2} hex characters")
    try:
        return bytes.fromhex(value)
    except ValueError as exc:
        raise ValueError(f"{label} must be hexadecimal") from exc


def counter_to_little_endian_hex(counter: int) -> str:
    if not 1 <= counter <= 0xFFFFFF:
        raise ValueError("counter must be between 1 and 16,777,215")
    return counter.to_bytes(3, "little").hex().upper()


def sdm_mac(counter: int, uid: str, key: str) -> str:
    uid_bytes = _decode_hex(uid, expected_bytes=7, label="UID")
    key_bytes = _decode_hex(key, expected_bytes=16, label="AES key")
    counter_bytes = counter.to_bytes(3, "little")

    session_derivation = bytes.fromhex("3CC300010080") + uid_bytes + counter_bytes
    session_cmac = cmac.CMAC(algorithms.AES(key_bytes))
    session_cmac.update(session_derivation)
    session_key = session_cmac.finalize()

    full_cmac = cmac.CMAC(algorithms.AES(session_key))
    full_cmac.update(b"")
    digest = full_cmac.finalize()

    # NTAG 424 DNA returns the odd bytes of the full CMAC.
    return digest[1::2].hex().upper()


def generate_hashes(count: int, uid: str, key: str) -> list[str]:
    if count <= 0:
        raise ValueError("count must be greater than zero")
    if count > 0xFFFFFF:
        raise ValueError("count exceeds the 24-bit NTAG counter")

    return [
        hashlib.sha256(sdm_mac(counter, uid, key).encode("ascii")).hexdigest()
        for counter in range(1, count + 1)
    ]


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate hashed NTAG 424 SDM MACs")
    parser.add_argument("-k", "--key", required=True, help="16-byte AES key as 32 hex characters")
    parser.add_argument("-u", "--uid", required=True, help="7-byte tag UID as 14 hex characters")
    parser.add_argument("-c", "--count", type=int, default=42_000)
    parser.add_argument("-o", "--output", type=Path, required=True)
    args = parser.parse_args()

    try:
        hashes = generate_hashes(args.count, args.uid.upper(), args.key.upper())
    except ValueError as exc:
        parser.error(str(exc))

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(hashes), encoding="utf-8")
    print(f"Generated {len(hashes)} hashes in {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
