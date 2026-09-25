#!/usr/bin/env bash
# Interactive / status UI for PyPI and Flutter package mirrors.

HESABIX_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=hesabix_deploy_env.sh
source "${HESABIX_LIB_DIR}/hesabix_deploy_env.sh"
# shellcheck source=../mirror_config.sh
source "${HESABIX_LIB_DIR}/../mirror_config.sh"

declare -A HESABIX_MIRROR_HTTP_CODE=()

hesabix_mirrors_norm_url() {
  local url="${1:-}"
  url="${url%"${url##*[![:space:]]}"}"
  url="${url#"${url%%[![:space:]]*}"}"
  printf '%s' "${url%/}"
}

hesabix_mirrors_urls_equal() {
  local a b
  a="$(hesabix_mirrors_norm_url "${1:-}")"
  b="$(hesabix_mirrors_norm_url "${2:-}")"
  [[ -n "$a" && "$a" == "$b" ]]
}

hesabix_mirrors_format_status() {
  local code="${1:-000}"
  case "$code" in
    000|"") printf '%s' "unreachable" ;;
    2*) printf '%s' "ok" ;;
    301|302|303|307|308) printf '%s' "ok" ;;
    403) printf '%s' "blocked (403)" ;;
    404) printf '%s' "not found (404)" ;;
    429) printf '%s' "quota exceeded (429)" ;;
    5*) printf '%s' "server error (${code})" ;;
    *) printf '%s' "failed (${code})" ;;
  esac
}

