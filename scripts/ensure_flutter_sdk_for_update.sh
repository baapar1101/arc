#!/usr/bin/env bash
# Ensure Flutter Dart SDK + web engine artifacts before web build (update.sh / deploy).
# - Optional git update to origin/stable only when HESABIX_UPDATE_FLUTTER_SDK=1
# - Resolve FLUTTER_STORAGE_BASE_URL to a mirror that has engine artifacts (sky_engine.zip)
# - Download Dart SDK / precache web with storage mirror fallbacks
set -euo pipefail

APP_ROOT="${APP_ROOT:-/opt/hesabix}"
FLUTTER_ROOT="${FLUTTER_ROOT:-/opt/flutter}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=scripts/mirror_config.sh
if [[ -r "${SCRIPT_DIR}/mirror_config.sh" ]]; then
  # shellcheck disable=SC1091
  source "${SCRIPT_DIR}/mirror_config.sh"
fi

log() { echo "ensure_flutter_sdk: $*" >&2; }

_dart_sdk_ready() {
  local dart_bin="${FLUTTER_ROOT}/bin/cache/dart-sdk/bin/dart"
  [[ -x "$dart_bin" ]] && "$dart_bin" --version >/dev/null 2>&1
}

_ensure_dart_sdk_with_mirror() {
  local base update_script
  update_script="${FLUTTER_ROOT}/bin/internal/update_dart_sdk.sh"
  [[ -f "$update_script" ]] || {
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
  done < <(hesabix_flutter_storage_fallback_bases)
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

_web_artifacts_ready() {
  [[ -d "${FLUTTER_ROOT}/bin/cache/flutter_web_sdk/lib" ]] \
    && [[ -d "${FLUTTER_ROOT}/bin/cache/pkg/sky_engine/lib" ]]
}

ensure_flutter_web_artifacts() {
  local flutter_bin="${FLUTTER_ROOT}/bin/flutter"
  [[ -x "$flutter_bin" ]] || flutter_bin="$(command -v flutter 2>/dev/null || true)"
  [[ -n "$flutter_bin" ]] || {
    log "flutter binary not found"
    return 1
  }

  if _web_artifacts_ready; then
    log "Flutter web artifacts already cached; skipping precache"
    return 0
  fi

  local storage_resolved=0
  if declare -F hesabix_resolve_flutter_storage_base_url >/dev/null 2>&1; then
    if hesabix_resolve_flutter_storage_base_url; then
      storage_resolved=1
    fi
  fi
  if [[ "$storage_resolved" -eq 0 ]]; then
    export FLUTTER_STORAGE_BASE_URL="${FLUTTER_STORAGE_BASE_URL:-https://storage.flutter-io.cn}"
    log "Storage mirror probe failed; using fallback FLUTTER_STORAGE_BASE_URL=${FLUTTER_STORAGE_BASE_URL}"
  fi

  export PUB_HOSTED_URL="${PUB_HOSTED_URL:-https://f.mirror.hesabix.ir/pub}"
  export PATH="${FLUTTER_ROOT}/bin:/snap/bin:${PATH:-}"
  log "Precaching Flutter web artifacts (FLUTTER_STORAGE_BASE_URL=${FLUTTER_STORAGE_BASE_URL})"
  if env PUB_HOSTED_URL="${PUB_HOSTED_URL}" FLUTTER_STORAGE_BASE_URL="${FLUTTER_STORAGE_BASE_URL}" \
    "$flutter_bin" precache --web --no-android --no-ios --no-linux --no-macos --no-windows --no-fuchsia; then
    log "Flutter web artifacts precached"
    return 0
  fi

  if _web_artifacts_ready; then
    log "precache reported failure but web artifacts are present; continuing"
    return 0
  fi

  log "flutter precache --web failed"
  return 1
}

main() {
  if declare -F hesabix_apply_flutter_mirror_env >/dev/null 2>&1; then
    hesabix_apply_flutter_mirror_env
  else
    export PUB_HOSTED_URL="${PUB_HOSTED_URL:-https://f.mirror.hesabix.ir/pub}"
    export FLUTTER_STORAGE_BASE_URL="${FLUTTER_STORAGE_BASE_URL:-https://f.mirror.hesabix.ir/gcs}"
  fi

  maybe_update_flutter_git || true
  ensure_flutter_dart_sdk
  ensure_flutter_web_artifacts
}

main "$@"
