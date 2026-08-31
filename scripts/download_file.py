#!/usr/bin/env python3
"""Download one private Collection file through controller-only Candid calls."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import tempfile
from pathlib import Path

import icp_cli


def candid_text(value: str) -> str:
    return json.dumps(value, ensure_ascii=False)


def get_chunk(
    project_root: Path,
    environment: str,
    identity: str,
    canister: str,
    title: str,
    chunk_id: int,
) -> dict[str, object] | None:
    output = icp_cli.call_canister(
        project_root,
        environment,
        identity,
        canister,
        "getFileChunk",
        f"({candid_text(title)}, {chunk_id} : nat)",
        query=True,
        timeout=120,
    )
    if not icp_cli.optional_is_present(output):
        return None
    return {
        "chunk": icp_cli.blob_field(output, "chunk"),
        "total_chunks": icp_cli.nat_field(output, "totalChunks"),
        "content_type": icp_cli.text_field(output, "contentType"),
        "artist": icp_cli.text_field(output, "artist"),
    }


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Download a file from one Collection")
    parser.add_argument("title")
    parser.add_argument("output", nargs="?", type=Path, default=Path("downloaded_file"))
    parser.add_argument("canister", nargs="?", default="collection_monayolla")
    parser.add_argument("environment", nargs="?", default="local")
    parser.add_argument("identity", nargs="?", default="raygen")
    return parser


def main() -> int:
    args = build_parser().parse_args()
    project_root = Path(__file__).resolve().parents[1]
    output_path = args.output.resolve()
    if not output_path.parent.is_dir():
        raise SystemExit(f"ERROR: output directory does not exist: {output_path.parent}")

    print(f"Title       : {args.title}")
    print(f"Canister    : {args.canister}")
    print(f"Environment : {args.environment}")
    print(f"Identity    : {args.identity}")

    temporary_path: Path | None = None
    try:
        first = get_chunk(
            project_root,
            args.environment,
            args.identity,
            args.canister,
            args.title,
            0,
        )
        if first is None:
            raise icp_cli.IcpCliError(f"file not found: {args.title}")

        total_chunks = int(first["total_chunks"])
        if total_chunks <= 0:
            raise ValueError("canister returned an invalid chunk count")
        print(f"Artist      : {first['artist']}")
        print(f"Content-Type: {first['content_type']}")
        print(f"Chunks      : {total_chunks}")

        descriptor, temporary_name = tempfile.mkstemp(
            prefix=f".{output_path.name}.",
            suffix=".part",
            dir=output_path.parent,
        )
        temporary_path = Path(temporary_name)
        digest = hashlib.sha256()
        with os.fdopen(descriptor, "wb") as handle:
            for index in range(total_chunks):
                current = first if index == 0 else get_chunk(
                    project_root,
                    args.environment,
                    args.identity,
                    args.canister,
                    args.title,
                    index,
                )
                if current is None:
                    raise icp_cli.IcpCliError(f"chunk {index} is missing")
                if int(current["total_chunks"]) != total_chunks:
                    raise ValueError("chunk metadata changed during download")
                chunk = current["chunk"]
                if not isinstance(chunk, bytes):
                    raise ValueError("canister returned an invalid chunk")
                print(f"Downloading chunk {index + 1}/{total_chunks}...")
                handle.write(chunk)
                digest.update(chunk)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary_path, output_path)
        temporary_path = None
    except (OSError, ValueError, icp_cli.IcpCliError) as exc:
        if temporary_path is not None:
            temporary_path.unlink(missing_ok=True)
        raise SystemExit(f"ERROR: {exc}") from exc

    print(f"Downloaded   : {output_path}")
    print(f"SHA256       : {digest.hexdigest()}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
