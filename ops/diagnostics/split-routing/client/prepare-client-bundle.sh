#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail
umask 077

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
RU_HOST="${RU_HOST:-diag.systemcoach.ru}"
NON_RU_HOST="${NON_RU_HOST:-diag.glide.club}"
ENDPOINT_TOKEN="${ENDPOINT_TOKEN:-}"
output_dir=''

fail() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

usage() {
    cat <<'USAGE'
Usage: ENDPOINT_TOKEN=... prepare-client-bundle.sh --output-dir DIRECTORY

Creates GCM-Routing-Test.zip for owner rehearsal and, only after that,
optional delivery through Telegram. Existing output files are not overwritten.
USAGE
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --output-dir)
            [[ $# -ge 2 ]] || fail '--output-dir requires a directory'
            output_dir="$2"
            shift
            ;;
        --help|-h) usage; exit 0 ;;
        *) fail "unknown argument: $1" ;;
    esac
    shift
done

[[ -n "$output_dir" ]] || { usage; exit 1; }
[[ -d "$output_dir" ]] || fail "output directory does not exist: $output_dir"
[[ "$RU_HOST" =~ ^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$ ]] || fail 'invalid RU_HOST'
[[ "$NON_RU_HOST" =~ ^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$ ]] || fail 'invalid NON_RU_HOST'
[[ "$RU_HOST" == *.ru ]] || fail 'RU_HOST must end in .ru'
[[ "$NON_RU_HOST" != *.ru ]] || fail 'NON_RU_HOST must not end in .ru'
[[ "$ENDPOINT_TOKEN" =~ ^[A-Za-z0-9_-]{12,64}$ ]] || fail 'invalid ENDPOINT_TOKEN'
command -v ditto >/dev/null 2>&1 || fail 'ditto is required on macOS'

bundle_dir="${output_dir}/GCM-Routing-Test"
bundle_zip="${output_dir}/GCM-Routing-Test.zip"
[[ ! -e "$bundle_dir" && ! -e "$bundle_zip" ]] || fail 'refusing to overwrite an existing client bundle'

mkdir -m 0700 "$bundle_dir"
mkdir -m 0700 "${bundle_dir}/support"

sed \
    -e "s|@@RU_HOST@@|${RU_HOST}|g" \
    -e "s|@@NON_RU_HOST@@|${NON_RU_HOST}|g" \
    -e "s|@@ENDPOINT_TOKEN@@|${ENDPOINT_TOKEN}|g" \
    "${SCRIPT_DIR}/GCM-Routing-Test.command.template" \
    >"${bundle_dir}/GCM Routing Test.command"

cp "${SCRIPT_DIR}/collect-routing-diagnostic.sh" "${bundle_dir}/support/"
cp "${SCRIPT_DIR}/analyze-routing-results.sh" "${bundle_dir}/support/"
chmod 0700 "${bundle_dir}/GCM Routing Test.command"
chmod 0700 "${bundle_dir}/support/collect-routing-diagnostic.sh"
chmod 0700 "${bundle_dir}/support/analyze-routing-results.sh"

cat >"${bundle_dir}/ПРОЧИТАЙТЕ.txt" <<'TEXT'
Откройте файл «GCM Routing Test.command» через Control + клик → «Открыть».
Следуйте сообщениям в появившемся окне. Не изменяйте настройки безопасности macOS.
После завершения отправьте владельцу созданный ZIP с результатами через Telegram.
TEXT

ditto -c -k --sequesterRsrc --keepParent "$bundle_dir" "$bundle_zip"
printf 'Client bundle created: %s\n' "$bundle_zip"
printf 'Rehearse the exact Telegram-to-result flow on an owner device before client delivery.\n'