hesabix_mirrors_probe_urls() {
  local -a urls=()
  local url i dir code
  HESABIX_MIRROR_HTTP_CODE=()
  for url in "$@"; do
    url="$(hesabix_mirrors_norm_url "$url")"
    [[ -n "$url" ]] || continue
    urls+=("$url")
  done
  [[ ${#urls[@]} -gt 0 ]] || return 0
  dir="$(mktemp -d)"
  for i in "${!urls[@]}"; do
    url="${urls[$i]}"
    (
      code="$(curl -sS -o /dev/null -w '%{http_code}' --connect-timeout 5 --max-time 10 -L --max-redirs 4 "${url}/" 2>/dev/null || true)"
      printf '%s' "${code:-000}" > "${dir}/${i}"
    ) &
  done
  wait
  for i in "${!urls[@]}"; do
    code="$(cat "${dir}/${i}" 2>/dev/null || true)"
    HESABIX_MIRROR_HTTP_CODE["${urls[$i]}"]="${code:-000}"
  done
  rm -rf "${dir}"
}

# id|label|url
hesabix_mirrors_pip_catalog() {
  printf '%s\n' \
    "hesabix|Hesabix (Iran)|${HESABIX_PIP_INDEX_URL}" \
    "official|Official PyPI|https://pypi.org/simple" \
    "tuna|Tsinghua (China)|https://pypi.tuna.tsinghua.edu.cn/simple" \
    "aliyun|Aliyun (China)|https://mirrors.aliyun.com/pypi/simple" \
    "devneeds|Devneeds|https://pypi.devneeds.ir/simple"
}

hesabix_mirrors_pub_catalog() {
  printf '%s\n' \
    "hesabix|Hesabix (Iran)|${HESABIX_PUB_HOSTED_URL}" \
    "pub_azs|pub-azs.ir (Iran)|https://pub-azs.ir" \
    "flutter_io_cn|China (flutter-io.cn)|https://pub.flutter-io.cn" \
    "tuna|Tsinghua (China)|https://mirrors.tuna.tsinghua.edu.cn/dart-pub" \
    "sjtu|SJTU (China)|https://mirror.sjtu.edu.cn/dart-pub" \
    "official|Official pub.dev|https://pub.dev" \
    "devneeds|Devneeds|https://dart.devneeds.ir"
}

hesabix_mirrors_storage_catalog() {
  printf '%s\n' \
    "hesabix|Hesabix (Iran)|${HESABIX_FLUTTER_STORAGE_BASE_URL}" \
    "pub_azs|pub-azs.ir (Iran)|https://pub-azs.ir" \
    "flutter_io_cn|China (storage.flutter-io.cn)|https://storage.flutter-io.cn" \
    "tuna|Tsinghua (China)|https://mirrors.tuna.tsinghua.edu.cn/flutter" \
    "sjtu|SJTU (China)|https://mirror.sjtu.edu.cn" \
    "official|Official Google|https://storage.googleapis.com" \
    "devneeds|Devneeds|https://flutter.devneeds.ir"
}

hesabix_mirrors_catalog_has_url() {
  local want="$1" line id label url
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    IFS='|' read -r id label url <<<"$line"
    if hesabix_mirrors_urls_equal "$url" "$want"; then
      return 0
    fi
  done
  return 1
}

# Prints numbered menu rows: n|id|label|url|selected(0/1)
hesabix_mirrors_build_menu() {
  local catalog_fn="$1"
  local current_url="$2"
  local n=1
  local line id label url selected
  local found_current=0
  current_url="$(hesabix_mirrors_norm_url "$current_url")"

  if [[ -n "$current_url" ]] && ! "$catalog_fn" | hesabix_mirrors_catalog_has_url "$current_url"; then
    printf '%s\n' "${n}|custom|Current custom|${current_url}|1"
    found_current=1
    n=$((n + 1))
  fi

  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    IFS='|' read -r id label url <<<"$line"
    url="$(hesabix_mirrors_norm_url "$url")"
    selected=0
    if [[ "$found_current" -eq 0 ]] && hesabix_mirrors_urls_equal "$url" "$current_url"; then
      selected=1
      found_current=1
    fi
    printf '%s\n' "${n}|${id}|${label}|${url}|${selected}"
    n=$((n + 1))
  done < <("$catalog_fn")

  printf '%s\n' "${n}|custom_input|Custom URL||0"
}

hesabix_mirrors_print_menu() {
  local title="$1"
  local current_url="$2"
  shift 2
  local row n id label url selected mark status code
  echo
  echo "=== ${title} ==="
  if [[ -n "$current_url" ]]; then
    echo "Current: ${current_url}"
  else
    echo "Current: (not set)"
  fi
  echo
  while IFS= read -r row; do
    [[ -n "$row" ]] || continue
    IFS='|' read -r n id label url selected <<<"$row"
    mark=" "
    [[ "$selected" == "1" ]] && mark="*"
    if [[ "$id" == "custom_input" ]]; then
      printf '  %s [%s] %s\n' "$mark" "$n" "$label"
      continue
    fi
    code="${HESABIX_MIRROR_HTTP_CODE[$(hesabix_mirrors_norm_url "$url")]:-000}"
    status="$(hesabix_mirrors_format_status "$code")"
    printf '  %s [%s] %s\n      %s  —  %s\n' "$mark" "$n" "$label" "$url" "$status"
  done
  echo "  * = currently saved"
}

hesabix_mirrors_collect_probe_urls() {
  local line id label url
  while IFS= read -r line; do
    IFS='|' read -r id label url <<<"$line"
    [[ -n "$url" ]] && printf '%s\n' "$(hesabix_mirrors_norm_url "$url")"
  done
}

hesabix_mirrors_flutter_preset_for_urls() {
  local pub storage
  pub="$(hesabix_mirrors_norm_url "${1:-}")"
  storage="$(hesabix_mirrors_norm_url "${2:-}")"
  if hesabix_mirrors_urls_equal "$pub" "${HESABIX_PUB_HOSTED_URL}" \
    && hesabix_mirrors_urls_equal "$storage" "${HESABIX_FLUTTER_STORAGE_BASE_URL}"; then
    printf '%s' "hesabix"; return 0
  fi
  if hesabix_mirrors_urls_equal "$pub" "https://pub-azs.ir" \
    && hesabix_mirrors_urls_equal "$storage" "https://pub-azs.ir"; then
    printf '%s' "pub_azs"; return 0
  fi
  if hesabix_mirrors_urls_equal "$pub" "https://pub.flutter-io.cn" \
    && hesabix_mirrors_urls_equal "$storage" "https://storage.flutter-io.cn"; then
    printf '%s' "flutter_io_cn"; return 0
  fi
  if hesabix_mirrors_urls_equal "$pub" "https://mirrors.tuna.tsinghua.edu.cn/dart-pub" \
    && hesabix_mirrors_urls_equal "$storage" "https://mirrors.tuna.tsinghua.edu.cn/flutter"; then
    printf '%s' "tuna"; return 0
  fi
  if hesabix_mirrors_urls_equal "$pub" "https://mirror.sjtu.edu.cn/dart-pub" \
    && hesabix_mirrors_urls_equal "$storage" "https://mirror.sjtu.edu.cn"; then
    printf '%s' "sjtu"; return 0
  fi
  if hesabix_mirrors_urls_equal "$pub" "https://pub.dev" \
    && hesabix_mirrors_urls_equal "$storage" "https://storage.googleapis.com"; then
    printf '%s' "official"; return 0
  fi
  if hesabix_mirrors_urls_equal "$pub" "https://dart.devneeds.ir" \
    && hesabix_mirrors_urls_equal "$storage" "https://flutter.devneeds.ir"; then
    printf '%s' "custom"; return 0
  fi
  printf '%s' "custom"
}

hesabix_mirrors_pip_preset_for_url() {
  local url
  url="$(hesabix_mirrors_norm_url "${1:-}")"
  case "$url" in
    "${HESABIX_PIP_INDEX_URL%/}"|"${HESABIX_PIP_INDEX_URL}") printf '%s' "hesabix" ;;
    "https://pypi.org/simple") printf '%s' "official" ;;
    "https://pypi.tuna.tsinghua.edu.cn/simple") printf '%s' "tuna" ;;
    "https://mirrors.aliyun.com/pypi/simple") printf '%s' "aliyun" ;;
    *) printf '%s' "custom" ;;
  esac
}

