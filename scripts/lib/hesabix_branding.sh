#!/usr/bin/env bash
# Build-time UI branding overlay for Hesabix Flutter web.
#
# Pack layout (flat or nested — first match wins):
#   BRANDING_DIR/
#     names.json                 # { "fa": "…", "en": "…" }  (optional)
#     logo-light.png             # or logos/ / images/
#     logo-blue.png              # optional
#     Icon-192.png …             # or icons/
#     favicon.ico / favicon.png  # optional
#
# Env / .deploy_env:
#   BRANDING_MODE=default|custom   (empty → default)
#   BRANDING_DIR=/opt/hesabix/branding
#   APP_NAME_FA=…  APP_NAME_EN=…
#
# When mode is default (or unset): no-op — Hesabix logos/names stay as in the repo.

# shellcheck shell=bash

HESABIX_BRANDING_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=hesabix_deploy_env.sh
if [[ -r "${HESABIX_BRANDING_LIB_DIR}/hesabix_deploy_env.sh" ]]; then
  # shellcheck disable=SC1091
  source "${HESABIX_BRANDING_LIB_DIR}/hesabix_deploy_env.sh"
fi

_HESABIX_BRANDING_BACKUP_DIR=""
_HESABIX_BRANDING_APPLIED=0
_HESABIX_BRANDING_EFFECTIVE_MODE="default"
HESABIX_BRANDING_NAME_FA=""
HESABIX_BRANDING_NAME_EN=""

hesabix_branding_default_dir() {
  printf '%s' "${APP_ROOT:-/opt/hesabix}/branding"
}

hesabix_branding_normalize_mode() {
  local m="${1:-}"
  m="$(printf '%s' "$m" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
  case "$m" in
    ""|default|hesabix|off|none|0) printf '%s' "default" ;;
    custom|yes|on|1) printf '%s' "custom" ;;
    *) printf '%s' "$m" ;;
  esac
}

# Find a file in branding pack: nested or flat.
hesabix_branding_find_file() {
  local root="$1"
  local name="$2"
  shift 2
  local sub
  for sub in "$@" "."; do
    if [[ "$sub" == "." ]]; then
      [[ -f "${root}/${name}" ]] && { printf '%s' "${root}/${name}"; return 0; }
    else
      [[ -f "${root}/${sub}/${name}" ]] && { printf '%s' "${root}/${sub}/${name}"; return 0; }
    fi
  done
  return 1
}

# Prints two lines: FA then EN. Returns 0 on success.
hesabix_branding_read_names_json() {
  local json_file="$1"
  [[ -f "$json_file" ]] || return 1
  python3 - "$json_file" <<'PY'
import json, sys
path = sys.argv[1]
try:
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
except Exception as e:
    print(f"warn: cannot parse names.json: {e}", file=sys.stderr)
    sys.exit(1)
fa = str(data.get("fa") or data.get("fa_IR") or data.get("persian") or "").strip()
en = str(data.get("en") or data.get("en_US") or data.get("english") or "").strip()
print(fa)
print(en)
PY
}

