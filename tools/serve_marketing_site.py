#!/usr/bin/env python3
"""Static file server with SPA fallback for marketing-site dist."""
from __future__ import annotations

import argparse
import http.server
import socketserver
from pathlib import Path


class SpaHandler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, directory: str | None = None, **kwargs):
        super().__init__(*args, directory=directory, **kwargs)

    def do_GET(self) -> None:
        path = self.path.split("?", 1)[0]
        if path not in ("", "/") and not path.startswith("/assets/"):
            local = Path(self.directory or ".") / path.lstrip("/")
            if not local.is_file():
                self.path = "/index.html"
        super().do_GET()


def main() -> None:
    parser = argparse.ArgumentParser(description="Serve marketing-site dist with SPA routing")
    parser.add_argument("--port", type=int, default=5174)
    parser.add_argument("--bind", default="0.0.0.0")
    parser.add_argument(
        "--directory",
        default=str(Path(__file__).resolve().parents[1] / "src" / "apps" / "marketing-site" / "dist"),
    )
    args = parser.parse_args()

    handler = lambda *h_args, **h_kwargs: SpaHandler(  # noqa: E731
        *h_args, directory=args.directory, **h_kwargs
    )
    socketserver.TCPServer.allow_reuse_address = True
    try:
        with socketserver.TCPServer((args.bind, args.port), handler) as httpd:
            print(f"Serving {args.directory} at http://127.0.0.1:{args.port}/")
            if args.bind == "0.0.0.0":
                print(f"LAN: use http://<this-pc-ip>:{args.port}/")
            httpd.serve_forever()
    except OSError as exc:
        if getattr(exc, "winerror", None) == 10048 or exc.errno in {48, 98}:
            raise SystemExit(
                f"Port {args.port} is already in use. "
                f"Stop the other process or pick another port: "
                f"python tools/serve_marketing_site.py --port 5175"
            ) from exc
        raise


if __name__ == "__main__":
    main()
