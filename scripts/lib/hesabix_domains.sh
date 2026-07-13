#!/usr/bin/env bash
# Domain management: show, set, frontend rebuild for Hesabix.

HESABIX_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=hesabix_deploy_env.sh
source "${HESABIX_LIB_DIR}/hesabix_deploy_env.sh"
# shellcheck source=hesabix_letsencrypt.sh
source "${HESABIX_LIB_DIR}/hesabix_letsencrypt.sh"
# shellcheck source=hesabix_nginx_domains.sh
source "${HESABIX_LIB_DIR}/hesabix_nginx_domains.sh"
# shellcheck source=hesabix_ssl.sh
source "${HESABIX_LIB_DIR}/hesabix_ssl.sh"

hesabix_update_share_link_base_url() {
  local ui_scheme
  ui_scheme="$(hesabix_resolve_ui_public_scheme)"
  local share_url="${ui_scheme}://${UI_DOMAIN}/p"
  local env_file="${APP_ROOT}/app/hesabixAPI/.env"
  [[ -f "${env_file}" ]] || return 0
  hesabix_patch_env_file "${env_file}" "SHARE_LINK_PUBLIC_BASE_URL=${share_url}"
  echo ">> Updated SHARE_LINK_PUBLIC_BASE_URL=${share_url}"
}

hesabix_rebuild_frontend() {
  hesabix_load_deploy_env || return 1

  local app_dir="${APP_ROOT}/app"
  local build_script="${app_dir}/build_web.sh"
  if [[ ! -f "${build_script}" ]]; then
    echo "build_web.sh not found: ${build_script}" >&2
    return 1
  fi
  chmod +x "${build_script}"

  # shellcheck source=/dev/null
  if [[ -r "${app_dir}/scripts/api_public_scheme.sh" ]]; then
    source "${app_dir}/scripts/api_public_scheme.sh"
  fi
  if ! declare -F hesabix_resolve_api_public_scheme >/dev/null 2>&1; then
    hesabix_resolve_api_public_scheme() {
      if hesabix_pick_letsencrypt_live_for_domain "${API_DOMAIN:-}" >/dev/null 2>&1; then
        printf '%s' "https"; return 0
      fi
      local s="${API_PUBLIC_SCHEME:-}"
      s="${s,,}"
      case "$s" in http|https) printf '%s' "$s"; return 0 ;; esac
      printf '%s' "http"
    }
  fi

  local api_scheme api_url
  api_scheme="$(hesabix_resolve_api_public_scheme)"
  api_url="${api_scheme}://${API_DOMAIN}"

  echo ">> Rebuilding Flutter web (API_BASE_URL=${api_url})..."
  cd "${app_dir}"
  if ! env PATH="/opt/flutter/bin:/snap/bin:$PATH" \
      PUB_HOSTED_URL="${PUB_HOSTED_URL:-}" \
      FLUTTER_STORAGE_BASE_URL="${FLUTTER_STORAGE_BASE_URL:-}" \
      SKIP_NGINX_ENSURE=1 \
      bash "${build_script}" --mode release --api-base-url "${api_url}" --clean --install-deps; then
    echo "Frontend build failed." >&2
    return 1
  fi

  local build_output="${app_dir}/hesabixUI/hesabix_ui/build/web"
  if [[ ! -f "${build_output}/index.html" ]]; then
    echo "Build output missing index.html." >&2
    return 1
  fi
  mkdir -p "/var/www/${UI_DOMAIN}"
  rsync -a --delete "${build_output}/" "/var/www/${UI_DOMAIN}/"
  chown -R www-data:www-data "/var/www/${UI_DOMAIN}"
  echo "✓ Frontend deployed to /var/www/${UI_DOMAIN}"
}

hesabix_domains_show() {
  hesabix_load_deploy_env || return 1

  local api_s ui_s pg_s=""
  # shellcheck source=/dev/null
  [[ -r "${APP_ROOT}/app/scripts/api_public_scheme.sh" ]] && source "${APP_ROOT}/app/scripts/api_public_scheme.sh"
  api_s="$(hesabix_resolve_api_public_scheme 2>/dev/null || echo http)"
  ui_s="$(hesabix_resolve_ui_public_scheme)"

  echo "Configured domains"
  echo "=================="
  echo "  API_DOMAIN:      ${API_DOMAIN}"
  echo "  UI_DOMAIN:       ${UI_DOMAIN}"
  if [[ -n "${PGADMIN4_DOMAIN:-}" ]]; then
    if hesabix_domain_has_ssl "${PGADMIN4_DOMAIN}"; then pg_s="https"; else pg_s="http"; fi
    echo "  PGADMIN4_DOMAIN:  ${PGADMIN4_DOMAIN}"
  fi
  echo
  echo "  API URL:  ${api_s}://${API_DOMAIN}/"
  echo "  UI URL:   ${ui_s}://${UI_DOMAIN}/"
  if [[ -n "${PGADMIN4_DOMAIN:-}" ]]; then
    echo "  pgAdmin:  ${pg_s}://${PGADMIN4_DOMAIN}/"
  fi
  echo
  echo "  Frontend root: /var/www/${UI_DOMAIN}"
  echo "  Config:        ${HESABIX_DEPLOY_ENV}"
}

