# Change plan: one-time split-routing diagnostic

## Status

Repo-only draft. Production changes are not authorized by this document, its review, merge, or release.

## Objective and success criterion

Проверить на одном устройстве, меняется ли публичный egress IP в зависимости только от hostname при включённом VPN.

Успешное подтверждение требует одновременно:

1. оба hostname разрешаются в один IPv4 `node1`;
2. `curl` для обоих hostname соединяется с тем же IPv4;
3. VPN off: оба hostname дают один direct egress IP;
4. VPN on: `.ru` даёт direct IP, а non-`.ru` — отличный VPN egress IP;
5. результат повторяется минимум три раза и подтверждается серверным `request_id`.

Если VPN on для обоих hostname стабильно даёт один и тот же egress, проверяемая гипотеза для этого VPN-клиента опровергнута. Один тест не обобщает результат на все VPN-продукты и всех пользователей.

## Scope

Только `node1`:

- два точных Nginx `server_name`;
- один общий JSON endpoint;
- отдельный ограниченный access log;
- отдельный сертификат для `.ru` hostname;
- существующий wildcard-сертификат для `diag.glide.club` после live-проверки SAN.

Вне scope:

- node2;
- Timeweb Load Balancer;
- Node.js/PM2;
- существующие зеркала;
- firewall;
- постоянный ACME/renewal процесс;
- исправление real IP или rate limiting GCM.

## Preconditions

- принят отдельный production go владельца;
- read-only preflight соответствует фактам или все отклонения рассмотрены;
- controlled SSH выполняется владельцем в одной сессии только на `node1`;
- оба hostname и `node1` public IPv4 подтверждены;
- существующие целевые Nginx-файлы отсутствуют;
- нет точного конфликтующего `server_name`;
- wildcard-сертификат валиден для non-`.ru` hostname не менее суток;
- новый сертификат валиден для `.ru` hostname не менее суток;
- выбран непредсказуемый endpoint token;
- определены контакт и stop conditions.

## Files created on node1

```text
/etc/nginx/sites-available/gcm-routing-ab-test.conf
/etc/nginx/sites-enabled/gcm-routing-ab-test.conf
/etc/nginx/snippets/gcm-routing-ab-endpoint.conf
/var/lib/gcm-routing-ab-test/state
/var/log/nginx/gcm-routing-ab-test.log
```

Существующие site-файлы, main `nginx.conf`, Node.js и certificate lineages скриптами не изменяются.

## Deployment stages

### Stage 0 — read-only preflight

- проверить `nginx -t`;
- получить только санитизированный результат поиска конфликтующих `server_name` через effective `nginx -T`;
- проверить layout `sites-available/sites-enabled/snippets`;
- проверить public certificate metadata без чтения private keys;
- проверить metadata private-key path без вывода содержимого;
- зафиксировать время и версию Nginx.

### Stage 1 — certificate

Владелец выпускает отдельный `diag.systemcoach.ru` lineage через текущий manual DNS-01 процесс. Новый hostname не добавляется в существующий wildcard GCM.

### Stage 2 — install without reload

`deploy.sh --apply` рендерит конфигурацию, создаёт только отсутствующие файлы, создаёт symlink и state manifest, затем выполняет `nginx -t`. Reload отсутствует.

### Stage 3 — activation

После ручной проверки файлов и отдельного go `deploy.sh --activate` повторно проверяет hashes и `nginx -t`, затем выполняет один `systemctl reload nginx`.

### Stage 4 — smoke-test and DNS

До DNS выполнить прямой smoke-test с SNI/Host override. После этого владелец создаёт две A-записи на один IPv4. Основной VPN-тест нельзя выполнять с `--resolve`, потому что это может обойти hostname/DNS-механику VPN.

### Stage 5 — experiment

- собственное устройство владельца: VPN off, затем VPN on;
- минимум три парных запроса в каждом сценарии;
- после успешной собственной проверки — опциональный клиентский запуск;
- серверный лог используется только для сопоставления `request_id`.

## Data minimization and retention

Endpoint и отдельный лог содержат только:

- host;
- public client/VPN IP;
- request id;
- timestamp.

Не записываются query string, cookies, authorization headers, User-Agent или полный стандартный access log. Клиентские TSV и серверный лог удаляются после принятия результата; рекомендуемый максимальный retention для одноразового теста — 7 дней.

## Stop conditions

Немедленно остановиться, если:

- live topology или Nginx layout расходится с принятым As-Is;
- обнаружен точный конфликт `server_name` или целевого пути;
- требуется читать private key, `.env`, token или иной секрет;
- сертификат не покрывает hostname или истекает менее чем через сутки;
- `nginx -t` неуспешен;
- reload неуспешен;
- существующее зеркало перестало проходить smoke-test;
- оба DNS-имени не разрешаются строго в один и тот же IPv4;
- endpoint отвечает через LB/CDN или другой server IP;
- наблюдается деградация или неожиданная нагрузка.

## Rollback

1. Прекратить новые запросы и сохранить минимальный evidence.
2. Вручную удалить A `diag.systemcoach.ru`; проверить отсутствие wildcard fallback.
3. Для `diag.glide.club` заменить A на явный TXT tombstone без A/AAAA, иначе существующий `*.glide.club` снова направит имя в LB.
4. Выждать не менее двух TTL и проверить публичный DNS.
5. Выполнить `teardown.sh --apply --dns-confirmed`: обязательный флаг подтверждает завершение ручного DNS teardown; скрипт сверяет hashes, удаляет только собственный symlink, выполняет `nginx -t`, reload, затем удаляет собственные site/snippet/state и по умолчанию диагностический лог.
6. Выполнить smoke-test существующих зеркал.
7. Отдельным согласованным действием удалить временный certificate lineage. `teardown.sh` сертификаты не удаляет.

Если teardown обнаруживает изменённый hash, он останавливается и ничего не удаляет до ручного review.

## Evidence package

Минимальный пакет:

- два клиентских TSV: VPN off и VPN on;
- вывод `analyze-routing-results.sh`;
- санитизированные совпадения server log по `request_id`;
- время теста, выбранный VPN exit и версия клиентского скрипта;
- результат post-teardown smoke-test.

## Owner decisions before production

- hostname и точный endpoint token;
- TTL и окно теста;
- разрешение на выпуск сертификата;
- разрешение на `deploy --apply`;
- отдельное разрешение на `deploy --activate`/reload;
- нужен ли клиентский запуск после собственной проверки;
- retention и момент удаления evidence;
- удалять ли certificate lineage после теста.
