#!/usr/bin/env python3
"""Build the small Candid values used by Collection operator scripts."""

from __future__ import annotations

import json
import re
import sys
from collections.abc import Sequence


NAT_RE = re.compile(r"^(0|[1-9][0-9]*)$")


def candid_text(value: str) -> str:
    return json.dumps(value, ensure_ascii=False)


def build_item_argument(fields: Sequence[str], attributes: Sequence[tuple[str, str]]) -> str:
    if len(fields) != 5:
        raise ValueError("exactly five Item text fields are required")
    rendered_attributes = ";".join(
        f"record {{{candid_text(key)}; {candid_text(value)}}}"
        for key, value in attributes
    )
    rendered_fields = ", ".join(candid_text(field) for field in fields)
    return f"({rendered_fields}, vec {{{rendered_attributes}}})"


def parse_nat_json(output: str) -> int:
    try:
        value = json.loads(output)
    except json.JSONDecodeError as exc:
        raise ValueError("dfx did not return valid JSON") from exc

    if isinstance(value, bool):
        raise ValueError("dfx returned a Boolean instead of a Nat")
    if isinstance(value, int) and value >= 0:
        return value
    if isinstance(value, str) and NAT_RE.fullmatch(value):
        return int(value)
    raise ValueError("dfx JSON result is not one Candid Nat")


def main(arguments: Sequence[str] | None = None) -> int:
    values = list(sys.argv[1:] if arguments is None else arguments)
    if not values:
        raise ValueError("expected item-argument or parse-nat")

    command = values.pop(0)
    if command == "item-argument":
        if len(values) < 5 or (len(values) - 5) % 2 != 0:
            raise ValueError("expected five Item fields followed by key/value pairs")
        attribute_values = values[5:]
        pairs = list(
            zip(attribute_values[::2], attribute_values[1::2], strict=True)
        )
        print(build_item_argument(values[:5], pairs))
        return 0

    if command == "parse-nat" and len(values) == 1:
        print(parse_nat_json(values[0]))
        return 0
    raise ValueError("invalid candid_values.py arguments")


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except ValueError as error:
        print(f"Error: {error}", file=sys.stderr)
        raise SystemExit(2) from error
