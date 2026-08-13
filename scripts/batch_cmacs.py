#!/usr/bin/env python3
"""Upload NTAG CMAC hashes to one explicit Collection canister."""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path
from typing import Sequence


HASH_RE = re.compile(r"^[0-9a-f]{64}$")
UID_RE = re.compile(r"^[0-9A-F]{14}$")
ROUTE_RE = re.compile(r"^[A-Za-z0-9/._~-]+$")


def normalize_route(value: str) -> str:
    route = value.strip().strip("/")
    if not route or not ROUTE_RE.fullmatch(route):
        raise ValueError("route contains unsupported characters")
    if any(segment in {"", ".", ".."} for segment in route.split("/")):
        raise ValueError("route contains an invalid path segment")
    return route


def candid_text(value: str) -> str:
    return json.dumps(value, ensure_ascii=False)


def candid_hashes(values: Sequence[str]) -> str:
    return "vec {" + ";".join(candid_text(value) for value in values) + "}"


def run_dfx(
    project_root: Path,
    network: str,
    identity: str,
    canister: str,
    method: str,
    argument: str,
    *,
    query: bool = False,
) -> str:
    command = [
        "dfx",
        "canister",
        "call",
        "--network",
        network,
        "--identity",
        identity,
        canister,
        method,
        argument,
        "--output",
        "json",
    ]
    if query:
        command.insert(-2, "--query")
    result = subprocess.run(command, cwd=project_root, text=True, capture_output=True)
    if result.returncode != 0:
        detail = result.stderr.strip() or result.stdout.strip()
        raise RuntimeError(f"dfx {method} failed: {detail}")
    return result.stdout.strip()


def read_hashes(path: Path) -> list[str]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise ValueError(f"cannot read CMAC file {path}: {exc}") from exc

    if not isinstance(value, list) or not value:
        raise ValueError("CMAC file must contain a non-empty JSON array")
    if any(not isinstance(entry, str) or not HASH_RE.fullmatch(entry) for entry in value):
        raise ValueError("every CMAC hash must be a lowercase SHA-256 hex digest")
    return value


def query_existing_hashes(
    project_root: Path,
    network: str,
    identity: str,
    canister: str,
    route: str,
    uid: str,
) -> list[str]:
    output = run_dfx(
        project_root,
        network,
        identity,
        canister,
        "get_route_cmacs",
        f"({candid_text(route)}, {candid_text(uid)})",
        query=True,
    )
    try:
        value = json.loads(output)
    except json.JSONDecodeError as exc:
        raise RuntimeError(f"unexpected get_route_cmacs response: {output}") from exc
    if not isinstance(value, list) or any(not isinstance(entry, str) for entry in value):
        raise RuntimeError("unexpected get_route_cmacs response type")
    return value


def upload_hashes(
    project_root: Path,
    network: str,
    identity: str,
    canister: str,
    route: str,
    uid: str,
    desired: list[str],
    batch_size: int,
) -> None:
    existing = query_existing_hashes(project_root, network, identity, canister, route, uid)
    if existing == desired:
        print(f"CMAC table already complete ({len(desired)} hashes).")
        return
    if existing != desired[: len(existing)]:
        raise RuntimeError(
            "existing CMAC table is not a prefix of the requested table; refusing to overwrite scan state"
        )

    offset = len(existing)
    while offset < len(desired):
        batch = desired[offset : offset + batch_size]
        method = "update_route_cmacs" if offset == 0 else "append_route_cmacs"
        argument = (
            f"({candid_text(route)}, {candid_text(uid)}, {candid_hashes(batch)})"
        )
        run_dfx(project_root, network, identity, canister, method, argument)
        offset += len(batch)
        print(f"Uploaded {offset}/{len(desired)} CMAC hashes.")

    verified = query_existing_hashes(project_root, network, identity, canister, route, uid)
    if verified != desired:
        raise RuntimeError("CMAC table verification failed after upload")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Upload CMAC hashes to one Collection")
    parser.add_argument("cmacs_file", type=Path)
    parser.add_argument("--canister", required=True, help="Explicit dfx canister alias")
    parser.add_argument("--route", required=True, help="Normalized route without query parameters")
    parser.add_argument("--uid", required=True, help="14-character NTAG UID")
    parser.add_argument("--network", default="local")
    parser.add_argument("--identity", default="raygen")
    parser.add_argument("--batch-size", type=int, default=1_000)
    parser.add_argument("--execute", action="store_true")
    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    project_root = Path(__file__).resolve().parents[1]
    try:
        route = normalize_route(args.route)
    except ValueError as exc:
        parser.error(str(exc))
    uid = args.uid.strip().upper()

    if not UID_RE.fullmatch(uid):
        parser.error("UID must contain exactly 14 hexadecimal characters")
    if args.batch_size <= 0:
        parser.error("batch-size must be greater than zero")

    try:
        hashes = read_hashes(args.cmacs_file)
    except ValueError as exc:
        parser.error(str(exc))

    print(f"Collection : {args.canister}")
    print(f"Network    : {args.network}")
    print(f"Identity   : {args.identity}")
    print(f"Route      : /{route}")
    print(f"Tag UID    : {uid}")
    print(f"CMAC count : {len(hashes)}")

    if not args.execute:
        print("PLAN ONLY — no on-chain state was changed.")
        return 0

    try:
        upload_hashes(
            project_root,
            args.network,
            args.identity,
            args.canister,
            route,
            uid,
            hashes,
            args.batch_size,
        )
    except RuntimeError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1

    print("CMAC upload verified.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
