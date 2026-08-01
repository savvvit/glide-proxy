#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

allow_missing_ru_cert='no'
expect_dns='no'

usage() {
    cat <<'USAGE'
Usage: preflight.sh [--allow-missing-ru-cert] [--expect-dns]

Read-only checks for the one-time GCM split-routing diagnostic.
No files, services, DNS records or certificates are changed.
USAGE
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --allow-missing-ru-cert) allow_missing_ru_cert='yes' ;;
        --expect-dns) expect_dns='yes' ;;
        --help|-h) usage; exit 0 ;;
        *) fail "unknown argument: $1" ;;
    esac
    shift
done

load_and_validate_inputs
require_root
require_command nginx
require_command openssl
require_command stat
require_command awk

[[ -d /etc/nginx/sites-available ]] || fail "sites-available directory is missing"
[[ -d /etc/nginx/sites-enabled ]] || fail "sites-enabled directory is missing"
[[ -d /etc/nginx/snippets ]] || fail "snippets directory is missing"

for path in "$SITE_AVAILABLE" "$SITE_ENABLED" "$ENDPOINT_SNIPPET" "$STATE_FILE"; do
    [[ ! -e "$path" && ! -L "$path" ]] || fail "target already exists: $path"
done

nginx -t

# nginx -T output can contain sensitive directives. Emit only exact matching
# server_name lines and discard every other line without storing raw output.
conflicts="$({ nginx -T 2>&1 || exit $?; } | awk -v ru="$RU_HOST" -v nonru="$NON_RU_HOST" '
    $1 == "server_name" {
        for (i = 2; i <= NF; i++) {
            value = $i
            sub(/;$/, "", value)
            if (value == ru || value == nonru) print $0
        }
    }
')" || fail "unable to inspect sanitized effective nginx configuration"

[[ -z "$conflicts" ]] || {
    printf 'Conflicting server_name entries:\n%s\n' "$conflicts" >&2
    fail "exact diagnostic hostname already exists"
}

check_public_certificate "$NON_RU_CERT_LINEAGE" "$NON_RU_HOST" 'no'
check_public_certificate "$RU_CERT_LINEAGE" "$RU_HOST" "$allow_missing_ru_cert"

if [[ "$expect_dns" == 'yes' ]]; then
    require_command dig
    ru_dns="$(dig +short A "$RU_HOST" | awk '/^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/ {print}' | sort -u)"
    non_ru_dns="$(dig +short A "$NON_RU_HOST" | awk '/^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/ {print}' | sort -u)"
    [[ "$ru_dns" == "$NODE_PUBLIC_IP" ]] || fail "unexpected A record for $RU_HOST: ${ru_dns:-none}"
    [[ "$non_ru_dns" == "$NODE_PUBLIC_IP" ]] || fail "unexpected A record for $NON_RU_HOST: ${non_ru_dns:-none}"
    [[ -z "$(dig +short AAAA "$RU_HOST")" ]] || fail "unexpected AAAA for $RU_HOST"
    [[ -z "$(dig +short AAAA "$NON_RU_HOST")" ]] || fail "unexpected AAAA for $NON_RU_HOST"
fi

info "read-only preflight passed"
info "node target: ${NODE_PUBLIC_IP}"
info "endpoint: /routing-test-${ENDPOINT_TOKEN}"
