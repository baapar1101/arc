#!/usr/bin/env bash
# Ensure Flutter Dart SDK is usable before web build (update.sh / deploy).
# - Optional git update to origin/stable only when HESABIX_UPDATE_FLUTTER_SDK=1
# - Download Dart SDK with storage mirror fallbacks when primary mirror lacks artifacts
# - Roll back Flutter git + restore dart-sdk.old if update breaks the toolchain
set -euo pipefail

FLUTTER_ROOT="${FLUTTER_ROOT:-/opt/flutter}"

log() { echo "ensure_flutter_sdk: $*" >&2; }

_flutter_storage_fallback_bases() {
  local -a bases=()
  local b
  if [[ -n "${FLUTTER_STORAGE_BASE_URL:-}" ]]; then
    bases+=("${FLUTTER_STORAGE_BASE_URL%/}")
  fi
  bases+=(
    "https://f.mirror.hesabix.ir/gcs"
    "https://storage.flutter-io.cn"
    "https://mirrors.tuna.tsinghua.edu.cn/flutter"
    "https://storage.googleapis.com"
  )
  local -A seen=()
  for b in "${bases[@]}"; do
    [[ -n "$b" && -z "${seen[$b]:-}" ]] || continue
    seen[$b]=1
    printf '%s\n' "$b"
  done
}

_dart_sdk_ready() {
  local dart_bin="${FLUTTER_ROOT}/bin/cache/dart-sdk/bin/dart"
  [[ -x "$dart_bin" ]] && "$dart_bin" --version >/dev/null 2>&1
}

_ensure_dart_sdk_with_mirror() {
  local base update_script
  update_script="${FLUTTER_ROOT}/bin/internal/update_dart_sdk.sh"
  [[ -x "$update_script" || -f "$update_script" ]] || {
    log "missing ${update_script}"
    return 1
  }
  while IFS= read -r base; do
    [[ -n "$base" ]] || continue
    log "Ensuring Dart SDK via FLUTTER_STORAGE_BASE_URL=${base}"
    if env FLUTTER_STORAGE_BASE_URL="$base" bash "$update_script" >/dev/null 2>&1; then
      if _dart_sdk_ready; then
        log "Dart SDK ready (${base})"
        return 0
      fi
    fi
    rm -f "${FLUTTER_ROOT}/bin/cache/dart-sdk-linux-x64.zip" 2>/dev/null || true
    rm -f "${FLUTTER_ROOT}/bin/cache/dart-sdk-linux-arm64.zip" 2>/dev/null || true
  done < <(_flutter_storage_fallback_bases)
  return 1
}

_restore_dart_sdk_backup() {
  local dart_sdk="${FLUTTER_ROOT}/bin/cache/dart-sdk"
  local dart_old="${FLUTTER_ROOT}/bin/cache/dart-sdk.old"
  if [[ -d "${dart_old}/bin" ]]; then
    log "Restoring Dart SDK from dart-sdk.old"
    rm -rf "$dart_sdk"
    mv "$dart_old" "$dart_sdk"
    _dart_sdk_ready
    return $?
  fi
  return 1
}

maybe_update_flutter_git() {
  local flag="${HESABIX_UPDATE_FLUTTER_SDK:-0}"
  if [[ ! "$flag" =~ ^(1|[Yy]|[Yy][Ee][Ss]|true)$ ]]; then
    log "Skipping Flutter SDK git update (set HESABIX_UPDATE_FLUTTER_SDK=1 to upgrade stable)"
    return 0
  fi
  [[ -d "${FLUTTER_ROOT}/.git" ]] || {
    log "No git checkout at ${FLUTTER_ROOT}; skip git update"
    return 0
  }

  local prev_commit
  prev_commit="$(git -C "$FLUTTER_ROOT" rev-parse HEAD 2>/dev/null || true)"
  log "Updating Flutter SDK git to origin/stable (was ${prev_commit:-unknown})"
  if ! (cd "$FLUTTER_ROOT" && git fetch --depth 1 origin stable && git reset --hard origin/stable); then
    log "Flutter git update failed"
    return 1
  fi

  if _ensure_dart_sdk_with_mirror; then
    return 0
  fi

  log "Dart SDK unavailable after Flutter git update; rolling back"
  if [[ -n "$prev_commit" ]]; then
    git -C "$FLUTTER_ROOT" reset --hard "$prev_commit" || true
  fi
  _restore_dart_sdk_backup || true
  if _dart_sdk_ready; then
    log "Rolled back Flutter SDK; Dart toolchain restored"
    return 1
  fi
  return 1
}

ensure_flutter_dart_sdk() {
  [[ -d "$FLUTTER_ROOT" ]] || {
    log "Flutter not found at ${FLUTTER_ROOT}"
    return 1
  }
  git config --global --add safe.directory "$FLUTTER_ROOT" 2>/dev/null || true

  if _dart_sdk_ready; then
    log "Dart SDK already OK"
    return 0
  fi

  if _ensure_dart_sdk_with_mirror; then
    return 0
  fi

  if _restore_dart_sdk_backup; then
    log "Using backed-up Dart SDK"
    return 0
  fi

  log "Could not provision Dart SDK from any mirror"
  return 1
}

main() {
  maybe_update_flutter_git || true
  ensure_flutter_dart_sdk
}

main "$@"
