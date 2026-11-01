#!/usr/bin/python3
"""Minimal YP Python demo."""

import argparse
import json

__version__ = "0.1.0"


def main(argv=None):
    parser = argparse.ArgumentParser(description="YP Python demo service")
    parser.add_argument("--json", action="store_true", help="print status as JSON")
    parser.add_argument(
        "--version", action="version", version=f"%(prog)s {__version__}"
    )
    args = parser.parse_args(argv)

    if args.json:
        print(json.dumps({"name": "yp-demo-python", "version": __version__, "status": "ok"}))
    else:
        print(f"yp-demo-python {__version__}")


if __name__ == "__main__":
    main()