# Resolve effective mode/dir/names into globals + exports.
# Optional overrides: BRANDING_MODE_OVERRIDE, BRANDING_DIR_OVERRIDE, APP_NAME_FA_OVERRIDE, APP_NAME_EN_OVERRIDE
hesabix_branding_resolve() {
  local mode dir fa en json_path pair

  mode="$(hesabix_branding_normalize_mode "${BRANDING_MODE_OVERRIDE:-${BRANDING_MODE:-}}")"
  dir="${BRANDING_DIR_OVERRIDE:-${BRANDING_DIR:-}}"
  [[ -n "$dir" ]] || dir="$(hesabix_branding_default_dir)"
  fa="${APP_NAME_FA_OVERRIDE:-${APP_NAME_FA:-}}"
  en="${APP_NAME_EN_OVERRIDE:-${APP_NAME_EN:-}}"

  if [[ "$mode" != "custom" ]]; then
    _HESABIX_BRANDING_EFFECTIVE_MODE="default"
    HESABIX_BRANDING_NAME_FA=""
    HESABIX_BRANDING_NAME_EN=""
    export BRANDING_MODE="default"
    return 0
  fi

  if [[ ! -d "$dir" ]]; then
    echo "[branding] warn: BRANDING_MODE=custom but directory missing: $dir — using default" >&2
    _HESABIX_BRANDING_EFFECTIVE_MODE="default"
    HESABIX_BRANDING_NAME_FA=""
    HESABIX_BRANDING_NAME_EN=""
    export BRANDING_MODE="default"
    return 0
  fi

  if [[ -z "$fa" || -z "$en" ]]; then
    json_path=""
    if json_path="$(hesabix_branding_find_file "$dir" "names.json" "." "meta" 2>/dev/null)"; then
      local names_out="" json_fa="" json_en=""
      if names_out="$(hesabix_branding_read_names_json "$json_path" 2>/dev/null)"; then
        json_fa="$(printf '%s\n' "$names_out" | sed -n '1p')"
        json_en="$(printf '%s\n' "$names_out" | sed -n '2p')"
        [[ -z "$fa" && -n "$json_fa" ]] && fa="$json_fa"
        [[ -z "$en" && -n "$json_en" ]] && en="$json_en"
      fi
    fi
  fi

  # Must have at least one asset or a custom name; otherwise fall back.
  local has_asset=0
  hesabix_branding_find_file "$dir" "logo-light.png" "logos" "images" "." >/dev/null 2>&1 && has_asset=1
  hesabix_branding_find_file "$dir" "logo-blue.png" "logos" "images" "." >/dev/null 2>&1 && has_asset=1
  hesabix_branding_find_file "$dir" "Icon-192.png" "icons" "." >/dev/null 2>&1 && has_asset=1
  hesabix_branding_find_file "$dir" "Icon-512.png" "icons" "." >/dev/null 2>&1 && has_asset=1
  hesabix_branding_find_file "$dir" "favicon.ico" "icons" "." >/dev/null 2>&1 && has_asset=1
  hesabix_branding_find_file "$dir" "favicon.png" "icons" "." >/dev/null 2>&1 && has_asset=1

  if [[ "$has_asset" -eq 0 && -z "$fa" && -z "$en" ]]; then
    echo "[branding] warn: custom pack has no logos/icons/names — using default" >&2
    _HESABIX_BRANDING_EFFECTIVE_MODE="default"
    HESABIX_BRANDING_NAME_FA=""
    HESABIX_BRANDING_NAME_EN=""
    export BRANDING_MODE="default"
    return 0
  fi

  _HESABIX_BRANDING_EFFECTIVE_MODE="custom"
  HESABIX_BRANDING_NAME_FA="$fa"
  HESABIX_BRANDING_NAME_EN="$en"
  export BRANDING_MODE="custom"
  export BRANDING_DIR="$dir"
  export APP_NAME_FA="$fa"
  export APP_NAME_EN="$en"
}

hesabix_branding_backup_file() {
  local src="$1"
  local backup_root="$2"
  local app_dir="$3"
  [[ -f "$src" ]] || return 0
  local rel="${src#"$app_dir"/}"
  local dest="${backup_root}/${rel}"
  mkdir -p "$(dirname "$dest")"
  cp -a "$src" "$dest"
}

hesabix_branding_install_file() {
  local src="$1"
  local dest="$2"
  local backup_root="$3"
  local app_dir="$4"
  [[ -f "$src" ]] || return 1
  mkdir -p "$(dirname "$dest")"
  hesabix_branding_backup_file "$dest" "$backup_root" "$app_dir"
  cp -f "$src" "$dest"
  touch "$dest" 2>/dev/null || true
  echo "[branding] overlay: ${dest#"$app_dir"/}"
}

