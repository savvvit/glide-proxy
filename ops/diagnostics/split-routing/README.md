# GCM split-routing diagnostic

Одноразовый диагностический пакет для проверки гипотезы hostname-based split routing:

- hostname в зоне `.ru` при включённом VPN выходит напрямую;
- hostname вне `.ru` при включённом VPN выходит через туннель;
- оба hostname обслуживаются одной точкой входа `node1` и одним endpoint.

Пакет не является постоянным production-решением и не разворачивает reverse proxy. Он создаёт только два изолированных Nginx virtual host с диагностическим JSON endpoint.

## Граница разрешения

Наличие кода в Git, Pull Request или merge **не разрешает**:

- изменение DNS;
- выпуск сертификата;
- запись файлов на production;
- `nginx reload`;
- удаление production-файлов или сертификатов.

Каждая из этих операций выполняется только после отдельного подтверждения владельца по принятому change plan. Скрипты не запускаются автоматически из CI и не содержат SSH/deployment automation.

## Состав

```text
split-routing/
├── README.md
├── CHANGE-PLAN.md
├── PILOT-LOG.md
├── dns/OWNER-STEPS.md
├── nginx/
│   ├── endpoint.conf.template
│   └── site.conf.template
├── server/
│   ├── common.sh
│   ├── preflight.sh
│   ├── deploy.sh
│   └── teardown.sh
├── client/
│   ├── CLIENT-INSTRUCTIONS.md
│   ├── GCM-Routing-Test.command.template
│   ├── collect-routing-diagnostic.sh
│   ├── analyze-routing-results.sh
│   └── prepare-client-bundle.sh
└── tests/run.sh
```

## Принятая тестовая схема

```text
diag.systemcoach.ru ─┐
                     ├─ A → node1 public IPv4 → Nginx → один endpoint
diag.glide.club ─────┘
```

Timeweb Load Balancer, Node.js proxy и upstream Glide не участвуют. Поэтому `$remote_addr` на `node1` является адресом TCP peer, а не адресом балансировщика.

Имена и IP имеют безопасные значения по умолчанию, основанные на принятом Production As-Is, но перед deployment обязательно подтверждаются read-only preflight:

```bash
export RU_HOST=diag.systemcoach.ru
export NON_RU_HOST=diag.glide.club
export NODE_PUBLIC_IP=77.233.221.222
export RU_CERT_LINEAGE=diag.systemcoach.ru
export NON_RU_CERT_LINEAGE=glide.club
export ENDPOINT_TOKEN='<случайная строка 12–64 символа>'
```

`ENDPOINT_TOKEN` уменьшает случайный трафик, но не является паролем или секретом. Не использовать в нём персональные данные.

## Последовательность

1. Выполнить read-only preflight до выпуска нового сертификата:

   ```bash
   sudo --preserve-env=RU_HOST,NON_RU_HOST,NODE_PUBLIC_IP,RU_CERT_LINEAGE,NON_RU_CERT_LINEAGE,ENDPOINT_TOKEN \
     ./server/preflight.sh --allow-missing-ru-cert
   ```

2. Владелец выполняет DNS-01 и выпуск отдельного сертификата по [DNS-инструкции](dns/OWNER-STEPS.md).

3. Повторить полный preflight без исключений:

   ```bash
   sudo --preserve-env=RU_HOST,NON_RU_HOST,NODE_PUBLIC_IP,RU_CERT_LINEAGE,NON_RU_CERT_LINEAGE,ENDPOINT_TOKEN \
     ./server/preflight.sh
   ```

4. Установить новые файлы, но пока не активировать их:

   ```bash
   sudo --preserve-env=RU_HOST,NON_RU_HOST,NODE_PUBLIC_IP,RU_CERT_LINEAGE,NON_RU_CERT_LINEAGE,ENDPOINT_TOKEN \
     ./server/deploy.sh --apply
   ```

   `--apply` создаёт только новые файлы, ссылку и state manifest, затем выполняет `nginx -t`. При неуспешном тесте собственные новые файлы удаляются автоматически. Reload не выполняется.

5. После проверки diff и отдельного go владельца активировать:

   ```bash
   sudo --preserve-env=RU_HOST,NON_RU_HOST,NODE_PUBLIC_IP,RU_CERT_LINEAGE,NON_RU_CERT_LINEAGE,ENDPOINT_TOKEN \
     ./server/deploy.sh --activate
   ```

6. Выполнить прямой smoke-test, затем вручную создать обе A-записи по DNS-инструкции.

