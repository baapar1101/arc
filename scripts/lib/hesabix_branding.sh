#!/usr/bin/env bash
# Build-time UI branding overlay for Hesabix Flutter web and Android.
#
# Pack layout (flat or nested — first match wins):
#   BRANDING_DIR/
#     names.json                 # { "fa": "…", "en": "…" }  (optional)
#     logo-light.png             # or logos/ / images/
#     logo-blue.png              # optional
#     Icon-192.png …             # or icons/  (Android launcher uses Icon-512)
#     favicon.ico / favicon.png  # optional (web)
#     ic_stat.png                # optional white silhouette for Android status bar
#
# Env / .deploy_env:
#   BRANDING_MODE=default|custom   (empty → default)
#   BRANDING_DIR=/opt/hesabix/branding
#   APP_NAME_FA=…  APP_NAME_EN=…
#
# When mode is default (or unset): no-op — Hesabix logos/names stay as in the repo.
# Android APK applies the same pack via build_android.sh (overlay + dart-define + restore).

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
    # لودر اولیه: پیش‌فرض تم روشن = لوگوی رنگی؛ نسخه سفید جدا preload می‌شود
    if 'href="images/logo-blue.png" as="image"' not in t:
        t = t.replace(
            '<link rel="preload" href="images/logo-light.png" as="image" type="image/png">',
            '<link rel="preload" href="images/logo-blue.png" as="image" type="image/png">\n'
            '  <link rel="preload" href="images/logo-light.png" as="image" type="image/png">',
            1,
        )
    t = re.sub(
        r'(class="loader-logo"\s*\n\s*src=")images/logo-light\.png(")',
        r'\1images/logo-blue.png\2',
        t,
        count=1,
    )
    t = t.replace('src="images/logo-light.png"', 'src="images/logo-blue.png"', 1)
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
    # تم روشن: logo-blue (رنگی) / تم تیره: logo-light (سفید) — بدون mask حسابیکس
    old_logo_block = """    if (logo) {
      logo.src = 'images/logo-light.png';
      logo.alt = '%s';
      if (dark) {
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
      }
    }""" % en
    # alt may still be Hesabix if the replace above did not run on a custom already-patched file
    old_logo_block_hesabix = old_logo_block.replace("logo.alt = '%s';" % en, "logo.alt = 'Hesabix';")
    new_logo_block = """    if (logo) {
      logo.src = dark ? 'images/logo-light.png' : 'images/logo-blue.png';
      logo.alt = '%s';
      logo.style.opacity = '1';
      logo.style.filter = 'none';
      if (wrap) {
        wrap.classList.remove('loader-logo-wrap--tinted');
        wrap.style.removeProperty('--loader-logo-tint');
      }
    }""" % en
    if old_logo_block in t:
        t = t.replace(old_logo_block, new_logo_block, 1)
    elif old_logo_block_hesabix in t:
        t = t.replace(old_logo_block_hesabix, new_logo_block, 1)
    else:
        # fallback: just switch the asset by theme
        t = t.replace(
            "logo.src = 'images/logo-light.png';",
            "logo.src = dark ? 'images/logo-light.png' : 'images/logo-blue.png';",
            1,
        )
        old_light = """} else {
        // سیلوئت سفید مخفی؛ رنگ برند روی wrap با mask
        logo.style.opacity = '0';
        if (wrap) {
          wrap.classList.add('loader-logo-wrap--tinted');
          wrap.style.setProperty('--loader-logo-tint', readBrandFromStorage());
        }
      }"""
        new_light = """} else {
        logo.style.opacity = '1';
        logo.style.filter = 'none';
        if (wrap) {
          wrap.classList.remove('loader-logo-wrap--tinted');
          wrap.style.removeProperty('--loader-logo-tint');
        }
      }"""
        if old_light in t:
            t = t.replace(old_light, new_light, 1)
    loader.write_text(t, encoding="utf-8")
    print("[branding] patched web/hesabix_web_loader.js names")
PY
}