hesabix_branding_patch_web_names() {
  local app_dir="$1"
  local fa="$2"
  local en="$3"
  [[ -n "$fa" || -n "$en" ]] || return 0

  local fa_use="${fa:-$en}"
  local en_use="${en:-$fa}"

  python3 - "$app_dir" "$fa_use" "$en_use" <<'PY'
import pathlib
import re
import sys

app_dir = pathlib.Path(sys.argv[1])
fa = sys.argv[2]
en = sys.argv[3]

# --- index.html ---
index = app_dir / "web" / "index.html"
if index.is_file():
    t = index.read_text(encoding="utf-8")
    t = re.sub(
        r'(<meta\s+name="apple-mobile-web-app-title"\s+content=")[^"]*(")',
        rf'\1{en}\2',
        t,
        count=1,
    )
    t = re.sub(r"(<title>)[^<]*(</title>)", rf"\1{en}\2", t, count=1, flags=re.I)
    t = re.sub(
        r'(<meta\s+name="description"\s+content=")[^"]*(")',
        rf'\1{en} - سیستم مدیریت مالی\2',
        t,
        count=1,
    )
    t = re.sub(r'(alt=")Hesabix(")', rf'\1{en}\2', t)
    t = re.sub(
        r'(id="loader-title">)حسابیکس(</h1>)',
        rf"\1{fa}\2",
        t,
        count=1,
    )
    index.write_text(t, encoding="utf-8")
    print("[branding] patched web/index.html names")

# --- manifest.json ---
manifest = app_dir / "web" / "manifest.json"
if manifest.is_file():
    t = manifest.read_text(encoding="utf-8")
    t = re.sub(r'("name"\s*:\s*")[^"]*(")', rf'\1{en}\2', t, count=1)
    t = re.sub(r'("short_name"\s*:\s*")[^"]*(")', rf'\1{en}\2', t, count=1)
    t = re.sub(
        r'("description"\s*:\s*")[^"]*(")',
        rf'\1{en} - سیستم مدیریت مالی\2',
        t,
        count=1,
    )
    manifest.write_text(t, encoding="utf-8")
    print("[branding] patched web/manifest.json names")

# --- loader JS ---
loader = app_dir / "web" / "hesabix_web_loader.js"
if loader.is_file():
    t = loader.read_text(encoding="utf-8")
    t = re.sub(
        r"(fa:\s*\{\s*title:\s*')[^']*(')",
        rf"\1{fa}\2",
        t,
        count=1,
    )
    t = re.sub(
        r"(en:\s*\{\s*title:\s*')[^']*(')",
        rf"\1{en}\2",
        t,
        count=1,
    )
    t = re.sub(r"(logo\.alt\s*=\s*')Hesabix(')", rf"\1{en}\2", t, count=1)
    # لوگوی رنگی کاستوم: در تم روشن هم خود تصویر نشان داده شود (بدون mask/tint)
    if "HESABIX_BRAND_KEEP_LOGO_COLORS" not in t:
        t = t.replace(
            "logo.src = 'images/logo-light.png';",
            "logo.src = 'images/logo-light.png';\n"
            "      var HESABIX_BRAND_KEEP_LOGO_COLORS = true;",
            1,
        )
    # dark branch already shows as-is; force light branch to same behavior when flag set
    old_light = """} else {
        // سیلوئت سفید مخفی؛ رنگ برند روی wrap با mask
        logo.style.opacity = '0';
        if (wrap) {
          wrap.classList.add('loader-logo-wrap--tinted');
          wrap.style.setProperty('--loader-logo-tint', readBrandFromStorage());
        }
      }"""
    new_light = """} else if (typeof HESABIX_BRAND_KEEP_LOGO_COLORS !== 'undefined' && HESABIX_BRAND_KEEP_LOGO_COLORS) {
        logo.style.opacity = '1';
        logo.style.filter = 'none';
        if (wrap) {
          wrap.classList.remove('loader-logo-wrap--tinted');
          wrap.style.removeProperty('--loader-logo-tint');
        }
      } else {
        // سیلوئت سفید مخفی؛ رنگ برند روی wrap با mask
        logo.style.opacity = '0';
        if (wrap) {
          wrap.classList.add('loader-logo-wrap--tinted');
          wrap.style.setProperty('--loader-logo-tint', readBrandFromStorage());
        }
      }"""
    if old_light in t:
        t = t.replace(old_light, new_light, 1)
    loader.write_text(t, encoding="utf-8")
    print("[branding] patched web/hesabix_web_loader.js names")
PY
}

