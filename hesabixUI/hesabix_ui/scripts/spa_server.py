#!/usr/bin/env python3
"""Serve a Flutter web release with SPA route fallback for local testing."""

from __future__ import annotations

import argparse
import os
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlsplit


DEFAULT_ROOT = Path(__file__).resolve().parent.parent / "build" / "web"


class SpaRequestHandler(SimpleHTTPRequestHandler):
    def do_GET(self) -> None:  # noqa: N802 - stdlib handler API
        path = urlsplit(self.path).path
        requested = (Path.cwd() / path.lstrip("/")).resolve()
        root = Path.cwd().resolve()
        try:
            requested.relative_to(root)
        except ValueError:
            self.send_error(403)
            return
        if not requested.exists() or requested.is_dir():
            self.path = "/index.html"
        super().do_GET()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="0.0.0.0")
    parser.add_argument("--port", type=int, default=8080)
    parser.add_argument("--root", type=Path, default=DEFAULT_ROOT)
    args = parser.parse_args()

    root = args.root.expanduser().resolve()
    index = root / "index.html"
    if not index.is_file():
        raise SystemExit(
            f"Flutter build not found at {root}. Run 'flutter build web' first."
        )

    os.chdir(root)
    server = ThreadingHTTPServer((args.host, args.port), SpaRequestHandler)
    print(f"Serving {root} at http://{args.host}:{args.port}")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
