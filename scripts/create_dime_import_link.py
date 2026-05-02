#!/usr/bin/env python3
"""Create a Dime external import deep link from a JSON batch file.

Usage:
  python3 scripts/create_dime_import_link.py batch.json

The JSON file must match the schema documented in docs/hermes-dime-automation-plan.md.
"""

from __future__ import annotations

import base64
import json
import sys
from datetime import date, datetime
from pathlib import Path
from typing import Any


MAX_TRANSACTIONS = 50
TRUSTED_SOURCE = "hermes"


def _validate_date(value: Any) -> None:
    if not isinstance(value, str) or not value.strip():
        raise ValueError("date must be a non-empty string")

    raw = value.strip()

    try:
        if "T" in raw:
            datetime.fromisoformat(raw.replace("Z", "+00:00"))
        else:
            date.fromisoformat(raw)
    except ValueError as exc:
        raise ValueError(f"invalid date: {value}") from exc


def validate_batch(batch: Any) -> None:
    if not isinstance(batch, dict):
        raise ValueError("batch must be a JSON object")

    if batch.get("version") != 1:
        raise ValueError("version must be 1")

    if batch.get("source") != TRUSTED_SOURCE:
        raise ValueError(f"source must be {TRUSTED_SOURCE!r}")

    transactions = batch.get("transactions")
    if not isinstance(transactions, list):
        raise ValueError("transactions must be a list")

    if len(transactions) > MAX_TRANSACTIONS:
        raise ValueError(f"max {MAX_TRANSACTIONS} transactions per link")

    for index, transaction in enumerate(transactions, start=1):
        if not isinstance(transaction, dict):
            raise ValueError(f"transaction {index} must be an object")

        external_id = transaction.get("externalId")
        if not isinstance(external_id, str) or not external_id.strip():
            raise ValueError(f"transaction {index}: externalId is required")

        amount = transaction.get("amount")
        if not isinstance(amount, (int, float)) or isinstance(amount, bool) or amount <= 0:
            raise ValueError(f"transaction {index}: amount must be a positive number")

        transaction_type = transaction.get("type", "expense")
        if transaction_type not in {"expense", "income"}:
            raise ValueError(f"transaction {index}: type must be expense or income")

        category_id = transaction.get("categoryId")
        category = transaction.get("category")
        has_category_id = isinstance(category_id, str) and bool(category_id.strip())
        has_category = isinstance(category, str) and bool(category.strip())

        if category_id is not None and not has_category_id:
            raise ValueError(f"transaction {index}: categoryId must be a non-empty string")

        if category is not None and not has_category:
            raise ValueError(f"transaction {index}: category must be a non-empty string")

        if not has_category_id and not has_category:
            raise ValueError(f"transaction {index}: categoryId or category is required")

        if transaction.get("repeatType", 0) != 0 or transaction.get("repeatCoefficient", 1) != 1:
            raise ValueError(f"transaction {index}: recurring imports are not allowed")

        _validate_date(transaction.get("date"))


def main() -> int:
    if len(sys.argv) != 2:
        print("Usage: create_dime_import_link.py batch.json", file=sys.stderr)
        return 2

    batch_path = Path(sys.argv[1])
    raw = batch_path.read_text(encoding="utf-8")

    try:
        batch = json.loads(raw)
        validate_batch(batch)
    except (json.JSONDecodeError, ValueError) as exc:
        print(f"Invalid Dime import batch: {exc}", file=sys.stderr)
        return 1

    compact = json.dumps(batch, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    payload = base64.urlsafe_b64encode(compact).decode("ascii").rstrip("=")

    print(f"dimeapp://importTransactions?payload={payload}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
