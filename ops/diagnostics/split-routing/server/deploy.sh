#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail
umask 027

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

action=''
render_dir=''

usage() {
    cat <<'USAGE'
Usage:
  deploy.sh --render OUTPUT_DIR   Render reviewed files locally; no root needed.
  deploy.sh --apply               Install new files and run nginx -t; no reload.
  deploy.sh --activate            Verify hashes, run nginx -t, reload nginx.

Exactly one action is required. Production actions require the separately
approved controlled root session.
USAGE
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --render)
            [[ $# -ge 2 ]] || fail "--render requires OUTPUT_DIR"
            action='render'
            render_dir="$2"
            shift
            ;;
        --apply) action='apply' ;;
        --activate) action='activate' ;;
        --help|-h) usage; exit 0 ;;
        *) fail "unknown argument: $1" ;;
    esac
    shift
done

[[ -n "$action" ]] || { usage; exit 1; }
load_and_validate_inputs

if [[ "$action" == 'render' ]]; then
    [[ -d "$render_dir" ]] || fail "OUTPUT_DIR must already exist"
    render_templates "$render_dir"
    info "rendered files into $render_dir"
    exit 0
fi

require_root
require_command nginx
require_command systemctl

if [[ "$action" == 'activate' ]]; then
    verify_deployed_hashes
    [[ "$MANIFEST_RU_HOST" == "$RU_HOST" ]] || fail "RU_HOST differs from installed manifest"
    [[ "$MANIFEST_NON_RU_HOST" == "$NON_RU_HOST" ]] || fail "NON_RU_HOST differs from installed manifest"
    [[ "$MANIFEST_NODE_PUBLIC_IP" == "$NODE_PUBLIC_IP" ]] || fail "NODE_PUBLIC_IP differs from installed manifest"
    [[ "$MANIFEST_ENDPOINT_TOKEN" == "$ENDPOINT_TOKEN" ]] || fail "ENDPOINT_TOKEN differs from installed manifest"
    check_public_certificate "$NON_RU_CERT_LINEAGE" "$NON_RU_HOST" 'no'
    check_public_certificate "$RU_CERT_LINEAGE" "$RU_HOST" 'no'
    nginx -t
    systemctl reload nginx
    info "diagnostic Nginx configuration activated"
    exit 0
fi

"${SCRIPT_DIR}/preflight.sh"

for path in "$SITE_AVAILABLE" "$SITE_ENABLED" "$ENDPOINT_SNIPPET" "$STATE_FILE"; do
    [[ ! -e "$path" && ! -L "$path" ]] || fail "refusing to overwrite existing path: $path"
done

check_public_certificate "$NON_RU_CERT_LINEAGE" "$NON_RU_HOST" 'no'
check_public_certificate "$RU_CERT_LINEAGE" "$RU_HOST" 'no'

tmp_dir="$(mktemp -d)"
apply_complete='no'
created_site='no'
created_snippet='no'
created_symlink='no'
created_state='no'
created_state_dir='no'
cleanup_tmp() {
    status=$?
    if [[ "$apply_complete" == 'no' ]]; then
        [[ "$created_symlink" == 'yes' ]] && unlink "$SITE_ENABLED" 2>/dev/null || true
        [[ "$created_site" == 'yes' ]] && rm -f -- "$SITE_AVAILABLE"
        [[ "$created_snippet" == 'yes' ]] && rm -f -- "$ENDPOINT_SNIPPET"
        [[ "$created_state" == 'yes' ]] && rm -f -- "$STATE_FILE"
        [[ "$created_state_dir" == 'yes' ]] && rmdir "$STATE_DIR" 2>/dev/null || true
    fi
    rm -rf -- "$tmp_dir"
    return "$status"
}
trap cleanup_tmp EXIT

render_templates "$tmp_dir"
site_hash="$(sha256_file "${tmp_dir}/site.conf")"
snippet_hash="$(sha256_file "${tmp_dir}/endpoint.conf")"

install -m 0644 "${tmp_dir}/site.conf" "$SITE_AVAILABLE"
created_site='yes'
install -m 0644 "${tmp_dir}/endpoint.conf" "$ENDPOINT_SNIPPET"
created_snippet='yes'
ln -s "$SITE_AVAILABLE" "$SITE_ENABLED"
created_symlink='yes'
install -d -m 0750 "$STATE_DIR"
created_state_dir='yes'

cat >"${tmp_dir}/state" <<STATE
RU_HOST=${RU_HOST}
NON_RU_HOST=${NON_RU_HOST}
NODE_PUBLIC_IP=${NODE_PUBLIC_IP}
ENDPOINT_TOKEN=${ENDPOINT_TOKEN}
SITE_SHA256=${site_hash}
SNIPPET_SHA256=${snippet_hash}
DEPLOYED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)
STATE
install -m 0600 "${tmp_dir}/state" "$STATE_FILE"
created_state='yes'

if ! nginx -t; then
    info "nginx -t failed; removing only files created by this invocation"
    fail "installation rolled back because nginx -t failed"
fi

apply_complete='yes'
info "files installed and nginx -t passed; nginx was NOT reloaded"
info "review the installed files, then use deploy.sh --activate after separate approval"