hesabix_branding_patch_android_names() {
  local app_dir="$1"
  local fa="$2"
  local en="$3"
  [[ -n "$fa" || -n "$en" ]] || return 0
  local fa_use="${fa:-$en}"
  local en_use="${en:-$fa}"
  local values="$app_dir/android/app/src/main/res/values/strings.xml"
  local values_fa="$app_dir/android/app/src/main/res/values-fa/strings.xml"
  [[ -f "$values" || -f "$values_fa" ]] || return 0

  python3 - "$values" "$values_fa" "$fa_use" "$en_use" <<'PY'
import pathlib
import re
import sys
import xml.sax.saxutils as xml_escape

def patch(path: pathlib.Path, name: str) -> None:
    if not path.is_file() or not name:
        return
    raw = path.read_text(encoding="utf-8")
    escaped = xml_escape.escape(name)
    updated, n = re.subn(
        r'(<string\s+name="app_name">)[^<]*(</string>)',
        rf"\1{escaped}\2",
        raw,
        count=1,
    )
    if n:
        path.write_text(updated, encoding="utf-8")
        print(f"[branding] patched {path.name} app_name")
    else:
        print(f"[branding] warn: app_name string not found in {path}", file=sys.stderr)

values = pathlib.Path(sys.argv[1])
values_fa = pathlib.Path(sys.argv[2])
fa = sys.argv[3]
en = sys.argv[4]
patch(values, en)
patch(values_fa, fa)
PY
}

# Resize src onto dest in-place (dest must already exist). mode=fit|silhouette
hesabix_branding_overlay_resized() {
  local src="$1"
  local dest="$2"
  local backup_root="$3"
  local app_dir="$4"
  local mode="${5:-fit}"
  [[ -f "$src" && -f "$dest" ]] || return 0
  hesabix_branding_backup_file "$dest" "$backup_root" "$app_dir"
  local dest_mode=""
  dest_mode="$(stat -c '%a' "$dest" 2>/dev/null || true)"
  if python3 - "$src" "$dest" "$mode" <<'PY'
import sys
from pathlib import Path

try:
    from PIL import Image
except ImportError:
    print("[branding] warn: Pillow not installed; skip image overlay", file=sys.stderr)
    sys.exit(1)

src_path = Path(sys.argv[1])
dest_path = Path(sys.argv[2])
mode = sys.argv[3]

src = Image.open(src_path).convert("RGBA")
with Image.open(dest_path) as current:
    size = current.size

def to_white_silhouette(im: Image.Image) -> Image.Image:
    im = im.convert("RGBA")
    _r, _g, _b, a = im.split()
    amin, amax = a.getextrema()
    if amin >= 250:
        gray = im.convert("L")
        a = gray.point(lambda p: 0 if p > 245 else 255)
    white = Image.new("L", im.size, 255)
    return Image.merge("RGBA", (white, white, white, a))

if mode == "silhouette":
    src = to_white_silhouette(src)

fitted = src.resize(size, Image.Resampling.LANCZOS)
tmp = dest_path.with_suffix(dest_path.suffix + ".tmp")
fitted.save(tmp, "PNG")
tmp.replace(dest_path)
PY
  then
    [[ -n "$dest_mode" ]] && chmod "$dest_mode" "$dest" 2>/dev/null || true
    echo "[branding] overlay: ${dest#"$app_dir"/}"
  else
    echo "[branding] warn: failed to overlay ${dest#"$app_dir"/}" >&2
  fi
}

hesabix_branding_overlay_android_named() {
  local app_dir="$1"
  local src="$2"
  local basename="$3"
  local backup_root="$4"
  local mode="${5:-fit}"
  local res_root="$app_dir/android/app/src/main/res"
  [[ -f "$src" && -d "$res_root" ]] || return 0
  local dest
  while IFS= read -r -d '' dest; do
    hesabix_branding_overlay_resized "$src" "$dest" "$backup_root" "$app_dir" "$mode"
  done < <(find "$res_root" -type f -name "$basename" -print0 2>/dev/null)
}

