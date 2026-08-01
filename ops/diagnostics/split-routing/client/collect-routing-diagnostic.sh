#!/bin/sh

set -u
umask 077
LC_ALL=C
export LC_ALL

ru_host='diag.systemcoach.ru'
non_ru_host='diag.glide.club'
token=''
scenario=''
samples='3'
output=''
to_stdout='no'

usage() {
    cat <<'USAGE'
Usage: collect-routing-diagnostic.sh --token TOKEN --scenario LABEL [options]

Options:
  --ru-host HOST       Default: diag.systemcoach.ru
  --non-ru-host HOST   Default: diag.glide.club
  --samples N          1-10, default: 3
  --output FILE        Explicit result path
  --stdout             Print compact TSV instead of keeping a file
  --help

The result contains public client/VPN IP addresses, request IDs and timestamps.
It does not collect cookies, credentials, device identifiers or browsing data.
USAGE
}

fail() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

validate_hostname() {
    case "$1" in
        ''|*[!a-z0-9.-]*|.*|*..*|*.) fail "invalid lowercase hostname: $1" ;;
    esac
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --ru-host) [ "$#" -ge 2 ] || fail '--ru-host requires value'; ru_host="$2"; shift ;;
        --non-ru-host) [ "$#" -ge 2 ] || fail '--non-ru-host requires value'; non_ru_host="$2"; shift ;;
        --token) [ "$#" -ge 2 ] || fail '--token requires value'; token="$2"; shift ;;
        --scenario) [ "$#" -ge 2 ] || fail '--scenario requires value'; scenario="$2"; shift ;;
        --samples) [ "$#" -ge 2 ] || fail '--samples requires value'; samples="$2"; shift ;;
        --output) [ "$#" -ge 2 ] || fail '--output requires value'; output="$2"; shift ;;
        --stdout) to_stdout='yes' ;;
        --help|-h) usage; exit 0 ;;
        *) fail "unknown argument: $1" ;;
    esac
    shift
done

validate_hostname "$ru_host"
validate_hostname "$non_ru_host"
case "$ru_host" in *.ru) : ;; *) fail 'RU host must end in .ru' ;; esac
case "$non_ru_host" in *.ru) fail 'non-RU host must not end in .ru' ;; esac
case "$token" in ''|*[!A-Za-z0-9_-]*) fail 'token must use letters, digits, _ or -' ;; esac
[ "${#token}" -ge 12 ] && [ "${#token}" -le 64 ] || fail 'token length must be 12-64'
case "$scenario" in ''|*[!A-Za-z0-9._-]*) fail 'scenario must use letters, digits, dot, _ or -' ;; esac
case "$samples" in ''|*[!0-9]*) fail 'samples must be an integer' ;; esac
[ "$samples" -ge 1 ] && [ "$samples" -le 10 ] || fail 'samples must be 1-10'
command -v curl >/dev/null 2>&1 || fail 'curl is required'
command -v dig >/dev/null 2>&1 || fail 'dig is required'

dns_ipv4() {
    dig +short A "$1" 2>/dev/null | \
        awk '/^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/ {print}' | \
        sort -u | paste -sd, -
}

ru_dns="$(dns_ipv4 "$ru_host")"
non_ru_dns="$(dns_ipv4 "$non_ru_host")"
[ -n "$ru_dns" ] || fail "no IPv4 A response for $ru_host"
[ -n "$non_ru_dns" ] || fail "no IPv4 A response for $non_ru_host"
case "$ru_dns" in *,*) fail "$ru_host resolves to multiple IPv4 addresses: $ru_dns" ;; esac
case "$non_ru_dns" in *,*) fail "$non_ru_host resolves to multiple IPv4 addresses: $non_ru_dns" ;; esac
[ "$ru_dns" = "$non_ru_dns" ] || fail "hostnames resolve to different targets: $ru_dns vs $non_ru_dns"

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
if [ -z "$output" ]; then
    output="routing-diagnostic-${scenario}-${timestamp}.tsv"
fi

tmp_result="$(mktemp "${TMPDIR:-/tmp}/gcm-routing-result.XXXXXX")" || fail 'mktemp failed'
body_file="$(mktemp "${TMPDIR:-/tmp}/gcm-routing-body.XXXXXX")" || fail 'mktemp failed'
error_file="$(mktemp "${TMPDIR:-/tmp}/gcm-routing-error.XXXXXX")" || fail 'mktemp failed'
cleanup() {
    rm -f -- "$tmp_result" "$body_file" "$error_file"
}
trap cleanup EXIT HUP INT TERM

{
    printf '# gcm_split_routing_diagnostic_version=1\n'
    printf '# created_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf '# endpoint_path=/routing-test-%s\n' "$token"
    printf '# common_dns_ipv4=%s\n' "$ru_dns"
    printf 'scenario\titeration\tkind\thost\tdns_ipv4\tconnected_ip\thttp_code\tcurl_exit\tclient_ip\trequest_id\tserver_timestamp\terror\n'
} >"$tmp_result"

run_request() {
    kind="$1"
    host="$2"
    iteration="$3"
    : >"$body_file"
    : >"$error_file"

    metrics="$(curl -4 --silent --show-error \
        --connect-timeout 10 --max-time 20 \
        --output "$body_file" \
        --write-out '%{remote_ip}|%{http_code}' \
        "https://${host}/routing-test-${token}" 2>"$error_file")"
    curl_exit="$?"
    connected_ip="${metrics%%|*}"
    http_code="${metrics#*|}"
    [ "$metrics" = "$connected_ip" ] && http_code='000'

    client_ip="$(sed -n 's/.*"client_ip":"\([^"]*\)".*/\1/p' "$body_file" | head -n 1)"
    request_id="$(sed -n 's/.*"request_id":"\([^"]*\)".*/\1/p' "$body_file" | head -n 1)"
    server_timestamp="$(sed -n 's/.*"timestamp":"\([^"]*\)".*/\1/p' "$body_file" | head -n 1)"
    response_host="$(sed -n 's/.*"host":"\([^"]*\)".*/\1/p' "$body_file" | head -n 1)"
    error_text="$(tr '\t\r\n' '   ' <"$error_file" | cut -c1-200)"

    if [ "$curl_exit" -eq 0 ] && [ "$http_code" = '200' ] && [ "$response_host" != "$host" ]; then
        error_text="unexpected response host: ${response_host:-missing}"
    fi

    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$scenario" "$iteration" "$kind" "$host" "$ru_dns" \
        "$connected_ip" "$http_code" "$curl_exit" "$client_ip" \
        "$request_id" "$server_timestamp" "$error_text" >>"$tmp_result"
}

i=1
while [ "$i" -le "$samples" ]; do
    if [ $((i % 2)) -eq 1 ]; then
        run_request 'ru' "$ru_host" "$i"
        run_request 'non_ru' "$non_ru_host" "$i"
    else
        run_request 'non_ru' "$non_ru_host" "$i"
        run_request 'ru' "$ru_host" "$i"
    fi
    i=$((i + 1))
done

if [ "$to_stdout" = 'yes' ]; then
    cat "$tmp_result"
else
    if [ -e "$output" ]; then
        fail "refusing to overwrite existing result: $output"
    fi
    mv "$tmp_result" "$output"
    tmp_result=''
    printf 'Result saved to %s\n' "$output"
    printf 'This file contains public client/VPN IP addresses; share and retain it accordingly.\n'
fi
