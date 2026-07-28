#!/usr/bin/env bash
# Publish the current Android APK as a Forgejo release for hesabix/arc.
#
# Version is read from hesabixUI/hesabix_ui/pubspec.yaml (MAJOR.MINOR.PATCH).
# Tag, release name, and asset name follow ANDROID_AUTO_UPDATE.md:
#   tag:        70.11.123
#   asset:      app-release.70.11.123.apk
#
# Auth (pick one):
#   FORGEJO_TOKEN=...              # preferred (API token)
#   FORGEJO_USER=... FORGEJO_PASSWORD=...
#   or pass --user / --password / --token
#
# Examples:
#   FORGEJO_USER=morrning FORGEJO_PASSWORD='***' ./release_android_forgejo.sh
#   ./release_android_forgejo.sh --apk path/to/app-release.apk --body $'- note 1\n- note 2'
#   ./release_android_forgejo.sh --dry-run

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR"

DEFAULT_PUBSPEC="hesabixUI/hesabix_ui/pubspec.yaml"
DEFAULT_APK="hesabixUI/hesabix_ui/build/app/outputs/flutter-apk/app-release.apk"
DEFAULT_API_BASE="https://source.hesabix.ir/api/v1"
DEFAULT_OWNER="hesabix"
DEFAULT_REPO="arc"
DEFAULT_TARGET="master"

API_BASE="${FORGEJO_API_BASE:-$DEFAULT_API_BASE}"
OWNER="${FORGEJO_OWNER:-$DEFAULT_OWNER}"
REPO="${FORGEJO_REPO:-$DEFAULT_REPO}"
TARGET="${FORGEJO_TARGET:-$DEFAULT_TARGET}"
USER="${FORGEJO_USER:-}"
PASSWORD="${FORGEJO_PASSWORD:-}"
TOKEN="${FORGEJO_TOKEN:-}"
APK_PATH=""
PUBSPEC_PATH=""
BODY=""
DRY_RUN=0
FORCE=0

print_usage() {
  cat <<EOF
Usage: ./release_android_forgejo.sh [options]

Creates a Forgejo release from the current Flutter version and uploads the APK.

Options:
  --apk PATH          APK file (default: $DEFAULT_APK)
  --pubspec PATH      pubspec.yaml (default: $DEFAULT_PUBSPEC)
  --body TEXT         Release notes (Markdown). Default: short Android note.
  --body-file PATH    Read release notes from file
  --user NAME         Forgejo username (or FORGEJO_USER)
  --password PASS     Forgejo password (or FORGEJO_PASSWORD)
  --token TOKEN       Forgejo API token (or FORGEJO_TOKEN; preferred)
  --api-base URL      API base (default: $DEFAULT_API_BASE)
  --owner OWNER       Repo owner (default: $DEFAULT_OWNER)
  --repo REPO         Repo name (default: $DEFAULT_REPO)
  --target BRANCH     target_commitish (default: $DEFAULT_TARGET)
  --force             Replace existing release with the same tag (delete then recreate)
  --dry-run           Print actions only; do not create/upload
  --help              Show this help

Environment:
  FORGEJO_USER / FORGEJO_PASSWORD / FORGEJO_TOKEN
  FORGEJO_API_BASE / FORGEJO_OWNER / FORGEJO_REPO / FORGEJO_TARGET
EOF
}

info() { echo "[INFO] $*"; }
warn() { echo "[WARN] $*" >&2; }
die() { echo "[ERROR] $*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --apk) APK_PATH="${2:-}"; shift 2 ;;
    --pubspec) PUBSPEC_PATH="${2:-}"; shift 2 ;;
    --body) BODY="${2:-}"; shift 2 ;;
    --body-file)
      [[ -f "${2:-}" ]] || die "body file not found: ${2:-}"
      BODY="$(cat "$2")"
      shift 2
      ;;
    --user) USER="${2:-}"; shift 2 ;;
    --password) PASSWORD="${2:-}"; shift 2 ;;
    --token) TOKEN="${2:-}"; shift 2 ;;
    --api-base) API_BASE="${2:-}"; shift 2 ;;
    --owner) OWNER="${2:-}"; shift 2 ;;
    --repo) REPO="${2:-}"; shift 2 ;;
    --target) TARGET="${2:-}"; shift 2 ;;
    --force) FORCE=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    --help|-h) print_usage; exit 0 ;;
    *) die "Unknown option: $1 (use --help)" ;;
  esac
done

command -v curl >/dev/null || die "curl is required"
command -v python3 >/dev/null || die "python3 is required"

PUBSPEC_PATH="${PUBSPEC_PATH:-$REPO_ROOT/$DEFAULT_PUBSPEC}"
APK_PATH="${APK_PATH:-$REPO_ROOT/$DEFAULT_APK}"

[[ -f "$PUBSPEC_PATH" ]] || die "pubspec not found: $PUBSPEC_PATH"
[[ -f "$APK_PATH" ]] || die "APK not found: $APK_PATH (build with ./build_android.sh --universal-apk first)"

VERSION_NAME="$(
  python3 - "$PUBSPEC_PATH" <<'PY'
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
m = re.search(r"(?m)^version:\s*([^\s#]+)", text)
if not m:
    raise SystemExit("no version: line in pubspec.yaml")
