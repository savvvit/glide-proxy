# Ручные DNS-шаги владельца

DNS изменяется только вручную владельцем после отдельного production go. Скрипты репозитория не обращаются к DNS provider API.

## 1. До выпуска сертификата

Подтвердить:

- `systemcoach.ru` и `glide.club` находятся под ожидаемым управлением;
- `diag.systemcoach.ru` не имеет конфликтующих A/AAAA/CNAME;
- `diag.glide.club` сейчас может разрешаться через wildcard `*.glide.club`; это ожидаемо до создания явной записи;
- для обоих имён можно установить TTL 300;
- CDN/proxying выключен, используются обычные DNS records.

## 2. Сертификат `diag.systemcoach.ru`

На `node1` использовать существующий согласованный Certbot manual DNS-01 процесс. Ожидаемая форма команды после live-проверки установленной версии Certbot:

```bash
sudo certbot certonly --manual --preferred-challenges dns \
  --cert-name diag.systemcoach.ru \
  -d diag.systemcoach.ru
```

Certbot покажет имя и значение TXT challenge. В DNS UI:

1. создать только показанную TXT-запись;
2. дождаться её публичного разрешения;
3. продолжить Certbot;
4. проверить только public certificate metadata и SAN;
5. удалить challenge TXT после успешного выпуска и подтверждения владельцем.

Не копировать в Git/чат private key, credential DNS, cookies или полный Certbot account state. Этот одноразовый lineage не добавляется в существующий wildcard и не считается автоматически продлеваемым.

## 3. Публикация теста

Только после успешных `deploy --apply`, ручной проверки, `deploy --activate` и прямого smoke-test создать:

| Name | Type | Value | TTL |
|---|---|---|---:|
| `diag.systemcoach.ru` | A | подтверждённый public IPv4 `node1` | 300 |
| `diag.glide.club` | A | тот же public IPv4 `node1` | 300 |

Не создавать AAAA или CNAME. Если provider поддерживает proxy/CDN mode, он должен быть выключен.

Проверить разрешёнными публичными командами:

```bash
dig +noall +answer diag.systemcoach.ru A
dig +noall +answer diag.systemcoach.ru AAAA
dig +noall +answer diag.glide.club A
dig +noall +answer diag.glide.club AAAA
```

Критерий продолжения: ровно один и тот же A для обоих имён, AAAA отсутствуют.

## 4. Teardown DNS

После сохранения результата:

1. удалить A `diag.systemcoach.ru`;
2. проверить, не существует ли wildcard в `systemcoach.ru`; при наличии wildcard оставить явный TXT tombstone без A/AAAA;
3. у `diag.glide.club` сначала создать явный TXT tombstone, например `inactive`, затем удалить A;
4. убедиться, что запрос A для `diag.glide.club` возвращает NODATA и не падает обратно на `*.glide.club → Timeweb LB`;
5. выждать не менее двух TTL;
6. только после проверки DNS выполнять server teardown.

TXT tombstone не является секретом. Его можно оставить для подавления wildcard до окончательного решения об имени.