hesabix_domains_set() {
  local new_api="" new_ui="" new_pgadmin="" do_ssl=0 do_rebuild=1
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --api)
        [[ $# -ge 2 ]] || { echo "--api requires a domain." >&2; return 1; }
        new_api="$2"
        shift 2
        ;;
      --ui)
        [[ $# -ge 2 ]] || { echo "--ui requires a domain." >&2; return 1; }
        new_ui="$2"
        shift 2
        ;;
      --pgadmin)
        [[ $# -ge 2 ]] || { echo "--pgadmin requires a domain." >&2; return 1; }
        new_pgadmin="$2"
        shift 2
        ;;
      --ssl) do_ssl=1; shift ;;
      --rebuild) do_rebuild=1; shift ;;
      --no-rebuild) do_rebuild=0; shift ;;
      *)
        echo "Unknown option: $1" >&2
        return 1
        ;;
    esac
  done

  if [[ -z "${new_api}" && -z "${new_ui}" && -z "${new_pgadmin}" ]]; then
    echo "Provide at least one of: --api, --ui, --pgadmin" >&2
    return 1
  fi

  hesabix_load_deploy_env || return 1

  local old_api="${API_DOMAIN}" old_ui="${UI_DOMAIN}" old_pg="${PGADMIN4_DOMAIN:-}"
  local -a patch_deploy=() patch_saved=()

  if [[ -n "${new_api}" ]]; then
    hesabix_validate_domain "${new_api}" || return 1
    patch_deploy+=("API_DOMAIN=${new_api}")
    patch_saved+=("API_DOMAIN=${new_api}")
    API_DOMAIN="${new_api}"
  fi
  if [[ -n "${new_ui}" ]]; then
    hesabix_validate_domain "${new_ui}" || return 1
    patch_deploy+=("UI_DOMAIN=${new_ui}")
    patch_saved+=("UI_DOMAIN=${new_ui}")
    UI_DOMAIN="${new_ui}"
  fi
  if [[ -n "${new_pgadmin}" ]]; then
    hesabix_validate_domain "${new_pgadmin}" || return 1
    patch_saved+=("PGADMIN4_DOMAIN=${new_pgadmin}")
    PGADMIN4_DOMAIN="${new_pgadmin}"
  fi

  echo ">> Updating deployment config..."
  if [[ ${#patch_deploy[@]} -gt 0 ]]; then
    hesabix_patch_env_file "${HESABIX_DEPLOY_ENV}" "${patch_deploy[@]}"
  fi
  if [[ ${#patch_saved[@]} -gt 0 ]]; then
    hesabix_patch_env_file "${HESABIX_DEPLOY_SAVED_VARS}" "${patch_saved[@]}"
  fi

  echo ">> Applying Nginx configuration..."
  hesabix_apply_nginx_domain_configs || return 1

  if [[ "${do_ssl}" -eq 1 ]]; then
    echo ">> Enabling SSL for updated domain(s)..."
    local ssl_targets=()
    if [[ -n "${new_api}" ]]; then ssl_targets+=(--api); fi
    if [[ -n "${new_ui}" ]]; then ssl_targets+=(--ui); fi
    if [[ -n "${new_pgadmin}" ]]; then ssl_targets+=(--pgadmin); fi
    hesabix_ssl_enable_targets "${ssl_targets[@]}" --no-sync-nginx || true
    hesabix_apply_nginx_domain_configs || return 1
  fi

  if [[ "${do_rebuild}" -eq 1 ]] && [[ -n "${new_api}" || -n "${new_ui}" ]]; then
    hesabix_rebuild_frontend || return 1
  fi

  if [[ -n "${new_ui}" ]]; then
    hesabix_update_share_link_base_url || true
  fi

  echo
  echo "✓ Domains updated."
  if [[ "${old_api}" != "${API_DOMAIN}" ]]; then
    echo "  API: ${old_api} → ${API_DOMAIN}"
  fi
  if [[ "${old_ui}" != "${UI_DOMAIN}" ]]; then
    echo "  UI:  ${old_ui} → ${UI_DOMAIN}"
    echo "  (old web root /var/www/${old_ui} was left on disk; remove manually if unused)"
  fi
  if [[ -n "${new_pgadmin}" && "${old_pg}" != "${PGADMIN4_DOMAIN}" ]]; then
    echo "  pgAdmin4: ${old_pg:-<unset>} → ${PGADMIN4_DOMAIN}"
  fi
  hesabix_domains_show
}