hesabix_mirrors_pick_from_menu() {
  local prompt="$1"
  local menu="$2"
  local current_url="$3"
  local choice row n id label url selected
  local max=0
  while IFS= read -r row; do
    IFS='|' read -r n id label url selected <<<"$row"
    [[ "$n" =~ ^[0-9]+$ ]] || continue
    (( n > max )) && max=$n
  done <<<"$menu"

  while true; do
    read -rp "${prompt} [Enter = keep current]: " choice
    if [[ -z "$choice" ]]; then
      printf '%s' "$(hesabix_mirrors_norm_url "$current_url")"
      return 0
    fi
    if [[ ! "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > max )); then
      echo "Invalid number. Choose between 1 and ${max}." >&2
      continue
    fi
    while IFS= read -r row; do
      IFS='|' read -r n id label url selected <<<"$row"
      [[ "$n" == "$choice" ]] || continue
      if [[ "$id" == "custom_input" ]]; then
        local custom=""
        read -rp "Full mirror URL: " custom
        custom="$(hesabix_mirrors_norm_url "$custom")"
        if [[ -z "$custom" ]]; then
          echo "Empty URL; keeping current selection." >&2
          printf '%s' "$(hesabix_mirrors_norm_url "$current_url")"
          return 0
        fi
        printf '%s' "$custom"
        return 0
      fi
      printf '%s' "$(hesabix_mirrors_norm_url "$url")"
      return 0
    done <<<"$menu"
  done
}

hesabix_mirrors_resolve_choice() {
  local raw="$1"
  local kind="$2"
  local line id label url
  raw="$(hesabix_mirrors_norm_url "$raw")"
  [[ -n "$raw" ]] || return 1
  if [[ "$raw" == http://* || "$raw" == https://* ]]; then
    printf '%s' "$raw"
    return 0
  fi
  raw="${raw,,}"
  raw="${raw//-/_}"
  local catalog_fn=""
  case "$kind" in
    pip) catalog_fn=hesabix_mirrors_pip_catalog ;;
    pub) catalog_fn=hesabix_mirrors_pub_catalog ;;
    storage) catalog_fn=hesabix_mirrors_storage_catalog ;;
    *) return 1 ;;
  esac
  while IFS= read -r line; do
    IFS='|' read -r id label url <<<"$line"
    id="${id,,}"
    if [[ "$id" == "$raw" || "$id" == "${raw//_/-}" ]]; then
      printf '%s' "$(hesabix_mirrors_norm_url "$url")"
      return 0
    fi
  done < <("$catalog_fn")
  return 1
}

hesabix_mirrors_load() {
  hesabix_load_deploy_env || return 1
  hesabix_apply_pip_mirror_env >/dev/null 2>&1 || true
  hesabix_apply_flutter_mirror_env >/dev/null 2>&1 || true
}

