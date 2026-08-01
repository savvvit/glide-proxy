#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

readonly DIAGNOSTIC_ID="gcm-routing-ab-test"
readonly SITE_AVAILABLE="/etc/nginx/sites-available/${DIAGNOSTIC_ID}.conf"
readonly SITE_ENABLED="/etc/nginx/sites-enabled/${DIAGNOSTIC_ID}.conf"
readonly ENDPOINT_SNIPPET="/etc/nginx/snippets/${DIAGNOSTIC_ID}-endpoint.conf"
readonly STATE_DIR="/var/lib/${DIAGNOSTIC_ID}"
readonly STATE_FILE="${STATE_DIR}/state"
readonly LOG_FILE="/var/log/nginx/${DIAGNOSTIC_ID}.log"

COMMON_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly COMMON_DIR
readonly PACKAGE_DIR="$(CDPATH= cd -- "${COMMON_DIR}/.." && pwd)"
readonly SITE_TEMPLATE="${PACKAGE_DIR}/nginx/site.conf.template"
readonly ENDPOINT_TEMPLATE="${PACKAGE_DIR}/nginx/endpoint.conf.template"

fail() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

info() {
    printf 'INFO: %s\n' "$*"
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || fail "required command not found: $1"
}

validate_hostname() {
    local value="$1"
    [[ "$value" =~ ^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$ ]] || \
        fail "invalid lowercase hostname: $value"
}