hesabix_branding_apply_android_icons() {
  local app_dir="$1"
  local pack_dir="$2"
  local backup_root="$3"
  local res_root="$app_dir/android/app/src/main/res"
  [[ -d "$res_root" ]] || return 0

  local launcher="" logo_light="" logo_blue="" stat=""
  launcher="$(hesabix_branding_find_file "$pack_dir" "Icon-512.png" "icons" "." 2>/dev/null || true)"
  [[ -n "$launcher" ]] || launcher="$(hesabix_branding_find_file "$pack_dir" "Icon-192.png" "icons" "." 2>/dev/null || true)"
  [[ -n "$launcher" ]] || launcher="$(hesabix_branding_find_file "$pack_dir" "logo-light.png" "logos" "images" "." 2>/dev/null || true)"
  [[ -n "$launcher" ]] || launcher="$(hesabix_branding_find_file "$pack_dir" "logo-blue.png" "logos" "images" "." 2>/dev/null || true)"

  logo_light="$(hesabix_branding_find_file "$pack_dir" "logo-light.png" "logos" "images" "." 2>/dev/null || true)"
  logo_blue="$(hesabix_branding_find_file "$pack_dir" "logo-blue.png" "logos" "images" "." 2>/dev/null || true)"
  stat="$(hesabix_branding_find_file "$pack_dir" "ic_stat.png" "icons" "logos" "images" "." 2>/dev/null || true)"

  if [[ -n "$launcher" ]]; then
    echo "[branding] android launcher icons from $(basename "$launcher")"
    hesabix_branding_overlay_android_named "$app_dir" "$launcher" "ic_launcher.png" "$backup_root" "fit"
    hesabix_branding_overlay_android_named "$app_dir" "$launcher" "ic_launcher_foreground.png" "$backup_root" "fit"
  fi

  local large_dark="${logo_blue:-$logo_light}"
  local large_light="${logo_light:-$logo_blue}"
  if [[ -n "$large_dark" ]]; then
    hesabix_branding_overlay_android_named "$app_dir" "$large_dark" "ic_hesabix_logo.png" "$backup_root" "fit"
  fi
  if [[ -n "$large_light" ]]; then
    hesabix_branding_overlay_android_named "$app_dir" "$large_light" "ic_hesabix_logo_light.png" "$backup_root" "fit"
  fi
  # Native splash (launch_background.xml) uses ic_hesabix_logo / ic_hesabix_logo_light.

  local stat_src="${stat:-$logo_light}"
  [[ -n "$stat_src" ]] || stat_src="$logo_blue"
  if [[ -n "$stat_src" ]]; then
    local stat_mode="silhouette"
    [[ -n "$stat" ]] && stat_mode="fit"
    echo "[branding] android status-bar icon from $(basename "$stat_src") ($stat_mode)"
    hesabix_branding_overlay_android_named "$app_dir" "$stat_src" "ic_stat_hesabix.png" "$backup_root" "$stat_mode"
  fi
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

  # Android launcher name + native icons (only existing drawables; restore copies them back)
  for f in android/app/src/main/res/values/strings.xml android/app/src/main/res/values-fa/strings.xml; do
    [[ -f "$app_dir/$f" ]] && hesabix_branding_backup_file "$app_dir/$f" "$backup" "$app_dir"
  done
  hesabix_branding_patch_android_names "$app_dir" "${HESABIX_BRANDING_NAME_FA}" "${HESABIX_BRANDING_NAME_EN}"
  hesabix_branding_apply_android_icons "$app_dir" "$dir" "$backup"

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
    cp -a "$backup/$rel" "$app_dir/$rel"
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
    for f in logo-light.png logo-blue.png Icon-192.png Icon-512.png favicon.ico names.json ic_stat.png; do
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
        echo "Android APK uses the same .deploy_env on the next ./build_android.sh."
        echo "Rebuild web now: sudo hesabix -branding apply"
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
        echo "Saved. Apply web on next build: sudo hesabix -branding apply"
        echo "Or: sudo hesabix -update"
        echo "Android APK: ./build_android.sh (reads the same .deploy_env branding)"
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
      echo "  hesabix -branding apply          # rebuild Flutter web only" >&2
      echo "  Android APK uses the same pack: ./build_android.sh" >&2
      return 1
      ;;
  esac
}