hesabix_mirrors_show() {
  hesabix_mirrors_load || return 1
  local pip_url pub_url storage_url
  pip_url="$(hesabix_mirrors_norm_url "${PIP_INDEX_URL:-}")"
  pub_url="$(hesabix_mirrors_norm_url "${PUB_HOSTED_URL:-}")"
  storage_url="$(hesabix_mirrors_norm_url "${FLUTTER_STORAGE_BASE_URL:-}")"

  echo "Checking mirror availability..."
  local -a probe=()
  mapfile -t probe < <(
    {
      hesabix_mirrors_pip_catalog
      hesabix_mirrors_pub_catalog
      hesabix_mirrors_storage_catalog
    } | hesabix_mirrors_collect_probe_urls
    [[ -n "$pip_url" ]] && printf '%s\n' "$pip_url"
    [[ -n "$pub_url" ]] && printf '%s\n' "$pub_url"
    [[ -n "$storage_url" ]] && printf '%s\n' "$storage_url"
  )
  local -A uniq=()
  local -a unique_urls=()
  local u
  for u in "${probe[@]}"; do
    u="$(hesabix_mirrors_norm_url "$u")"
    [[ -n "$u" && -z "${uniq[$u]:-}" ]] || continue
    uniq[$u]=1
    unique_urls+=("$u")
  done
  hesabix_mirrors_probe_urls "${unique_urls[@]}"

  local pip_menu pub_menu storage_menu
  pip_menu="$(hesabix_mirrors_build_menu hesabix_mirrors_pip_catalog "$pip_url")"
  pub_menu="$(hesabix_mirrors_build_menu hesabix_mirrors_pub_catalog "$pub_url")"
  storage_menu="$(hesabix_mirrors_build_menu hesabix_mirrors_storage_catalog "$storage_url")"

  echo
  echo "Hesabix mirror status"
  echo "Saved in: ${HESABIX_DEPLOY_ENV}"
  echo "Python preset: ${PIP_MIRROR:-—}"
  echo "Flutter preset: ${FLUTTER_MIRROR:-—}"
  hesabix_mirrors_print_menu "Python (pip / PyPI)" "$pip_url" <<<"$pip_menu"
  hesabix_mirrors_print_menu "Flutter pub (Dart packages)" "$pub_url" <<<"$pub_menu"
  hesabix_mirrors_print_menu "Flutter storage (engine / SDK artifacts)" "$storage_url" <<<"$storage_menu"
}

hesabix_mirrors_apply_selection() {
  local pip_url pub_url storage_url
  pip_url="$(hesabix_mirrors_norm_url "$1")"
  pub_url="$(hesabix_mirrors_norm_url "$2")"
  storage_url="$(hesabix_mirrors_norm_url "$3")"
  [[ -n "$pip_url" && -n "$pub_url" && -n "$storage_url" ]] || {
    echo "Python, Flutter pub, and Flutter storage URLs are all required." >&2
    return 1
  }

  export PIP_INDEX_URL
  PIP_INDEX_URL="$(hesabix_normalize_pip_index_url "$pip_url")"
  export PIP_MIRROR
  PIP_MIRROR="$(hesabix_mirrors_pip_preset_for_url "$PIP_INDEX_URL")"
  export PUB_HOSTED_URL="$pub_url"
  export FLUTTER_STORAGE_BASE_URL="$storage_url"
  export FLUTTER_MIRROR
  FLUTTER_MIRROR="$(hesabix_mirrors_flutter_preset_for_urls "$pub_url" "$storage_url")"

  unset PIP_EXTRA_INDEX_URL
  hesabix_persist_mirror_to_deploy_env "${HESABIX_DEPLOY_ENV}"
  hesabix_configure_pip_mirror >/dev/null 2>&1 || true

  echo
  echo "Mirrors saved:"
  echo "  Python:          ${PIP_MIRROR} — ${PIP_INDEX_URL}"
  echo "  Flutter pub:     ${PUB_HOSTED_URL}"
  echo "  Flutter storage: ${FLUTTER_STORAGE_BASE_URL}"
  echo "  Flutter preset:  ${FLUTTER_MIRROR}"
}

hesabix_mirrors_log_current() {
  echo "Active mirrors:"
  echo "  Python:          ${PIP_INDEX_URL:-—}"
  echo "  Flutter pub:     ${PUB_HOSTED_URL:-—}"
  echo "  Flutter storage: ${FLUTTER_STORAGE_BASE_URL:-—}"
}

hesabix_mirrors_prompt_before_update() {
  if [[ "${HESABIX_SKIP_MIRROR_PROMPT:-0}" == "1" || "${HESABIX_NONINTERACTIVE:-0}" == "1" ]]; then
    hesabix_mirrors_load || true
    echo "Mirror prompt skipped (non-interactive)."
    hesabix_mirrors_log_current
    return 0
  fi
  if [[ ! -t 0 ]]; then
    hesabix_mirrors_load || true
    echo "stdin is not a TTY; using saved mirrors."
    hesabix_mirrors_log_current
    return 0
  fi
  echo
  echo "Before updating, choose Python and Flutter mirrors."
  echo "You can change them each time. Enter keeps the saved selection."
  hesabix_mirrors_set_interactive
}

