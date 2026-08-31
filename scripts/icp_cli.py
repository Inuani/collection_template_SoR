#!/usr/bin/env python3
"""Small, typed helpers for invoking ICP CLI from operator scripts."""

from __future__ import annotations

import re
import subprocess
from pathlib import Path


NAME_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_-]*$")


class IcpCliError(RuntimeError):
    pass


def _run(command: list[str], project_root: Path, timeout: float | None = None) -> str:
    try:
        result = subprocess.run(
            command,
            cwd=project_root,
            text=True,
            capture_output=True,
            timeout=timeout,
        )
    except FileNotFoundError as exc:
        raise IcpCliError("icp is not available") from exc
    except subprocess.TimeoutExpired as exc:
        raise IcpCliError("ICP CLI command timed out") from exc
    if result.returncode != 0:
        detail = result.stderr.strip() or result.stdout.strip()
        raise IcpCliError(f"ICP CLI command failed: {detail}")
    return result.stdout.strip()


def validate_name(value: str, label: str) -> None:
    if not NAME_RE.fullmatch(value):
        raise IcpCliError(f"invalid {label}: {value!r}")


def declared_canisters(project_root: Path) -> set[str]:
    config_path = project_root / "icp.yaml"
    try:
        lines = config_path.read_text(encoding="utf-8").splitlines()
    except OSError as exc:
        raise IcpCliError(f"cannot read {config_path}: {exc}") from exc

    names: set[str] = set()
    in_canisters = False
    for line in lines:
        if not in_canisters:
            in_canisters = line.strip() == "canisters:" and not line.startswith((" ", "\t"))
            continue
        if line and not line.startswith((" ", "\t")):
            break
        match = re.match(r"^\s+-\s+name:\s*['\"]?([A-Za-z0-9][A-Za-z0-9_-]*)['\"]?\s*$", line)
        if match:
            names.add(match.group(1))
    if not names:
        raise IcpCliError("icp.yaml declares no canisters")
    return names


def resolve_canister_id(
    project_root: Path,
    canister: str,
    environment: str,
    identity: str,
) -> str:
    for value, label in (
        (canister, "canister alias"),
        (environment, "environment"),
        (identity, "identity"),
    ):
        validate_name(value, label)
    return _run(
        [
            "icp",
            "canister",
            "status",
            canister,
            "--environment",
            environment,
            "--identity",
            identity,
            "--id-only",
        ],
        project_root,
    )


def call_canister(
    project_root: Path,
    environment: str,
    identity: str,
    canister: str,
    method: str,
    argument: str | None = "()",
    *,
    args_file: Path | None = None,
    query: bool = False,
    timeout: float | None = None,
) -> str:
    for value, label in (
        (canister, "canister alias"),
        (method, "canister method"),
        (environment, "environment"),
        (identity, "identity"),
    ):
        validate_name(value, label)
    if args_file is not None and argument not in (None, "()"):
        raise ValueError("argument and args_file cannot both be supplied")

    command = ["icp", "canister", "call", canister, method]
    if args_file is not None:
        command.extend(["--args-file", str(args_file)])
    elif argument is not None:
        command.append(argument)
    command.extend(
        [
            "--environment",
            environment,
            "--identity",
            identity,
            "--output",
            "candid",
        ]
    )
    if query:
        command.append("--query")
    return _run(command, project_root, timeout)


def parse_nat(output: str) -> int:
    match = re.fullmatch(
        r"\s*\(\s*([0-9]+)(?:\s*:\s*nat(?:8|16|32|64)?)?\s*,?\s*\)\s*",
        output,
    )
    if not match:
        raise ValueError("ICP CLI response is not one Candid Nat")
    return int(match.group(1))


def optional_is_present(output: str) -> bool:
    if re.fullmatch(r"\s*\(\s*null\s*,?\s*\)\s*", output):
        return False
    if re.match(r"\s*\(\s*opt\b", output):
        return True
    raise ValueError("ICP CLI response is not one Candid optional value")


def _decode_quoted_at(value: str, start: int) -> tuple[bytes, int]:
    if start >= len(value) or value[start] != '"':
        raise ValueError("expected a quoted Candid value")
    decoded = bytearray()
    index = start + 1
    named_escapes = {
        "n": b"\n",
        "r": b"\r",
        "t": b"\t",
        "\\": b"\\",
        '"': b'"',
        "'": b"'",
    }
    while index < len(value):
        character = value[index]
        if character == '"':
            return bytes(decoded), index + 1
        if character != "\\":
            decoded.extend(character.encode("utf-8"))
            index += 1
            continue

        index += 1
        if index >= len(value):
            raise ValueError("unterminated Candid escape")
        if index + 1 < len(value) and all(
            digit in "0123456789abcdefABCDEF" for digit in value[index : index + 2]
        ):
            decoded.append(int(value[index : index + 2], 16))
            index += 2
            continue
        escaped = value[index]
        if escaped in named_escapes:
            decoded.extend(named_escapes[escaped])
            index += 1
            continue
        if escaped == "u" and index + 1 < len(value) and value[index + 1] == "{":
            end = value.find("}", index + 2)
            if end == -1:
                raise ValueError("unterminated Candid Unicode escape")
            try:
                decoded.extend(chr(int(value[index + 2 : end], 16)).encode("utf-8"))
            except (ValueError, OverflowError) as exc:
                raise ValueError("invalid Candid Unicode escape") from exc
            index = end + 1
            continue
        raise ValueError(f"unsupported Candid escape: \\{escaped}")
    raise ValueError("unterminated quoted Candid value")


def _field_bytes(output: str, field: str, *, blob: bool) -> bytes:
    validate_name(field, "Candid field")
    marker = rf"\b{re.escape(field)}\s*=\s*"
    if blob:
        marker += r"blob\s*"
    match = re.search(marker, output)
    if not match:
        raise ValueError(f"Candid response has no {field!r} field")
    decoded, _ = _decode_quoted_at(output, match.end())
    return decoded


def text_field(output: str, field: str) -> str:
    try:
        return _field_bytes(output, field, blob=False).decode("utf-8")
    except UnicodeDecodeError as exc:
        raise ValueError(f"Candid field {field!r} is not UTF-8 text") from exc


def blob_field(output: str, field: str) -> bytes:
    return _field_bytes(output, field, blob=True)


def nat_field(output: str, field: str) -> int:
    validate_name(field, "Candid field")
    match = re.search(
        rf"\b{re.escape(field)}\s*=\s*([0-9]+)(?:\s*:\s*nat(?:8|16|32|64)?)?\s*;",
        output,
    )
    if not match:
        raise ValueError(f"Candid response has no Nat field {field!r}")
    return int(match.group(1))


def parse_text_vector(output: str) -> list[str]:
    match = re.match(r"\s*\(\s*vec\s*\{", output)
    if not match:
        raise ValueError("ICP CLI response is not one Candid Text vector")
    index = match.end()
    values: list[str] = []
    while True:
        while index < len(output) and (output[index].isspace() or output[index] == ";"):
            index += 1
        if index >= len(output):
            raise ValueError("unterminated Candid vector")
        if output[index] == "}":
            remainder = output[index + 1 :]
            if not re.fullmatch(r"\s*,?\s*\)\s*", remainder):
                raise ValueError("unexpected data after Candid vector")
            return values
        decoded, index = _decode_quoted_at(output, index)
        try:
            values.append(decoded.decode("utf-8"))
        except UnicodeDecodeError as exc:
            raise ValueError("Candid vector contains non-UTF-8 text") from exc