# Apply overlays to Flutter project sources (must restore after build).
hesabix_branding_apply() {
  local app_dir="$1"
  hesabix_branding_resolve

  if [[ "$_HESABIX_BRANDING_EFFECTIVE_MODE" != "custom" ]]; then
    echo "[branding] mode=default — keeping Hesabix logos and names"
    _HESABIX_BRANDING_APPLIED=0
    return 0
  fi

  local dir="${BRANDING_DIR}"
  local backup
  backup="$(mktemp -d /tmp/hesabix-branding.XXXXXX)"
  _HESABIX_BRANDING_BACKUP_DIR="$backup"

  echo "[branding] mode=custom dir=$dir"
  [[ -n "${HESABIX_BRANDING_NAME_FA}" ]] && echo "[branding] name FA: ${HESABIX_BRANDING_NAME_FA}"
  [[ -n "${HESABIX_BRANDING_NAME_EN}" ]] && echo "[branding] name EN: ${HESABIX_BRANDING_NAME_EN}"

  local src

  # Logos → Flutter assets + web splash images
  if src="$(hesabix_branding_find_file "$dir" "logo-light.png" "logos" "images" ".")"; then
    hesabix_branding_install_file "$src" "$app_dir/assets/images/logo-light.png" "$backup" "$app_dir"
    hesabix_branding_install_file "$src" "$app_dir/web/images/logo-light.png" "$backup" "$app_dir"
    # Also used as web favicon.png fallback in some installs
    if [[ -f "$app_dir/web/favicon.png" ]] && \
       ! hesabix_branding_find_file "$dir" "favicon.png" "icons" "." >/dev/null 2>&1; then
      : # leave favicon.png unless pack provides one; don't force logo as favicon
    fi
  fi
  if src="$(hesabix_branding_find_file "$dir" "logo-blue.png" "logos" "images" ".")"; then
    hesabix_branding_install_file "$src" "$app_dir/assets/images/logo-blue.png" "$backup" "$app_dir"
    hesabix_branding_install_file "$src" "$app_dir/web/images/logo-blue.png" "$backup" "$app_dir"
  fi
  if src="$(hesabix_branding_find_file "$dir" "logo-light.svg" "logos" "images" ".")"; then
    hesabix_branding_install_file "$src" "$app_dir/assets/images/logo-light.svg" "$backup" "$app_dir"
    if [[ -f "$app_dir/web/assets/images/logo-light.svg" ]]; then
      hesabix_branding_install_file "$src" "$app_dir/web/assets/images/logo-light.svg" "$backup" "$app_dir"
    fi
  fi
  if src="$(hesabix_branding_find_file "$dir" "logo32.png" "logos" "images" ".")"; then
    hesabix_branding_install_file "$src" "$app_dir/assets/images/logo32.png" "$backup" "$app_dir"
  elif src="$(hesabix_branding_find_file "$dir" "logo-light.png" "logos" "images" ".")"; then
    # لانچر موبایل از logo32 استفاده می‌کند
    hesabix_branding_install_file "$src" "$app_dir/assets/images/logo32.png" "$backup" "$app_dir"
  fi
  if src="$(hesabix_branding_find_file "$dir" "logo.png" "logos" "images" ".")"; then
    hesabix_branding_install_file "$src" "$app_dir/assets/images/logo.png" "$backup" "$app_dir"
  elif src="$(hesabix_branding_find_file "$dir" "logo-light.png" "logos" "images" ".")"; then
    hesabix_branding_install_file "$src" "$app_dir/assets/images/logo.png" "$backup" "$app_dir"
  fi

  # PWA icons
  local icon_name pack_has_192=0 pack_has_512=0 pack_has_m192=0 pack_has_m512=0
  for icon_name in Icon-192.png Icon-512.png Icon-maskable-192.png Icon-maskable-512.png; do
    if src="$(hesabix_branding_find_file "$dir" "$icon_name" "icons" ".")"; then
      hesabix_branding_install_file "$src" "$app_dir/web/icons/$icon_name" "$backup" "$app_dir"
      case "$icon_name" in
        Icon-192.png) pack_has_192=1 ;;
        Icon-512.png) pack_has_512=1 ;;
        Icon-maskable-192.png) pack_has_m192=1 ;;
        Icon-maskable-512.png) pack_has_m512=1 ;;
      esac
    fi
  done
  # Fill missing maskable from base icons when pack only shipped Icon-192/512
  if [[ "$pack_has_192" -eq 1 && "$pack_has_m192" -eq 0 ]]; then
    if src="$(hesabix_branding_find_file "$dir" "Icon-192.png" "icons" ".")"; then
      hesabix_branding_install_file "$src" "$app_dir/web/icons/Icon-maskable-192.png" "$backup" "$app_dir"
    fi
  fi
  if [[ "$pack_has_512" -eq 1 && "$pack_has_m512" -eq 0 ]]; then
    if src="$(hesabix_branding_find_file "$dir" "Icon-512.png" "icons" ".")"; then
      hesabix_branding_install_file "$src" "$app_dir/web/icons/Icon-maskable-512.png" "$backup" "$app_dir"
    fi
  fi

  if src="$(hesabix_branding_find_file "$dir" "favicon.ico" "icons" ".")"; then
    hesabix_branding_install_file "$src" "$app_dir/web/favicon.ico" "$backup" "$app_dir"
  fi
  if src="$(hesabix_branding_find_file "$dir" "favicon.png" "icons" ".")"; then
    hesabix_branding_install_file "$src" "$app_dir/web/favicon.png" "$backup" "$app_dir"
  fi

  # Backup then patch name-bearing web sources
  for f in web/index.html web/manifest.json web/hesabix_web_loader.js; do
    [[ -f "$app_dir/$f" ]] && hesabix_branding_backup_file "$app_dir/$f" "$backup" "$app_dir"
  done
  hesabix_branding_patch_web_names "$app_dir" "${HESABIX_BRANDING_NAME_FA}" "${HESABIX_BRANDING_NAME_EN}"

  _HESABIX_BRANDING_APPLIED=1
}

