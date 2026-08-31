#!/usr/bin/env python3
"""Safely enroll an NTAG 424 DNA tag for one explicit Collection route.

The command is a plan-only preflight unless ``--execute`` is supplied.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import secrets
import shutil
import sys
from ctypes import c_ubyte, c_uint, c_uint16, memset, sizeof
from datetime import datetime, timezone
from pathlib import Path

import batch_cmacs
import hashed_cmacs
import icp_cli


CANISTER_RE = re.compile(r"^[a-z0-9][a-z0-9_-]*$")
PARAM_RE = re.compile(r"^[A-Za-z0-9_.~-]+=[A-Za-z0-9_.~-]+$")
ROUTE_RE = re.compile(r"^[A-Za-z0-9._~/-]+$")
DEFAULT_KEY_HEX = "0" * 32
KEY_MODE_RANDOM = "random"
KEY_MODE_ZERO = "zero"
KEY_MODES = (KEY_MODE_RANDOM, KEY_MODE_ZERO)


class EnrollmentError(RuntimeError):
    pass


def normalize_route(value: str) -> str:
    route = value.strip().strip("/")
    if not route or not ROUTE_RE.fullmatch(route):
        raise EnrollmentError(
            "route must use only letters, digits, '/', '.', '_', '~' or '-'"
        )
    if any(segment in {"", ".", ".."} for segment in route.split("/")):
        raise EnrollmentError("route cannot contain '.', '..' or empty path segments")
    return route


def parse_parameter(value: str) -> tuple[str, str]:
    if not PARAM_RE.fullmatch(value):
        raise EnrollmentError("parameter must use the form key=value without spaces or '&'")
    key, parameter_value = value.split("=", 1)
    return key, parameter_value


def validate_knitwork_binding(
    item_id: int,
    route: str,
    parameter: tuple[str, str],
) -> None:
    expected_route = f"nfc/item/{item_id}"
    if route != expected_route:
        raise EnrollmentError(
            f"Knitwork V1 requires route {expected_route!r} for Item {item_id}"
        )
    if parameter != ("item_id", str(item_id)):
        raise EnrollmentError(
            f"Knitwork V1 requires the signed parameter item_id={item_id}"
        )


def read_icp_canisters(project_root: Path) -> set[str]:
    try:
        return icp_cli.declared_canisters(project_root)
    except icp_cli.IcpCliError as exc:
        raise EnrollmentError(str(exc)) from exc


def resolve_canister_id(
    project_root: Path, canister: str, environment: str, identity: str
) -> str:
    try:
        return icp_cli.resolve_canister_id(
            project_root, canister, environment, identity
        )
    except icp_cli.IcpCliError as exc:
        raise EnrollmentError(str(exc)) from exc


def query_item(
    project_root: Path,
    canister: str,
    environment: str,
    identity: str,
    item_id: int,
) -> dict[str, object]:
    try:
        output = icp_cli.call_canister(
            project_root,
            environment,
            identity,
            canister,
            "getCollectionItem",
            f"({item_id} : nat)",
            query=True,
        )
        if not icp_cli.optional_is_present(output):
            raise EnrollmentError(f"item {item_id} does not exist in {canister}")
        return {"name": icp_cli.text_field(output, "name")}
    except (ValueError, icp_cli.IcpCliError) as exc:
        raise EnrollmentError(f"unexpected getCollectionItem response: {exc}") from exc


def route_exists(
    project_root: Path,
    canister: str,
    environment: str,
    identity: str,
    route: str,
) -> bool:
    try:
        output = icp_cli.call_canister(
            project_root,
            environment,
            identity,
            canister,
            "get_route_protection",
            f"({json.dumps(route)})",
            query=True,
        )
        return icp_cli.optional_is_present(output)
    except (ValueError, icp_cli.IcpCliError) as exc:
        raise EnrollmentError(f"unexpected get_route_protection response: {exc}") from exc


def ensure_route(
    project_root: Path,
    canister: str,
    environment: str,
    identity: str,
    route: str,
) -> None:
    if not route_exists(project_root, canister, environment, identity, route):
        try:
            icp_cli.call_canister(
                project_root,
                environment,
                identity,
                canister,
                "add_protected_route",
                f"({json.dumps(route)})",
            )
        except icp_cli.IcpCliError as exc:
            raise EnrollmentError(str(exc)) from exc
    if not route_exists(project_root, canister, environment, identity, route):
        raise EnrollmentError("protected route was not persisted by the Collection")


def base_url(canister_id: str, environment: str, route: str) -> str:
    if environment == "ic":
        return f"https://{canister_id}.raw.icp0.io/{route}"
    return f"http://{canister_id}.raw.localhost:8000/{route}"


def requested_key_mode(key_mode: str | None, legacy_random_key: bool) -> str | None:
    if legacy_random_key:
        if key_mode not in (None, KEY_MODE_RANDOM):
            raise EnrollmentError("--random-key cannot be combined with --key-mode zero")
        return KEY_MODE_RANDOM
    return key_mode


def prompt_key_mode() -> str:
    print("\nAES key mode")
    print("============")
    print("1. random - unique random key, saved in a private Item key file (recommended)")
    print("2. zero   - keep 00000000000000000000000000000000 (test only)")
    while True:
        choice = input("Choose [1]: ").strip().lower()
        if choice in {"", "1", "random", "r"}:
            return KEY_MODE_RANDOM
        if choice in {"2", "zero", "z"}:
            return KEY_MODE_ZERO
        print("Please type 1 for random or 2 for zero.")


def save_random_key(
    key_hex: str,
    canister: str,
    canister_id: str,
    environment: str,
    item_id: int,
    item_name: str,
    uid: str,
    route: str,
    key_dir: Path | None,
) -> Path:
    directory = key_dir or (Path.home() / ".local" / "share" / "evorev" / "nfc-keys")
    directory.mkdir(mode=0o700, parents=True, exist_ok=True)
    try:
        directory.chmod(0o700)
    except OSError:
        pass
    path = directory / f"{canister}-item-{item_id}-{uid}.key"
    if path.exists():
        raise EnrollmentError(f"key file already exists; refusing to overwrite it: {path}")
    key_record = {
        "schema_version": 2,
        "key_mode": KEY_MODE_RANDOM,
        "aes_key_0_hex": key_hex,
        "collection_alias": canister,
        "collection_principal": canister_id,
        "environment": environment,
        "item_id": item_id,
        "item_name": item_name,
        "tag_uid": uid,
        "nfc_route": f"/{route}",
        "created_at_utc": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
    }
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
        json.dump(key_record, handle, ensure_ascii=False, indent=2)
        handle.write("\n")
    return path


def form_sdm_payload(uri: str, parameter: tuple[str, str] | None) -> dict[str, object]:
    # Keep the CMAC as the final field, as required by the NTAG 424 SDM
    # layout. Static routing data is placed before the dynamic mirrors.
    payload = [0x00, 0x00, 0xD1, 0x01, 0x00, 0x55, 0x00]
    payload.extend(uri.encode("ascii"))
    payload.append(ord("?"))
    if parameter is not None:
        payload.extend(f"{parameter[0]}={parameter[1]}&".encode("ascii"))

    payload.extend(b"uid=")
    uid_offset = len(payload)
    payload.extend([0] * 14)
    payload.extend(b"&ctr=")
    counter_offset = len(payload)
    payload.extend([0] * 6)
    payload.extend(b"&cmac=")
    mac_offset = len(payload)
    payload.extend([0] * 16)

    header_length = 7
    ndef_message_length = (len(payload) - header_length) + 5
    ndef_record_length = (len(payload) - header_length) + 1
    if ndef_message_length > 0xFF or ndef_record_length > 0xFF:
        raise EnrollmentError("NDEF URL is too long for the short-record layout")
    payload[1] = ndef_message_length
    payload[4] = ndef_record_length
    return {
        "payload": payload,
        "uid_offset": uid_offset,
        "counter_offset": counter_offset,
        "mac_offset": mac_offset,
    }


def program_tag(
    ntp,
    uri: str,
    parameter: tuple[str, str] | None,
    random_key_hex: str | None,
    card_type: int,
) -> None:
    formed = form_sdm_payload(uri, parameter)

    default_key = (c_ubyte * 16)()
    memset(default_key, 0, sizeof(default_key))
    file_no = c_ubyte(2)
    key_no = c_ubyte(0)

    status = ntp.nt4h_set_global_parameters(file_no, key_no, c_ubyte(0))
    if status != 0:
        raise EnrollmentError(
            f"cannot select NTAG NDEF file: {ntp.uFR_NT4H_Status2String(status)}"
        )

    payload = formed["payload"]
    write_buffer = (c_ubyte * len(payload))(*payload)
    bytes_written = c_uint16()
    auth_mode = c_ubyte(ntp.T4T_AUTHENTICATION["T4T_PK_PWD_AUTH"])
    status = ntp.LinearWrite_PK(
        write_buffer,
        0,
        c_uint16(len(payload)),
        bytes_written,
        auth_mode,
        default_key,
    )
    if status != 0 or bytes_written.value != len(payload):
        raise EnrollmentError(
            f"NDEF write failed: {ntp.uFR_NT4H_Status2String(status)} "
            f"({bytes_written.value}/{len(payload)} bytes)"
        )

    settings = (
        default_key,
        file_no,
        key_no,
        c_ubyte(3),
        c_ubyte(0),
        c_ubyte(0x0E),
        c_ubyte(0),
        c_ubyte(0),
        c_ubyte(0),
        c_ubyte(1),
        c_ubyte(1),
        c_ubyte(0),
        c_ubyte(0),
        c_ubyte(0x0E),
        c_ubyte(0),
        c_ubyte(0),
        formed["uid_offset"],
        formed["counter_offset"],
        c_uint(0),
        c_uint(formed["mac_offset"]),
        c_uint(0),
        c_uint(0),
        formed["mac_offset"],
        c_uint(0),
    )
    if card_type == 0x13:
        status = ntp.nt4h_tt_change_sdm_file_settings_pk(
            *settings,
            c_ubyte(0),
            c_uint(0),
        )
    else:
        status = ntp.nt4h_change_sdm_file_settings_pk(*settings)
    if status != 0:
        raise EnrollmentError(
            f"SDM configuration failed: {ntp.uFR_NT4H_Status2String(status)}"
        )

    if random_key_hex is not None:
        new_key = ntp.string_to_hex_buffer(random_key_hex)
        status = ntp.nt4h_change_key_pk(default_key, 0, new_key, default_key)
        if status != 0:
            raise EnrollmentError(
                f"AES key change failed: {ntp.uFR_NT4H_Status2String(status)}"
            )


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Plan or execute one explicit NTAG 424 Collection enrollment"
    )
    parser.add_argument("--canister", required=True, help="Explicit alias, e.g. collection_bleu")
    parser.add_argument("--item-id", required=True, type=int)
    parser.add_argument("--route", help="NFC route; defaults to nfc/item/<item-id>")
    parser.add_argument("--environment", choices=("local", "ic"), default="local")
    parser.add_argument("--identity", default="raygen")
    parser.add_argument("--expected-canister-id")
    parser.add_argument("--param", help="One signed custom NDEF parameter, e.g. item_id=0")
    parser.add_argument("--cmac-count", type=int, default=20_000)
    parser.add_argument("--batch-size", type=int, default=1_000)
    parser.add_argument(
        "--key-mode",
        choices=KEY_MODES,
        help="AES key mode: random (saved per Item) or zero (test only)",
    )
    parser.add_argument("--random-key", action="store_true", help=argparse.SUPPRESS)
    parser.add_argument("--key-dir", type=Path)
    parser.add_argument("--execute", action="store_true")
    parser.add_argument("--yes", action="store_true", help="Skip the y/N confirmation")
    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    project_root = Path(__file__).resolve().parents[1]

    try:
        if shutil.which("icp") is None:
            raise EnrollmentError("icp is not available")
        if not CANISTER_RE.fullmatch(args.canister):
            raise EnrollmentError("invalid canister alias")
        if args.canister not in read_icp_canisters(project_root):
            raise EnrollmentError(f"{args.canister} is not declared in icp.yaml")
        if args.item_id < 0:
            raise EnrollmentError("item-id cannot be negative")
        if args.cmac_count <= 0 or args.cmac_count > 0xFFFFFF:
            raise EnrollmentError("cmac-count must be between 1 and 16,777,215")
        if args.batch_size <= 0:
            raise EnrollmentError("batch-size must be greater than zero")
        key_mode = requested_key_mode(args.key_mode, args.random_key)

        expected_route = f"nfc/item/{args.item_id}"
        route = normalize_route(args.route or expected_route)
        expected_parameter = ("item_id", str(args.item_id))
        parameter = parse_parameter(args.param) if args.param else expected_parameter
        validate_knitwork_binding(args.item_id, route, parameter)
        canister_id = resolve_canister_id(
            project_root, args.canister, args.environment, args.identity
        )
        if args.expected_canister_id and canister_id != args.expected_canister_id:
            raise EnrollmentError(
                f"principal mismatch: expected {args.expected_canister_id}, resolved {canister_id}"
            )
        item = query_item(
            project_root, args.canister, args.environment, args.identity, args.item_id
        )
        route_is_present = route_exists(
            project_root, args.canister, args.environment, args.identity, route
        )
        uri = base_url(canister_id, args.environment, route)
        dynamic_url = (
            uri
            + "?"
            + (f"{parameter[0]}={parameter[1]}&" if parameter else "")
            + "uid=<UID>&ctr=<COUNTER>&cmac=<CMAC>"
        )

        print("\nNFC enrollment plan")
        print("===================")
        print(f"Collection alias : {args.canister}")
        print(f"Principal        : {canister_id}")
        print(f"Environment      : {args.environment}")
        print(f"Identity         : {args.identity}")
        print(f"Item             : {args.item_id} · {item.get('name', '')}")
        print(f"Protected route  : /{route} ({'already present' if route_is_present else 'to create'})")
        print(f"NDEF URL         : {dynamic_url}")
        print(f"CMAC proofs      : {args.cmac_count}")
        if key_mode == KEY_MODE_RANDOM:
            key_description = "random, saved with the Collection and Item"
        elif key_mode == KEY_MODE_ZERO:
            key_description = "all zeroes (test only)"
        else:
            key_description = "choose random or zero during programming"
        print(f"AES key          : {key_description}")

        if not args.execute:
            print("\nPLAN ONLY — no reader, tag or canister state was changed.")
            return 0

        if key_mode is None:
            if args.yes:
                raise EnrollmentError("--key-mode random or --key-mode zero is required with --yes")
            key_mode = prompt_key_mode()

        print(
            "Selected AES key: "
            + (
                "random unique key (saved before programming)"
                if key_mode == KEY_MODE_RANDOM
                else "all-zero test key"
            )
        )

        if not args.yes:
            confirmation = input(
                "\n"
                f"Place the NTAG 424 for Item {args.item_id} on the programmer.\n"
                f"Collection to program: {args.canister} ({canister_id})\n"
                f"NFC path: /{route}\n"
                f"AES key mode: {key_mode}\n"
                "Continue? [y/N]: "
            ).strip().lower()
            if confirmation != "y":
                raise EnrollmentError("programming cancelled; nothing was changed")

        # The vendor library resolves its native .so relative to the project root.
        os.chdir(project_root)
        import ntag424_programmer as ntp

        status = ntp.ReaderOpen()
        if status != 0:
            raise EnrollmentError(
                f"cannot open D-Logic programmer: {ntp.uFR_NT4H_Status2String(status)}"
            )
        try:
            uid_buffer = (c_ubyte * 11)()
            sak = c_ubyte()
            uid_size = c_ubyte()
            status = ntp.GetCardIdEx(sak, uid_buffer, uid_size)
            if status != 0:
                raise EnrollmentError(
                    f"no readable tag on programmer: {ntp.uFR_NT4H_Status2String(status)}"
                )
            if uid_size.value != 7:
                raise EnrollmentError(
                    f"expected a 7-byte NTAG 424 UID, reader returned {uid_size.value} bytes"
                )
            uid = "".join(f"{uid_buffer[index]:02X}" for index in range(uid_size.value))
            print(f"Detected tag UID : {uid}")

            card_type = c_ubyte()
            status = ntp.GetDlogicCardType(card_type)
            if status != 0:
                raise EnrollmentError(
                    f"cannot identify tag type: {ntp.uFR_NT4H_Status2String(status)}"
                )
            if card_type.value not in (0x12, 0x13):
                card_name = ntp.card_types.DLOGIC_CARD_TYPE.get(
                    card_type.value, f"unknown 0x{card_type.value:02X}"
                )
                raise EnrollmentError(
                    f"refusing unsupported tag type {card_name}; expected NTAG 424 DNA or DNA TT"
                )
            print(
                "Detected tag type: "
                + ntp.card_types.DLOGIC_CARD_TYPE[card_type.value]
            )

            key_hex = DEFAULT_KEY_HEX
            key_path: Path | None = None
            if key_mode == KEY_MODE_RANDOM:
                key_hex = secrets.token_hex(16).upper()
                key_path = save_random_key(
                    key_hex,
                    args.canister,
                    canister_id,
                    args.environment,
                    args.item_id,
                    str(item.get("name", "")),
                    uid,
                    route,
                    args.key_dir,
                )
                print(
                    f"AES key file     : {key_path} "
                    "(mode 0600; contains key and Item mapping)"
                )

            hashes = hashed_cmacs.generate_hashes(args.cmac_count, uid, key_hex)

            # Prepare and verify all on-chain validation data before touching the tag.
            ensure_route(
                project_root, args.canister, args.environment, args.identity, route
            )
            batch_cmacs.upload_hashes(
                project_root,
                args.environment,
                args.identity,
                args.canister,
                route,
                uid,
                hashes,
                args.batch_size,
            )

            program_tag(
                ntp,
                uri,
                parameter,
                key_hex if key_mode == KEY_MODE_RANDOM else None,
                card_type.value,
            )
            if key_mode == KEY_MODE_RANDOM:
                print("NTAG NDEF, SDM settings and random AES key programmed.")
            else:
                print("NTAG NDEF and SDM settings programmed; all-zero AES key retained.")
        finally:
            ntp.ReaderClose()

        verified = batch_cmacs.query_existing_hashes(
            project_root, args.environment, args.identity, args.canister, route, uid
        )
        if verified != hashes:
            raise EnrollmentError("final on-chain CMAC verification failed")

        print("\nEnrollment complete and on-chain CMAC table verified.")
        print(
            "Public item page : "
            + base_url(canister_id, args.environment, f"item/{args.item_id}")
        )
        return 0
    except (EnrollmentError, RuntimeError, ValueError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
