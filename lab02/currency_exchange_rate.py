#!/usr/bin/env python3
"""Get the exchange rate of one currency against another on a date and save it as JSON."""

import argparse
import json
import os
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
from datetime import date, datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parent
DATA_DIR = ROOT / "data"
LOG_FILE = ROOT / "error.log"
# The service has rates for this period only. For any other date it silently returns the latest rate.
FIRST_DATE, LAST_DATE = date(2025, 1, 1), date(2025, 9, 15)


class ApiError(Exception):
    pass


def parse_args():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "from_currency", metavar="FROM", help="currency to convert from, e.g. USD"
    )
    parser.add_argument(
        "to_currency", metavar="TO", help="currency to convert to, e.g. EUR"
    )
    parser.add_argument(
        "date", help=f"date in YYYY-MM-DD format, {FIRST_DATE}..{LAST_DATE}"
    )
    parser.add_argument(
        "--key", default=os.environ.get("API_KEY"), help="API key (default: $API_KEY)"
    )
    parser.add_argument(
        "--url",
        default="http://localhost:8080",
        help="service URL (default: %(default)s)",
    )
    return parser.parse_args()


def validate(from_currency, to_currency, date_text):
    """Return normalized (FROM, TO, YYYY-MM-DD) or raise ValueError."""
    from_currency, to_currency = from_currency.upper(), to_currency.upper()
    for code in (from_currency, to_currency):
        if not re.fullmatch(r"[A-Z]{3}", code):
            raise ValueError(
                f"invalid currency code '{code}', expected 3 letters like USD"
            )
    try:
        day = date.fromisoformat(date_text)
    except ValueError:
        raise ValueError(
            f"invalid date '{date_text}', expected a real date in YYYY-MM-DD format"
        ) from None
    if not FIRST_DATE <= day <= LAST_DATE:
        raise ValueError(
            f"date {day} is outside the available period {FIRST_DATE}..{LAST_DATE}"
        )
    return from_currency, to_currency, day.isoformat()


def get_rate(url, key, from_currency, to_currency, day):
    """Request the rate from the service. Return the `data` object of the response or raise ApiError."""
    query = urllib.parse.urlencode(
        {"from": from_currency, "to": to_currency, "date": day}
    )
    body = urllib.parse.urlencode({"key": key}).encode()
    try:
        with urllib.request.urlopen(
            f"{url}/?{query}", data=body, timeout=10
        ) as response:
            text = response.read().decode()
    except urllib.error.URLError as e:  # also covers HTTP errors
        raise ApiError(f"request to {url} failed: {e.reason}") from None
    try:
        payload = json.loads(text)
    except json.JSONDecodeError:
        raise ApiError("service returned a response that is not JSON") from None
    if payload.get("error"):
        raise ApiError(payload["error"])
    return payload["data"]


def save(data, from_currency, to_currency, day):
    DATA_DIR.mkdir(exist_ok=True)
    path = DATA_DIR / f"{from_currency}_{to_currency}_{day}.json"
    path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    return path


def log_error(message):
    print(f"Error: {message}", file=sys.stderr)
    with LOG_FILE.open("a", encoding="utf-8") as log:
        log.write(f"{datetime.now():%Y-%m-%d %H:%M:%S} ERROR {message}\n")


def main():
    args = parse_args()
    try:
        if not args.key:
            raise ValueError("API key is missing, set API_KEY or pass --key")
        from_currency, to_currency, day = validate(
            args.from_currency, args.to_currency, args.date
        )
        data = get_rate(args.url, args.key, from_currency, to_currency, day)
    except (ValueError, ApiError) as e:
        log_error(f"{args.from_currency} -> {args.to_currency} on {args.date}: {e}")
        return 1

    path = save(data, from_currency, to_currency, day)
    print(f"{from_currency} -> {to_currency} on {day}: {data['rate']}")
    print(f"Saved to {path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