7. На своём устройстве сначала проверить технические скрипты напрямую: собрать `vpn-off`, затем `vpn-on`:

   ```bash
   sh client/collect-routing-diagnostic.sh \
     --ru-host "$RU_HOST" --non-ru-host "$NON_RU_HOST" \
     --token "$ENDPOINT_TOKEN" --scenario vpn-off

   sh client/collect-routing-diagnostic.sh \
     --ru-host "$RU_HOST" --non-ru-host "$NON_RU_HOST" \
     --token "$ENDPOINT_TOKEN" --scenario vpn-on
   ```

8. После успешной собственной проверки подготовить тот же нетехнический пакет, который позже может получить клиент:

   ```bash
   GCM_BUNDLE_DIR="$HOME/Downloads/gcm-client-bundle"
   mkdir -p "$GCM_BUNDLE_DIR"
   ENDPOINT_TOKEN="$ENDPOINT_TOKEN" \
     ./client/prepare-client-bundle.sh --output-dir "$GCM_BUNDLE_DIR"
   ```

   Результат — ZIP для отправки через Telegram. Внутри находится один видимый файл `GCM Routing Test.command`: он последовательно попросит выключить и включить VPN, соберёт оба результата, выполнит локальный анализ и покажет готовый ZIP для отправки владельцу.

9. Владелец сначала проходит [клиентскую инструкцию](client/CLIENT-INSTRUCTIONS.md) на собственном Mac ровно как будущий участник. Только после фактической репетиции инструкция корректируется и может быть отправлена клиенту.

10. При необходимости сравнить отдельные технические результаты вручную:

   ```bash
   sh client/analyze-routing-results.sh \
     --vpn-off routing-diagnostic-vpn-off-*.tsv \
     --vpn-on routing-diagnostic-vpn-on-*.tsv
   ```

   Если shell раскрыл больше одного файла на сценарий, передать точные имена файлов.

11. Сохранить только минимальный evidence-набор и выполнить teardown по `CHANGE-PLAN.md`.

## Почему нужен клиентский файл

Серверный лог содержит `timestamp`, `host`, `client_ip` и `request_id`, но не знает, включён ли VPN на устройстве. Клиентский TSV:

- явно маркирует сценарий;
- подтверждает, что оба hostname разрешились в один IPv4;
- фиксирует фактический IP TCP-сервера из `curl`;
- фиксирует egress IP, увиденный сервером;
- связывает результат с Nginx-логом по `request_id`.

Файл небольшой. Он содержит публичный IP устройства/VPN, поэтому перед передачей клиенту нужно сообщить о составе данных и удалить результат после анализа согласно согласованному retention.

Retention — это максимальный срок, в течение которого диагностические TSV/ZIP и серверный лог сохраняются для проверки. Ничего не удалится автоматически через 7 дней. Владелец вручную удаляет копии из рабочей папки, Telegram и сервера сразу после принятия вывода, но не позднее 7 дней, если отдельно не согласован другой срок. Сертификат к diagnostic evidence не относится и может оставаться неиспользуемым до отдельного cleanup.

## Мини-пилот AI-assisted разработки

Для оценки методологии фиксируются:

- время владельца и Codex по этапам;
- число итераций PR;
- findings автоматических проверок и review;
- расхождения между Production As-Is и live preflight;
- ручные действия владельца и места, где инструкция оказалась недостаточной;
- успешность rollback и полнота evidence;
- решение: переиспользовать пакет, переработать или удалить.

Фактические наблюдения и трудозатраты вносятся в [PILOT-LOG.md](PILOT-LOG.md) только после соответствующего этапа. Шаблон не является разрешением на следующий gate.

Роли:

- владелец: принимает scope, production go/no-go, выполняет DNS и ручной rollout;
- Codex: готовит repo-only артефакты, тесты и анализ результатов;
- independent reviewer: Claude в отдельной review-сессии проверяет готовый Draft PR до merge; reviewer не редактирует ветку;
- merge и production deployment остаются разными gates.

## Источники

- [GCM Project Hub](https://docs.google.com/document/d/1AydvgvfxU7zW4E2qTml88vCPMC8FwJPJVTYiLpzPmCM)
- [GCM Production As-Is Report](https://docs.google.com/document/d/1BDyK4WaVWRf2kp8wTvgVHq2xKzVLbRtILb5ilLPpHnA)
- [GCM target architecture ADR](https://docs.google.com/document/d/1s-Zs-qqzNZZBmqdyDrkLexqeoTUcED_uXbQ6XmICVOc)
- [GCM read-only survey runbook](https://docs.google.com/document/d/1JmJSHYMq1NJB7mQspD1hCxg-Ydl5hVPXlNsjwJpDPzs)