hesabix_branding_restore() {
  if [[ "$_HESABIX_BRANDING_APPLIED" != "1" ]]; then
    return 0
  fi
  local backup="${_HESABIX_BRANDING_BACKUP_DIR:-}"
  local app_dir="${1:-}"
  if [[ -z "$backup" || ! -d "$backup" ]]; then
    _HESABIX_BRANDING_APPLIED=0
    return 0
  fi
  if [[ -z "$app_dir" ]]; then
    echo "[branding] warn: restore skipped (no app_dir)" >&2
    rm -rf "$backup" 2>/dev/null || true
    _HESABIX_BRANDING_APPLIED=0
    _HESABIX_BRANDING_BACKUP_DIR=""
    return 0
  fi
  echo "[branding] restoring original project assets from backup..."
  local rel
  while IFS= read -r -d '' rel; do
    rel="${rel#./}"
    mkdir -p "$(dirname "$app_dir/$rel")"
    cp -f "$backup/$rel" "$app_dir/$rel"
  done < <(cd "$backup" && find . -type f -print0)
  rm -rf "$backup" 2>/dev/null || true
  _HESABIX_BRANDING_BACKUP_DIR=""
  _HESABIX_BRANDING_APPLIED=0
  echo "[branding] restore complete"
}

# Copy branding files into the Flutter web output so cached assets cannot
# keep the default Hesabix logos after a custom build.
hesabix_branding_stamp_build_output() {
  local build_dir="$1"
  [[ -n "$build_dir" && -d "$build_dir" ]] || return 0
  hesabix_branding_resolve
  if [[ "$_HESABIX_BRANDING_EFFECTIVE_MODE" != "custom" ]]; then
    return 0
  fi
  local dir="${BRANDING_DIR}"
  [[ -d "$dir" ]] || return 0
  echo "[branding] stamping custom logos/icons into $build_dir"

  local src dest
  _hesabix_branding_stamp_one() {
    local from="$1"
    local to="$2"
    [[ -f "$from" ]] || return 0
    mkdir -p "$(dirname "$to")"
    cp -f "$from" "$to"
    touch "$to" 2>/dev/null || true
    echo "[branding] stamped: ${to#"$build_dir"/}"
  }

  if src="$(hesabix_branding_find_file "$dir" "logo-light.png" "logos" "images" ".")"; then
    _hesabix_branding_stamp_one "$src" "$build_dir/images/logo-light.png"
    _hesabix_branding_stamp_one "$src" "$build_dir/assets/assets/images/logo-light.png"
    _hesabix_branding_stamp_one "$src" "$build_dir/assets/images/logo-light.png"
  fi
  if src="$(hesabix_branding_find_file "$dir" "logo-blue.png" "logos" "images" ".")"; then
    _hesabix_branding_stamp_one "$src" "$build_dir/images/logo-blue.png"
    _hesabix_branding_stamp_one "$src" "$build_dir/assets/assets/images/logo-blue.png"
    _hesabix_branding_stamp_one "$src" "$build_dir/assets/images/logo-blue.png"
  elif src="$(hesabix_branding_find_file "$dir" "logo-light.png" "logos" "images" ".")"; then
    _hesabix_branding_stamp_one "$src" "$build_dir/images/logo-blue.png"
    _hesabix_branding_stamp_one "$src" "$build_dir/assets/assets/images/logo-blue.png"
  fi
  if src="$(hesabix_branding_find_file "$dir" "logo.png" "logos" "images" ".")" \
     || src="$(hesabix_branding_find_file "$dir" "logo-light.png" "logos" "images" ".")"; then
    _hesabix_branding_stamp_one "$src" "$build_dir/assets/assets/images/logo.png"
  fi
  if src="$(hesabix_branding_find_file "$dir" "logo32.png" "logos" "images" ".")" \
     || src="$(hesabix_branding_find_file "$dir" "logo-light.png" "logos" "images" ".")"; then
    _hesabix_branding_stamp_one "$src" "$build_dir/assets/assets/images/logo32.png"
  fi

  local icon_name
  for icon_name in Icon-192.png Icon-512.png Icon-maskable-192.png Icon-maskable-512.png; do
    if src="$(hesabix_branding_find_file "$dir" "$icon_name" "icons" ".")"; then
      _hesabix_branding_stamp_one "$src" "$build_dir/icons/$icon_name"
    fi
  done
  if src="$(hesabix_branding_find_file "$dir" "favicon.ico" "icons" ".")"; then
    _hesabix_branding_stamp_one "$src" "$build_dir/favicon.ico"
  fi
  if src="$(hesabix_branding_find_file "$dir" "favicon.png" "icons" ".")"; then
    _hesabix_branding_stamp_one "$src" "$build_dir/favicon.png"
  fi
}

