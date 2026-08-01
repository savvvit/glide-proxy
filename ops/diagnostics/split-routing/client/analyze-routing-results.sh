#!/bin/sh

set -u
LC_ALL=C
export LC_ALL

vpn_off=''
vpn_on=''

usage() {
    cat <<'USAGE'
Usage: analyze-routing-results.sh --vpn-off FILE --vpn-on FILE

Compares two TSV files produced by collect-routing-diagnostic.sh.
No network requests are made.
USAGE
}

fail() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --vpn-off) [ "$#" -ge 2 ] || fail '--vpn-off requires file'; vpn_off="$2"; shift ;;
        --vpn-on) [ "$#" -ge 2 ] || fail '--vpn-on requires file'; vpn_on="$2"; shift ;;
        --help|-h) usage; exit 0 ;;
        *) fail "unknown argument: $1" ;;
    esac
    shift
done

[ -f "$vpn_off" ] || fail "VPN-off file not found: $vpn_off"
[ -f "$vpn_on" ] || fail "VPN-on file not found: $vpn_on"

unique_values() {
    file="$1"
    kind="$2"
    column="$3"
    awk -F '\t' -v kind="$kind" -v column="$column" '
        $1 !~ /^#/ && $1 != "scenario" && $3 == kind && $7 == "200" && $8 == "0" && $column != "" {
            print $column
        }
    ' "$file" | sort -u
}

success_count() {
    file="$1"
    kind="$2"
    awk -F '\t' -v kind="$kind" '
        $1 !~ /^#/ && $1 != "scenario" && $3 == kind && $7 == "200" && $8 == "0" && $9 != "" {count++}
        END {print count + 0}
    ' "$file"
}

single_value() {
    values="$1"
    count="$(printf '%s\n' "$values" | awk 'NF {count++} END {print count + 0}')"
    [ "$count" -eq 1 ] || return 1
    printf '%s\n' "$values"
}

for file in "$vpn_off" "$vpn_on"; do
    for kind in ru non_ru; do
        count="$(success_count "$file" "$kind")"
        [ "$count" -ge 2 ] || fail "insufficient successful samples in $file for $kind: $count"
    done
done

off_ru_values="$(unique_values "$vpn_off" ru 9)"
off_non_values="$(unique_values "$vpn_off" non_ru 9)"
on_ru_values="$(unique_values "$vpn_on" ru 9)"
on_non_values="$(unique_values "$vpn_on" non_ru 9)"

off_ru="$(single_value "$off_ru_values")" || fail "VPN-off RU client IP is not stable: $off_ru_values"
off_non="$(single_value "$off_non_values")" || fail "VPN-off non-RU client IP is not stable: $off_non_values"
on_ru="$(single_value "$on_ru_values")" || fail "VPN-on RU client IP is not stable: $on_ru_values"
on_non="$(single_value "$on_non_values")" || fail "VPN-on non-RU client IP is not stable: $on_non_values"

all_targets="$(
    {
        unique_values "$vpn_off" ru 6
        unique_values "$vpn_off" non_ru 6
        unique_values "$vpn_on" ru 6
        unique_values "$vpn_on" non_ru 6
    } | sort -u
)"
target="$(single_value "$all_targets")" || fail "requests connected to different server IPs: $all_targets"

printf 'Common server IP: %s\n' "$target"
printf 'VPN off: RU=%s, non-RU=%s\n' "$off_ru" "$off_non"
printf 'VPN on:  RU=%s, non-RU=%s\n' "$on_ru" "$on_non"

if [ "$off_ru" != "$off_non" ]; then
    printf 'RESULT: INCONCLUSIVE — VPN-off baseline already differs by hostname.\n'
    exit 2
fi

if [ "$on_ru" = "$off_ru" ] && [ "$on_non" != "$on_ru" ]; then
    printf 'RESULT: CONFIRMED — .ru retained the direct baseline while non-.ru used a different egress.\n'
    exit 0
fi

if [ "$on_ru" = "$on_non" ]; then
    printf 'RESULT: REFUTED FOR THIS RUN — both hostnames used the same egress with VPN on.\n'
    exit 1
fi

printf 'RESULT: SPLIT OBSERVED, ATTRIBUTION INCOMPLETE — VPN-on egress differs by hostname, but RU does not match the VPN-off baseline.\n'
printf 'Check whether the direct ISP address changed and independently identify the VPN exit before concluding.\n'
exit 2
