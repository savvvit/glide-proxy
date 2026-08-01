#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

TEST_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
PACKAGE_DIR="$(CDPATH= cd -- "${TEST_DIR}/.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf -- "$tmp_dir"' EXIT

bash -n "${PACKAGE_DIR}/server/common.sh"
bash -n "${PACKAGE_DIR}/server/preflight.sh"
bash -n "${PACKAGE_DIR}/server/deploy.sh"
bash -n "${PACKAGE_DIR}/server/teardown.sh"
sh -n "${PACKAGE_DIR}/client/collect-routing-diagnostic.sh"
sh -n "${PACKAGE_DIR}/client/analyze-routing-results.sh"

mkdir "${tmp_dir}/render"
RU_HOST='diag.systemcoach.ru' \
NON_RU_HOST='diag.glide.club' \
NODE_PUBLIC_IP='77.233.221.222' \
RU_CERT_LINEAGE='diag.systemcoach.ru' \
NON_RU_CERT_LINEAGE='glide.club' \
ENDPOINT_TOKEN='test-token-123456' \
    "${PACKAGE_DIR}/server/deploy.sh" --render "${tmp_dir}/render"

! grep -R '@@' "${tmp_dir}/render"
grep -q 'server_name diag.systemcoach.ru;' "${tmp_dir}/render/site.conf"
grep -q 'server_name diag.glide.club;' "${tmp_dir}/render/site.conf"
grep -q 'location = /routing-test-test-token-123456' "${tmp_dir}/render/endpoint.conf"

write_fixture() {
    local file="$1"
    local scenario="$2"
    local ru_ip="$3"
    local non_ru_ip="$4"
    {
        printf '# gcm_split_routing_diagnostic_version=1\n'
        printf 'scenario\titeration\tkind\thost\tdns_ipv4\tconnected_ip\thttp_code\tcurl_exit\tclient_ip\trequest_id\tserver_timestamp\terror\n'
        for iteration in 1 2 3; do
            printf '%s\t%s\tru\tdiag.systemcoach.ru\t77.233.221.222\t77.233.221.222\t200\t0\t%s\tr%s\t2026-08-01T00:00:00+03:00\t\n' \
                "$scenario" "$iteration" "$ru_ip" "$iteration"
            printf '%s\t%s\tnon_ru\tdiag.glide.club\t77.233.221.222\t77.233.221.222\t200\t0\t%s\tn%s\t2026-08-01T00:00:01+03:00\t\n' \
                "$scenario" "$iteration" "$non_ru_ip" "$iteration"
        done
    } >"$file"
}

write_fixture "${tmp_dir}/off.tsv" vpn-off 198.51.100.10 198.51.100.10
write_fixture "${tmp_dir}/on.tsv" vpn-on 198.51.100.10 203.0.113.20

analysis_output="$(${PACKAGE_DIR}/client/analyze-routing-results.sh \
    --vpn-off "${tmp_dir}/off.tsv" --vpn-on "${tmp_dir}/on.tsv")"
grep -q 'RESULT: CONFIRMED' <<<"$analysis_output"

write_fixture "${tmp_dir}/on-same.tsv" vpn-on 203.0.113.20 203.0.113.20
set +o errexit
refuted_output="$(${PACKAGE_DIR}/client/analyze-routing-results.sh \
    --vpn-off "${tmp_dir}/off.tsv" --vpn-on "${tmp_dir}/on-same.tsv")"
refuted_status=$?
set -o errexit
[[ "$refuted_status" -eq 1 ]]
grep -q 'RESULT: REFUTED' <<<"$refuted_output"

"${PACKAGE_DIR}/client/collect-routing-diagnostic.sh" --help >/dev/null
"${PACKAGE_DIR}/server/preflight.sh" --help >/dev/null
"${PACKAGE_DIR}/server/deploy.sh" --help >/dev/null
"${PACKAGE_DIR}/server/teardown.sh" --help >/dev/null

printf 'All split-routing diagnostic tests passed.\n'