# Append branding name dart-defines onto global array DART_DEFINE_ARGS.
hesabix_branding_append_dart_defines() {
  # Accept optional array name for compatibility; always mutate DART_DEFINE_ARGS.
  hesabix_branding_resolve
  if [[ "$_HESABIX_BRANDING_EFFECTIVE_MODE" != "custom" ]]; then
    return 0
  fi
  if [[ -n "${HESABIX_BRANDING_NAME_EN}" ]]; then
    DART_DEFINE_ARGS+=(--dart-define "APP_NAME_EN=${HESABIX_BRANDING_NAME_EN}")
  fi
  if [[ -n "${HESABIX_BRANDING_NAME_FA}" ]]; then
    DART_DEFINE_ARGS+=(--dart-define "APP_NAME_FA=${HESABIX_BRANDING_NAME_FA}")
  fi
  # لوگوی رنگی کاستوم را با ColorFilter تم حسابیکس بازنویسی نکن
  DART_DEFINE_ARGS+=(--dart-define "BRAND_LOGO_TINT=0")
}

hesabix_branding_persist() {
  local mode="${1:-default}"
  local dir="${2:-}"
  local fa="${3:-}"
  local en="${4:-}"
  mode="$(hesabix_branding_normalize_mode "$mode")"
  local env_file="${HESABIX_DEPLOY_ENV:-${APP_ROOT:-/opt/hesabix}/.deploy_env}"
  if [[ ! -f "$env_file" ]]; then
    echo "Deploy env not found: $env_file" >&2
    return 1
  fi
  if ! declare -F hesabix_patch_env_file >/dev/null 2>&1; then
    echo "hesabix_patch_env_file unavailable" >&2
    return 1
  fi
  if [[ "$mode" == "default" ]]; then
    hesabix_patch_env_file "$env_file" \
      "BRANDING_MODE=default" \
      "BRANDING_DIR=" \
      "APP_NAME_FA=" \
      "APP_NAME_EN="
  else
    [[ -n "$dir" ]] || dir="$(hesabix_branding_default_dir)"
    hesabix_patch_env_file "$env_file" \
      "BRANDING_MODE=custom" \
      "BRANDING_DIR=${dir}" \
      "APP_NAME_FA=${fa}" \
      "APP_NAME_EN=${en}"
  fi
  echo "[branding] saved to $env_file (mode=$mode)"
}