validate_ipv4() {
    local value="$1"
    local octet
    local -a octets

    IFS='.' read -r -a octets <<<"$value"
    [[ "${#octets[@]}" -eq 4 ]] || fail "invalid IPv4: $value"
    for octet in "${octets[@]}"; do
        [[ "$octet" =~ ^[0-9]{1,3}$ ]] || fail "invalid IPv4: $value"
        ((10#$octet <= 255)) || fail "invalid IPv4: $value"
    done
}

load_and_validate_inputs() {
    RU_HOST="${RU_HOST:-diag.systemcoach.ru}"
    NON_RU_HOST="${NON_RU_HOST:-diag.glide.club}"
    NODE_PUBLIC_IP="${NODE_PUBLIC_IP:-77.233.221.222}"
    RU_CERT_LINEAGE="${RU_CERT_LINEAGE:-diag.systemcoach.ru}"
    NON_RU_CERT_LINEAGE="${NON_RU_CERT_LINEAGE:-glide.club}"
    ENDPOINT_TOKEN="${ENDPOINT_TOKEN:-}"

    validate_hostname "$RU_HOST"
    validate_hostname "$NON_RU_HOST"
    validate_hostname "$RU_CERT_LINEAGE"
    validate_hostname "$NON_RU_CERT_LINEAGE"
    validate_ipv4 "$NODE_PUBLIC_IP"
    [[ "$RU_HOST" == *.ru ]] || fail "RU_HOST must end in .ru"
    [[ "$NON_RU_HOST" != *.ru ]] || fail "NON_RU_HOST must not end in .ru"
    [[ "$RU_HOST" != "$NON_RU_HOST" ]] || fail "hostnames must differ"
    [[ "$ENDPOINT_TOKEN" =~ ^[A-Za-z0-9_-]{12,64}$ ]] || \
        fail "ENDPOINT_TOKEN must contain 12-64 letters, digits, '_' or '-'"

    export RU_HOST NON_RU_HOST NODE_PUBLIC_IP RU_CERT_LINEAGE NON_RU_CERT_LINEAGE ENDPOINT_TOKEN
}

render_templates() {
    local output_dir="$1"

    [[ -d "$output_dir" ]] || fail "render output directory does not exist: $output_dir"
    require_command sed

    sed \
        -e "s|@@RU_HOST@@|${RU_HOST}|g" \
        -e "s|@@NON_RU_HOST@@|${NON_RU_HOST}|g" \
        -e "s|@@RU_CERT_LINEAGE@@|${RU_CERT_LINEAGE}|g" \
        -e "s|@@NON_RU_CERT_LINEAGE@@|${NON_RU_CERT_LINEAGE}|g" \
        -e "s|@@ENDPOINT_TOKEN@@|${ENDPOINT_TOKEN}|g" \
        "$SITE_TEMPLATE" >"${output_dir}/site.conf"

    sed \
        -e "s|@@ENDPOINT_TOKEN@@|${ENDPOINT_TOKEN}|g" \
        "$ENDPOINT_TEMPLATE" >"${output_dir}/endpoint.conf"

    if grep -R '@@' "${output_dir}/site.conf" "${output_dir}/endpoint.conf" >/dev/null 2>&1; then
        fail "unresolved template placeholder"
    fi
}

sha256_file() {
    local path="$1"
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$path" | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$path" | awk '{print $1}'
    else
        fail "sha256sum or shasum is required"
    fi
}

require_root() {
    [[ "${EUID}" -eq 0 ]] || fail "run this action as root through the approved controlled session"
}

check_public_certificate() {
    local lineage="$1"
    local hostname="$2"
    local allow_missing="$3"
    local cert_path="/etc/letsencrypt/live/${lineage}/cert.pem"
    local fullchain_path="/etc/letsencrypt/live/${lineage}/fullchain.pem"
    local key_path="/etc/letsencrypt/live/${lineage}/privkey.pem"

    if [[ ! -f "$cert_path" || ! -f "$fullchain_path" || ! -e "$key_path" ]]; then
        [[ "$allow_missing" == "yes" ]] && {
            info "certificate may be absent in this phase: ${lineage}"
            return 0
        }
        fail "certificate files are missing for lineage: ${lineage}"
    fi

    openssl x509 -in "$cert_path" -noout -checkhost "$hostname" >/dev/null 2>&1 || \
        fail "certificate ${lineage} does not cover ${hostname}"
    openssl x509 -in "$cert_path" -noout -checkend 86400 >/dev/null 2>&1 || \
        fail "certificate ${lineage} expires in less than 24 hours"

    # Metadata only. Never read or print private-key contents.
    stat -c '%a %U:%G' "$key_path" >/dev/null
    info "certificate metadata is acceptable: ${lineage} -> ${hostname}"
}

read_manifest() {
    [[ -f "$STATE_FILE" ]] || fail "state manifest not found: $STATE_FILE"

    MANIFEST_RU_HOST=''
    MANIFEST_NON_RU_HOST=''
    MANIFEST_NODE_PUBLIC_IP=''
    MANIFEST_ENDPOINT_TOKEN=''
    MANIFEST_SITE_SHA256=''
    MANIFEST_SNIPPET_SHA256=''

    while IFS='=' read -r key value; do
        case "$key" in
            RU_HOST) MANIFEST_RU_HOST="$value" ;;
            NON_RU_HOST) MANIFEST_NON_RU_HOST="$value" ;;
            NODE_PUBLIC_IP) MANIFEST_NODE_PUBLIC_IP="$value" ;;
            ENDPOINT_TOKEN) MANIFEST_ENDPOINT_TOKEN="$value" ;;
            SITE_SHA256) MANIFEST_SITE_SHA256="$value" ;;
            SNIPPET_SHA256) MANIFEST_SNIPPET_SHA256="$value" ;;
            DEPLOYED_AT) : ;;
            '') : ;;
            *) fail "unexpected key in state manifest: $key" ;;
        esac
    done <"$STATE_FILE"

    [[ -n "$MANIFEST_RU_HOST" && -n "$MANIFEST_NON_RU_HOST" && \
       -n "$MANIFEST_NODE_PUBLIC_IP" && -n "$MANIFEST_ENDPOINT_TOKEN" && \
       "$MANIFEST_SITE_SHA256" =~ ^[a-f0-9]{64}$ && \
       "$MANIFEST_SNIPPET_SHA256" =~ ^[a-f0-9]{64}$ ]] || \
        fail "state manifest is incomplete or invalid"
}

verify_deployed_hashes() {
    read_manifest
    [[ -f "$SITE_AVAILABLE" ]] || fail "deployed site file is missing"
    [[ -f "$ENDPOINT_SNIPPET" ]] || fail "deployed endpoint snippet is missing"
    [[ -L "$SITE_ENABLED" ]] || fail "enabled-site symlink is missing"
    [[ "$(readlink "$SITE_ENABLED")" == "$SITE_AVAILABLE" ]] || \
        fail "enabled-site symlink has an unexpected target"
    [[ "$(sha256_file "$SITE_AVAILABLE")" == "$MANIFEST_SITE_SHA256" ]] || \
        fail "deployed site differs from reviewed state"
    [[ "$(sha256_file "$ENDPOINT_SNIPPET")" == "$MANIFEST_SNIPPET_SHA256" ]] || \
        fail "deployed snippet differs from reviewed state"
}
