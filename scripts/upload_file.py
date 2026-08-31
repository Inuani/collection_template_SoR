#!/usr/bin/env python3
"""Upload one private file to a Collection canister with ICP CLI."""

from __future__ import annotations

import argparse
import json
import mimetypes
import os
import re
import tempfile
from pathlib import Path

import icp_cli


CHUNK_SIZE = 36_000


def candid_text(value: str) -> str:
    return json.dumps(value, ensure_ascii=False)


def upload_chunk(
    project_root: Path,
    environment: str,
    identity: str,
    canister: str,
    chunk: bytes,
) -> None:
    descriptor, argument_path = tempfile.mkstemp(prefix="collection-upload-", suffix=".did")
    try:
        os.chmod(argument_path, 0o600)
        with os.fdopen(descriptor, "w", encoding="ascii") as handle:
            handle.write("(vec {")
            handle.write(";".join(str(byte) for byte in chunk))
            handle.write("})\n")
        icp_cli.call_canister(
            project_root,
            environment,
            identity,
            canister,
            "upload",
            None,
            args_file=Path(argument_path),
            timeout=120,
        )
    finally:
        Path(argument_path).unlink(missing_ok=True)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Upload a file to one Collection")
    parser.add_argument("file", type=Path)
    parser.add_argument("title", nargs="?")
    parser.add_argument("artist", nargs="?", default="Unknown")
    parser.add_argument("canister", nargs="?", default="collection_monayolla")
    parser.add_argument("environment", nargs="?", default="local")
    parser.add_argument("identity", nargs="?", default="raygen")
    return parser


def main() -> int:
    args = build_parser().parse_args()
    project_root = Path(__file__).resolve().parents[1]
    file_path = args.file.resolve()
    if not file_path.is_file():
        raise SystemExit(f"ERROR: file not found: {file_path}")

    title = args.title or file_path.name
    content_type = mimetypes.guess_type(file_path.name)[0] or "application/octet-stream"
    total_chunks = max(1, (file_path.stat().st_size + CHUNK_SIZE - 1) // CHUNK_SIZE)

    print(f"File        : {file_path}")
    print(f"Title       : {title}")
    print(f"Artist      : {args.artist}")
    print(f"Content-Type: {content_type}")
    print(f"Canister    : {args.canister}")
    print(f"Environment : {args.environment}")
    print(f"Identity    : {args.identity}")

    try:
        with file_path.open("rb") as handle:
            for index in range(total_chunks):
                chunk = handle.read(CHUNK_SIZE)
                print(f"Uploading chunk {index + 1}/{total_chunks}...")
                upload_chunk(
                    project_root,
                    args.environment,
                    args.identity,
                    args.canister,
                    chunk,
                )

        result = icp_cli.call_canister(
            project_root,
            args.environment,
            args.identity,
            args.canister,
            "uploadFinalize",
            f"({candid_text(title)}, {candid_text(args.artist)}, {candid_text(content_type)})",
            timeout=120,
        )
        if re.search(r"\berr\s*=", result):
            try:
                detail = icp_cli.text_field(result, "err")
            except ValueError:
                detail = result
            raise icp_cli.IcpCliError(f"uploadFinalize rejected the file: {detail}")
        if not re.search(r"\bok\s*=", result):
            raise icp_cli.IcpCliError(
                f"uploadFinalize returned an unexpected response: {result}"
            )
    except (OSError, ValueError, icp_cli.IcpCliError) as exc:
        raise SystemExit(f"ERROR: {exc}") from exc

    print("Upload completed successfully.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