hesabix_branding_show() {
  hesabix_load_deploy_env 2>/dev/null || true
  hesabix_branding_resolve
  echo "UI branding:"
  echo "  mode: ${_HESABIX_BRANDING_EFFECTIVE_MODE}"
  echo "  dir:  ${BRANDING_DIR:-$(hesabix_branding_default_dir)}"
  echo "  name FA: ${HESABIX_BRANDING_NAME_FA:-«default حسابیکس»}"
  echo "  name EN: ${HESABIX_BRANDING_NAME_EN:-«default Hesabix»}"
  if [[ "$_HESABIX_BRANDING_EFFECTIVE_MODE" == "custom" && -d "${BRANDING_DIR:-}" ]]; then
    echo "  pack files:"
    local f
    for f in logo-light.png logo-blue.png Icon-192.png Icon-512.png favicon.ico names.json; do
      if hesabix_branding_find_file "${BRANDING_DIR}" "$f" "logos" "images" "icons" "meta" "." >/dev/null 2>&1; then
        echo "    ✓ $f"
      else
        echo "    · $f (missing)"
      fi
    done
  fi
}

hesabix_branding_command() {
  local action="${1:-show}"
  shift || true
  local dir="" fa="" en="" rebuild=0
  case "$action" in
    show|status)
      hesabix_branding_show
      return 0
      ;;
    default|reset)
      while [[ $# -gt 0 ]]; do
        case "$1" in
          --rebuild) rebuild=1; shift ;;
          *) echo "Unknown arg: $1" >&2; return 1 ;;
        esac
      done
      hesabix_branding_persist "default"
      if [[ "$rebuild" -eq 1 ]]; then
        # shellcheck source=hesabix_domains.sh
        source "${HESABIX_BRANDING_LIB_DIR}/hesabix_domains.sh"
        hesabix_rebuild_frontend
      else
        echo "Saved. Next web build / hesabix -update will use Hesabix defaults."
        echo "Rebuild now: sudo hesabix -branding apply"
      fi
      return 0
      ;;
    set)
      while [[ $# -gt 0 ]]; do
        case "$1" in
          --dir)
            [[ $# -ge 2 ]] || { echo "--dir needs a path" >&2; return 1; }
            dir="$2"; shift 2 ;;
          --name-fa|--fa)
            [[ $# -ge 2 ]] || { echo "--name-fa needs a value" >&2; return 1; }
            fa="$2"; shift 2 ;;
          --name-en|--en)
            [[ $# -ge 2 ]] || { echo "--name-en needs a value" >&2; return 1; }
            en="$2"; shift 2 ;;
          --rebuild) rebuild=1; shift ;;
          *) echo "Unknown arg: $1" >&2; return 1 ;;
        esac
      done
      [[ -n "$dir" ]] || dir="$(hesabix_branding_default_dir)"
      if [[ ! -d "$dir" ]]; then
        echo "Branding directory does not exist: $dir" >&2
        echo "Create it and add logo-light.png / icons / names.json first." >&2
        return 1
      fi
      # Prefer names.json when flags omitted
      if [[ -z "$fa" || -z "$en" ]]; then
        BRANDING_MODE_OVERRIDE=custom
        BRANDING_DIR_OVERRIDE="$dir"
        APP_NAME_FA_OVERRIDE="$fa"
        APP_NAME_EN_OVERRIDE="$en"
        hesabix_branding_resolve
        fa="${HESABIX_BRANDING_NAME_FA}"
        en="${HESABIX_BRANDING_NAME_EN}"
        unset BRANDING_MODE_OVERRIDE BRANDING_DIR_OVERRIDE APP_NAME_FA_OVERRIDE APP_NAME_EN_OVERRIDE
      fi
      hesabix_branding_persist "custom" "$dir" "$fa" "$en"
      if [[ "$rebuild" -eq 1 ]]; then
        source "${HESABIX_BRANDING_LIB_DIR}/hesabix_domains.sh"
        hesabix_rebuild_frontend
      else
        echo "Saved. Apply on next build: sudo hesabix -branding apply"
        echo "Or: sudo hesabix -update"
      fi
      return 0
      ;;
    apply|rebuild)
      hesabix_load_deploy_env || return 1
      # shellcheck source=hesabix_domains.sh
      source "${HESABIX_BRANDING_LIB_DIR}/hesabix_domains.sh"
      hesabix_rebuild_frontend
      return $?
      ;;
    *)
      echo "Usage:" >&2
      echo "  hesabix -branding show" >&2
      echo "  hesabix -branding set --dir /opt/hesabix/branding [--name-fa …] [--name-en …] [--rebuild]" >&2
      echo "  hesabix -branding default [--rebuild]" >&2
      echo "  hesabix -branding apply" >&2
      return 1
      ;;
  esac
}
