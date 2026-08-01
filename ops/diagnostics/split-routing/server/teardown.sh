#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

action=''
keep_log='no'
dns_confirmed='no'

usage() {
    cat <<'USAGE'
Usage:
  teardown.sh --check
  teardown.sh --apply --dns-confirmed [--keep-log]
  teardown.sh --purge-log-only

--apply verifies manifest hashes, disables only the diagnostic site, runs
nginx -t, reloads nginx, then removes its own files. The certificate lineage
and DNS are never changed. The diagnostic log is removed unless --keep-log is
set. Complete DNS teardown and retention review first.
USAGE
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --check|--apply|--purge-log-only)
            [[ -z "$action" ]] || fail "choose exactly one action"
            action="${1#--}"
            ;;
        --keep-log) keep_log='yes' ;;
        --dns-confirmed) dns_confirmed='yes' ;;
        --help|-h) usage; exit 0 ;;
        *) fail "unknown argument: $1" ;;
    esac
    shift
done

[[ -n "$action" ]] || { usage; exit 1; }
require_root

purge_log() {
    if [[ -L "$LOG_FILE" ]]; then
        fail "refusing to delete symlinked log path: $LOG_FILE"
    fi
    if [[ -e "$LOG_FILE" ]]; then
        [[ -f "$LOG_FILE" ]] || fail "diagnostic log path is not a regular file"
        rm -f -- "$LOG_FILE"
        info "diagnostic log removed"
    else
        info "diagnostic log already absent"
    fi
}

if [[ "$action" == 'purge-log-only' ]]; then
    purge_log
    exit 0
fi

verify_deployed_hashes
info "manifest and deployed hashes match"

if [[ "$action" == 'check' ]]; then
    exit 0
fi

[[ "$dns_confirmed" == 'yes' ]] || \
    fail "--dns-confirmed is required after completing and verifying manual DNS teardown"

require_command nginx
require_command systemctl

unlink "$SITE_ENABLED"
if ! nginx -t; then
    ln -s "$SITE_AVAILABLE" "$SITE_ENABLED"
    fail "nginx -t failed without diagnostic site; symlink restored, no reload performed"
fi

if ! systemctl reload nginx; then
    ln -s "$SITE_AVAILABLE" "$SITE_ENABLED"
    fail "nginx reload failed; diagnostic symlink restored for manual review"
fi

rm -f -- "$SITE_AVAILABLE" "$ENDPOINT_SNIPPET" "$STATE_FILE"
rmdir "$STATE_DIR" 2>/dev/null || true

if [[ "$keep_log" == 'no' ]]; then
    purge_log
else
    info "diagnostic log retained at $LOG_FILE"
fi

info "server-side diagnostic configuration removed; DNS and certificate were not changed"
