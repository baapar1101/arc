#!/usr/bin/env python3
"""Publish help articles via hesabix-portal login (captcha required).

Usage:
  python3 scripts/publish_help_portal.py CAPTCHA_CODE [article...]

  article format: ID:path/to.html[:path/to.excerpt.txt]

Example:
  python3 scripts/publish_help_portal.py 42469 \\
    793:docs/help-content/793-quick-sales.html:docs/help-content/793-quick-sales.excerpt.txt
"""
from __future__ import annotations

import base64
import http.cookiejar
import json
import re
import sys
import urllib.request
from pathlib import Path

USER = "support@hesabix.ir"
PWD = "@@babaK24055"
REST_PORTAL = "https://hesabix.ir/wp-json/hesabix-portal/v1"
REST_HELP = "https://hesabix.ir/wp-json/wp/v2/help"


def fetch_captcha(opener) -> tuple[str, Path]:
    req = urllib.request.Request(f"{REST_PORTAL}/captcha", method="POST", data=b"{}")
    req.add_header("Content-Type", "application/json")
    cap = json.loads(opener.open(req).read())
    data = cap["data"]
    captcha_id = data["captcha_id"]
    img_path = Path("/tmp/wp_captcha_publish.png")
    img_path.write_bytes(base64.b64decode(data["image_base64"]))
    return captcha_id, img_path


def login(opener, captcha_id: str, captcha_code: str) -> None:
    payload = json.dumps(
        {
            "identifier": USER,
            "password": PWD,
            "captcha_id": captcha_id,
            "captcha_code": captcha_code,
        }
    ).encode()
    req = urllib.request.Request(f"{REST_PORTAL}/login", data=payload, method="POST")
    req.add_header("Content-Type", "application/json")
    resp = json.loads(opener.open(req).read())
    if not resp.get("success"):
        raise RuntimeError(f"Login failed: {resp}")


def get_wp_nonce(opener) -> str:
    profile = opener.open("https://hesabix.ir/wp-admin/profile.php").read().decode("utf-8", errors="replace")
    m = re.search(r'wpApiSettings\s*=\s*\{[^}]*"nonce":"([^"]+)"', profile)
    if not m:
        raise RuntimeError("Could not extract wpApiSettings.nonce from profile page")
    return m.group(1)


def publish(opener, nonce: str, post_id: int, html: str, excerpt: str = "") -> dict:
    payload: dict = {"content": html}
    if excerpt:
        payload["excerpt"] = excerpt
    req = urllib.request.Request(
        f"{REST_HELP}/{post_id}",
        data=json.dumps(payload).encode(),
        method="POST",
    )
    req.add_header("Content-Type", "application/json")
    req.add_header("X-WP-Nonce", nonce)
    return json.loads(opener.open(req).read())


def parse_article(spec: str, base: Path) -> tuple[int, str, str]:
    parts = spec.split(":")
    post_id = int(parts[0])
    html = (base / parts[1]).read_text(encoding="utf-8")
    excerpt = (base / parts[2]).read_text(encoding="utf-8").strip() if len(parts) > 2 else ""
    return post_id, html, excerpt


def main() -> None:
    if len(sys.argv) < 3:
        print(__doc__)
        sys.exit(1)

    captcha_code = sys.argv[1].strip()
    articles = sys.argv[2:]
    base = Path(__file__).resolve().parent.parent

    cj = http.cookiejar.CookieJar()
    opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(cj))

    captcha_id, img_path = fetch_captcha(opener)
    print(f"Captcha image: {img_path} (id={captcha_id})")

    login(opener, captcha_id, captcha_code)
    print("Login OK")

    nonce = get_wp_nonce(opener)
    print(f"WP nonce: {nonce[:8]}...")

    for spec in articles:
        post_id, html, excerpt = parse_article(spec, base)
        data = publish(opener, nonce, post_id, html, excerpt)
        print(f"OK #{post_id}: {data['title']['rendered']}")
        print(f"  URL: {data['link']}")
        print(f"  Rendered: {len(data['content']['rendered'])} chars")


if __name__ == "__main__":
    main()