full = m.group(1).strip().strip("'\"")
name = full.split("+", 1)[0].strip()
parts = name.split(".")
if len(parts) != 3 or not all(p.isdigit() for p in parts):
    raise SystemExit(f"versionName must be MAJOR.MINOR.PATCH, got: {name}")
print(name)
PY
)"

ASSET_NAME="app-release.${VERSION_NAME}.apk"
BODY="${BODY:-- انتشار نسخه اندروید ${VERSION_NAME}
- به‌روزرسانی از ریلیزهای رسمی حسابیکس}"

if [[ -n "$TOKEN" ]]; then
  AUTH_ARGS=(-H "Authorization: token ${TOKEN}")
elif [[ -n "$USER" && -n "$PASSWORD" ]]; then
  AUTH_ARGS=(-u "${USER}:${PASSWORD}")
else
  die "Auth required: set FORGEJO_TOKEN or FORGEJO_USER+FORGEJO_PASSWORD (see --help)"
fi

api() {
  # api METHOD PATH [curl args...]
  local method="$1"
  local path="$2"
  shift 2
  curl -sS "${AUTH_ARGS[@]}" -X "$method" "${API_BASE}${path}" "$@"
}

info "Version (tag): ${VERSION_NAME}"
info "APK:           ${APK_PATH} ($(du -h "$APK_PATH" | awk '{print $1}'))"
info "Asset name:    ${ASSET_NAME}"
info "Repo:          ${OWNER}/${REPO} @ ${TARGET}"
info "API:           ${API_BASE}"

if [[ "$DRY_RUN" -eq 1 ]]; then
  info "Dry-run only — no release will be created."
  exit 0
fi

EXISTING_JSON="$(api GET "/repos/${OWNER}/${REPO}/releases/tags/${VERSION_NAME}" || true)"
EXISTING_ID="$(
  python3 -c 'import json,sys
try:
  d=json.loads(sys.stdin.read() or "{}")
except Exception:
  d={}
print(d.get("id") or "")' <<<"$EXISTING_JSON"
)"

if [[ -n "$EXISTING_ID" ]]; then
  if [[ "$FORCE" -eq 1 ]]; then
    warn "Release ${VERSION_NAME} exists (id=${EXISTING_ID}); deleting because --force"
    api DELETE "/repos/${OWNER}/${REPO}/releases/${EXISTING_ID}" -o /dev/null -w "%{http_code}\n" | grep -E '^(204|200)$' >/dev/null \
      || die "Failed to delete existing release ${EXISTING_ID}"
  else
    die "Release tag ${VERSION_NAME} already exists (id=${EXISTING_ID}). Use --force to replace, or bump pubspec version."
  fi
fi

CREATE_PAYLOAD="$(
  VERSION_NAME="$VERSION_NAME" TARGET="$TARGET" BODY="$BODY" python3 <<'PY'
import json, os
print(json.dumps({
  "tag_name": os.environ["VERSION_NAME"],
  "target_commitish": os.environ["TARGET"],
  "name": os.environ["VERSION_NAME"],
  "body": os.environ["BODY"],
  "draft": False,
  "prerelease": False,
}, ensure_ascii=False))
PY
)"

info "Creating release ${VERSION_NAME}..."
CREATE_RESP="$(api POST "/repos/${OWNER}/${REPO}/releases" \
  -H 'Content-Type: application/json' \
  -d "$CREATE_PAYLOAD")"

RELEASE_ID="$(
  python3 -c 'import json,sys
d=json.load(sys.stdin)
if not d.get("id"):
  raise SystemExit(d.get("message") or json.dumps(d, ensure_ascii=False)[:500])
print(d["id"])
print(d.get("html_url",""), file=sys.stderr)' <<<"$CREATE_RESP" 2>/tmp/forgejo_release_url.txt
)"
RELEASE_URL="$(cat /tmp/forgejo_release_url.txt 2>/dev/null || true)"
info "Release id=${RELEASE_ID} ${RELEASE_URL}"

info "Uploading ${ASSET_NAME}..."
UPLOAD_RESP="$(
  curl -sS "${AUTH_ARGS[@]}" \
    -H "Content-Type: application/octet-stream" \
    -X POST \
    --data-binary @"${APK_PATH}" \
    "${API_BASE}/repos/${OWNER}/${REPO}/releases/${RELEASE_ID}/assets?name=${ASSET_NAME}"
)"

python3 -c 'import json,sys
d=json.load(sys.stdin)
if not d.get("id"):
  raise SystemExit(d.get("message") or json.dumps(d, ensure_ascii=False)[:500])
print("[INFO] Asset uploaded:", d.get("name"), "size=", d.get("size"))
print("[INFO] Download:", d.get("browser_download_url") or "")
' <<<"$UPLOAD_RESP"

# Confirm latest
LATEST="$(api GET "/repos/${OWNER}/${REPO}/releases/latest")"
python3 -c 'import json,sys
d=json.load(sys.stdin)
print("[INFO] Latest release is now:", d.get("tag_name"))
assets=d.get("assets") or []
for a in assets:
  print("[INFO]  -", a.get("name"), a.get("browser_download_url"))
' <<<"$LATEST"

info "Done."
