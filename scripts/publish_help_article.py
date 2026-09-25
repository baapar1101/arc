#!/usr/bin/env python3
"""Publish a single help article from a local HTML file via WordPress REST API.

Usage:
  export HESABIX_WP_USER='support@hesabix.ir'
  export HESABIX_WP_APP_PASSWORD='xxxx xxxx xxxx xxxx'
  python3 scripts/publish_help_article.py 791 docs/help-content/791-sales-invoice.html

Create Application Password: WP Admin → Users → Profile → Application Passwords → help-content-agent
"""
from __future__ import annotations

import base64
import json
import os
import sys
import urllib.error
import urllib.request
from pathlib import Path


def main() -> None:
    if len(sys.argv) < 3:
        print(__doc__)
        sys.exit(1)

    post_id = int(sys.argv[1])
    html_path = Path(sys.argv[2])
    excerpt_path = Path(sys.argv[3]) if len(sys.argv) > 3 else None

    user = os.environ.get("HESABIX_WP_USER", "support@hesabix.ir")
    app_pass = os.environ.get("HESABIX_WP_APP_PASSWORD", "").replace(" ", "")
    if not app_pass:
        print("Error: set HESABIX_WP_APP_PASSWORD (Application Password, not login password)")
        sys.exit(1)

    html = html_path.read_text(encoding="utf-8")
    excerpt = excerpt_path.read_text(encoding="utf-8").strip() if excerpt_path else ""

    payload: dict = {"content": html}
    if excerpt:
        payload["excerpt"] = excerpt

    creds = base64.b64encode(f"{user}:{app_pass}".encode()).decode()
    url = f"https://hesabix.ir/wp-json/wp/v2/help/{post_id}"
    req = urllib.request.Request(url, data=json.dumps(payload).encode(), method="POST")
    req.add_header("Authorization", f"Basic {creds}")
    req.add_header("Content-Type", "application/json")

    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            data = json.loads(resp.read())
            print(f"OK #{post_id}: {data['title']['rendered']}")
            print(f"URL: {data['link']}")
            print(f"Content length: {len(data['content']['rendered'])} chars rendered")
    except urllib.error.HTTPError as e:
        print(f"HTTP {e.code}: {e.read().decode()[:500]}")
        sys.exit(1)


if __name__ == "__main__":
    main()