hesabix_mirrors_set_interactive() {
  hesabix_mirrors_show || return 1
  local pip_url pub_url storage_url
  pip_url="$(hesabix_mirrors_norm_url "${PIP_INDEX_URL:-}")"
  pub_url="$(hesabix_mirrors_norm_url "${PUB_HOSTED_URL:-}")"
  storage_url="$(hesabix_mirrors_norm_url "${FLUTTER_STORAGE_BASE_URL:-}")"

  local pip_menu pub_menu storage_menu
  pip_menu="$(hesabix_mirrors_build_menu hesabix_mirrors_pip_catalog "$pip_url")"
  pub_menu="$(hesabix_mirrors_build_menu hesabix_mirrors_pub_catalog "$pub_url")"
  storage_menu="$(hesabix_mirrors_build_menu hesabix_mirrors_storage_catalog "$storage_url")"

  echo
  echo "Enter a number. Enter keeps the current selection."
  local new_pip new_pub new_storage
  new_pip="$(hesabix_mirrors_pick_from_menu "Python" "$pip_menu" "$pip_url")"
  new_pub="$(hesabix_mirrors_pick_from_menu "Flutter pub" "$pub_menu" "$pub_url")"
  new_storage="$(hesabix_mirrors_pick_from_menu "Flutter storage" "$storage_menu" "$storage_url")"
  hesabix_mirrors_apply_selection "$new_pip" "$new_pub" "$new_storage"
}

hesabix_mirrors_set_from_args() {
  hesabix_mirrors_load || return 1
  local pip_url pub_url storage_url
  pip_url="$(hesabix_mirrors_norm_url "${PIP_INDEX_URL:-}")"
  pub_url="$(hesabix_mirrors_norm_url "${PUB_HOSTED_URL:-}")"
  storage_url="$(hesabix_mirrors_norm_url "${FLUTTER_STORAGE_BASE_URL:-}")"
  local arg val resolved
  while [[ $# -gt 0 ]]; do
    arg="$1"
    case "$arg" in
      --pip)
        [[ $# -ge 2 ]] || { echo "--pip requires a value." >&2; return 1; }
        val="$2"; shift 2
        resolved="$(hesabix_mirrors_resolve_choice "$val" pip)" || {
          echo "Unknown Python mirror: ${val}" >&2; return 1
        }
        pip_url="$resolved"
        ;;
      --pub|--flutter-pub)
        [[ $# -ge 2 ]] || { echo "${arg} requires a value." >&2; return 1; }
        val="$2"; shift 2
        resolved="$(hesabix_mirrors_resolve_choice "$val" pub)" || {
          echo "Unknown Flutter pub mirror: ${val}" >&2; return 1
        }
        pub_url="$resolved"
        ;;
      --storage|--flutter-storage)
        [[ $# -ge 2 ]] || { echo "${arg} requires a value." >&2; return 1; }
        val="$2"; shift 2
        resolved="$(hesabix_mirrors_resolve_choice "$val" storage)" || {
          echo "Unknown Flutter storage mirror: ${val}" >&2; return 1
        }
        storage_url="$resolved"
        ;;
      --flutter)
        [[ $# -ge 2 ]] || { echo "--flutter requires a value." >&2; return 1; }
        val="$2"; shift 2
        resolved="$(hesabix_mirrors_resolve_choice "$val" pub)" || {
          echo "Unknown Flutter mirror: ${val}" >&2; return 1
        }
        pub_url="$resolved"
        resolved="$(hesabix_mirrors_resolve_choice "$val" storage)" || {
          echo "No Flutter storage URL defined for ${val}." >&2; return 1
        }
        storage_url="$resolved"
        ;;
      *)
        echo "Unknown option: ${arg}" >&2
        echo "Usage: hesabix -mirrors set [--pip NAME|URL] [--pub NAME|URL] [--storage NAME|URL]" >&2
        return 1
        ;;
    esac
  done
  hesabix_mirrors_apply_selection "$pip_url" "$pub_url" "$storage_url"
}

hesabix_mirrors_command() {
  local action="${1:-}"
  shift || true
  case "$action" in
    ""|set)
      if [[ $# -gt 0 ]]; then
        hesabix_mirrors_set_from_args "$@"
      elif [[ -t 0 ]]; then
        hesabix_mirrors_set_interactive
      else
        hesabix_mirrors_show
      fi
      ;;
    show|status)
      hesabix_mirrors_show
      ;;
    *)
      echo "Invalid -mirrors action: ${action}. Use: show|set" >&2
      return 1
      ;;
  esac
}
