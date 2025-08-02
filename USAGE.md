# Universal Reverse Proxy Installer - Инструкция по использованию

## Описание

Универсальный установщик для автоматического развертывания production-ready Node.js reverse proxy с HTTPS поддержкой. Скрипт полностью автоматизирует процесс установки и настройки.

## Возможности

✅ **Автоматическая установка всех зависимостей**
- Node.js 18.x
- PM2 process manager
- nginx с SSL termination
- Let's Encrypt сертификаты

✅ **Production-ready конфигурация**
- HTTPS с автоматическим обновлением сертификатов
- Rate limiting и security headers
- Comprehensive logging (Winston + PM2)
- Health monitoring endpoints
- Firewall настройка

✅ **Продвинутый URL rewriting**
- HTML/CSS/JavaScript content transformation
- Cookie domain rewriting
- PWA и SPA поддержка

✅ **Мониторинг и управление**
- Автоматические health checks
- Скрипты управления
- Подробная документация

## Способы использования

### 1. Интерактивный режим (рекомендуется для первого использования)

```bash
# Загрузите скрипт на сервер
wget https://raw.githubusercontent.com/savvvit/glide-proxy/balancer/universal-proxy-installer.sh
# или
curl -O https://raw.githubusercontent.com/savvvit/glide-proxy/balancer/universal-proxy-installer.sh

# Сделайте исполняемым
chmod +x universal-proxy-installer.sh

# Запустите с правами root
sudo ./universal-proxy-installer.sh
```

Скрипт запросит следующие параметры:
- **Домен прокси** (например, `proxy.example.com`)
- **Целевой домен** (например, `old.example.com`)
- **Сервер SSL** (например, `node1.proxy.example.com`)
- **Email для SSL** (например, `admin@example.com`)
- **Имя проекта** (например, `my-proxy`)

Дополнительные параметры (опциональные):
- **Порт Node.js** (по умолчанию: 3000)
- **Протокол цели** (по умолчанию: https)
- **Лимит памяти** (по умолчанию: 512M)
- **Rate limiting** (по умолчанию: 10 req/sec)

### 2. Автоматический режим (через переменные окружения)

```bash
# Установите переменные окружения
export PROXY_DOMAIN="proxy.example.com"
export TARGET_DOMAIN="old.example.com"
export SERVER_DOMAIN="node1.proxy.example.com"
export SSL_EMAIL="admin@example.com"
export PROJECT_NAME="my-proxy"

# Опциональные параметры
export NODE_PORT="3000"
export TARGET_PROTOCOL="https"
export MAX_MEMORY="512M"
export RATE_LIMIT="10"
export AUTO_CONFIRM="yes"

# Запустите установку
sudo ./universal-proxy-installer.sh
```

### 3. One-liner установка

```bash
curl -sSL https://raw.githubusercontent.com/savvvit/glide-proxy/balancer/universal-proxy-installer.sh | \
PROXY_DOMAIN="proxy.example.com" \
TARGET_DOMAIN="old.example.com" \
SERVER_DOMAIN="node1.proxy.example.com" \
SSL_EMAIL="admin@example.com" \
PROJECT_NAME="my-proxy" \
AUTO_CONFIRM="yes" \
sudo bash
```

## Примеры конфигураций

### Пример 1: Простой reverse proxy

```bash
export PROXY_DOMAIN="proxy.mysite.com"
export TARGET_DOMAIN="old.mysite.com"
export SERVER_DOMAIN="node1.proxy.mysite.com"
export SSL_EMAIL="admin@mysite.com"
export PROJECT_NAME="mysite-proxy"
sudo ./universal-proxy-installer.sh
```

### Пример 2: High-performance конфигурация

```bash
export PROXY_DOMAIN="api-proxy.company.com"
export TARGET_DOMAIN="legacy-api.company.com"
export SERVER_DOMAIN="node1.api-proxy.company.com"
export SSL_EMAIL="devops@company.com"
export PROJECT_NAME="api-proxy"
export NODE_PORT="8080"
export MAX_MEMORY="1G"
export RATE_LIMIT="50"
sudo ./universal-proxy-installer.sh
```

### Пример 3: HTTP target с HTTPS proxy

```bash
export PROXY_DOMAIN="secure.example.com"
export TARGET_DOMAIN="internal.example.com"
export TARGET_PROTOCOL="http"
export SERVER_DOMAIN="node1.secure.example.com"
export SSL_EMAIL="security@example.com"
export PROJECT_NAME="secure-proxy"
sudo ./universal-proxy-installer.sh
```

## Требования к системе

### Поддерживаемые ОС
- Ubuntu 18.04+ (рекомендуется 20.04+)
- Debian 10+
- CentOS 8+ (требует адаптации)

### Минимальные требования
- **RAM**: 512MB (рекомендуется 1GB+)
- **Disk**: 2GB свободного места
- **Network**: доступ к интернету для установки пакетов
- **Ports**: 22 (SSH), 80 (HTTP), 443 (HTTPS)

### DNS настройка
Перед запуском убедитесь, что:
- DNS записи для `SERVER_DOMAIN` указывают на ваш сервер
- Домен доступен по HTTP (для Let's Encrypt challenge)

## Что происходит во время установки

1. **Проверка системы** - права root, доступность пакетов
2. **Установка зависимостей** - Node.js, PM2, nginx, certbot
3. **Создание проекта** - структура файлов, конфигурации
4. **Установка Node.js пакетов** - Express, proxy middleware, логирование
5. **SSL настройка** - получение Let's Encrypt сертификата
6. **nginx конфигурация** - SSL termination, proxy settings
7. **Запуск сервисов** - PM2 приложение, nginx reload
8. **Firewall настройка** - открытие портов 80, 443
9. **Создание утилит** - скрипты управления, документация
10. **Верификация** - проверка работоспособности всех компонентов

## После установки

### Проверка статуса
```bash
# Перейдите в директорию проекта
cd /opt/your-project-name

# Проверьте статус всех сервисов
./scripts/status.sh
```

### Управление сервисами
```bash
# Перезапуск
./scripts/restart.sh

# Просмотр логов
./scripts/logs.sh

# Обновление SSL сертификата
./scripts/renew-ssl.sh
```

### Мониторинг
```bash
# PM2 мониторинг
pm2 monit

# Health check
curl https://your-server-domain.com/health

# nginx статус
systemctl status nginx
```

### Endpoints
- **Main Proxy**: `https://your-proxy-domain.com/`
- **Health Check**: `https://your-server-domain.com/health`
- **Detailed Health**: `https://your-server-domain.com/health/detailed`  
- **nginx Health**: `https://your-server-domain.com/nginx-health`

## Настройка и кастомизация

### Изменение конфигурации
```bash
# Основная конфигурация приложения
nano /opt/your-project-name/.env

# PM2 конфигурация
nano /opt/your-project-name/ecosystem.config.js

# nginx конфигурация
nano /etc/nginx/sites-available/your-project-name
```

### Применение изменений
```bash
# Перезапуск приложения
pm2 restart your-project-name

# Перезагрузка nginx
systemctl reload nginx
```

## Troubleshooting

### Проблемы с SSL
```bash
# Проверка статуса сертификата
certbot certificates

# Ручное обновление
certbot renew --dry-run

# Проверка nginx конфигурации
nginx -t
```

### Проблемы с приложением
```bash
# Логи PM2
pm2 logs your-project-name

# Логи приложения
tail -f /opt/your-project-name/logs/app-*.log

# Логи ошибок
tail -f /opt/your-project-name/logs/error-*.log
```

### Проблемы с nginx
```bash
# nginx логи
tail -f /var/log/nginx/your-domain.error.log

# Проверка конфигурации
nginx -t

# Статус сервиса
systemctl status nginx
```

### Проблемы с сетью
```bash
# Проверка портов
netstat -tlnp | grep -E ":80|:443|:3000"

# Проверка firewall
ufw status

# Тест подключения к target
curl -I https://your-target-domain.com
```

## Безопасность

### Рекомендации
- Регулярно обновляйте систему: `apt update && apt upgrade`
- Мониторьте логи на подозрительную активность
- Настройте fail2ban для защиты от брute-force атак
- Используйте strong passwords и SSH keys

### Логирование
Все логи сохраняются в:
- **Приложение**: `/opt/your-project-name/logs/`
- **nginx**: `/var/log/nginx/`
- **PM2**: `/opt/your-project-name/logs/pm2-*.log`

## Обновления

### Автоматические
- SSL сертификаты обновляются автоматически через certbot
- PM2 перезапускает приложение при сбоях
- Ежедневный restart в 3:00 AM для очистки памяти

### Ручные
```bash
# Обновление Node.js пакетов
cd /opt/your-project-name
npm update

# Обновление PM2
npm update -g pm2

# Обновление системы
apt update && apt upgrade
```

## Удаление

```bash
# Остановка сервисов
pm2 delete your-project-name
pm2 save

# Удаление nginx конфигурации
rm /etc/nginx/sites-enabled/your-project-name
rm /etc/nginx/sites-available/your-project-name
systemctl reload nginx

# Удаление SSL сертификата
certbot delete --cert-name your-domain.com

# Удаление проекта
rm -rf /opt/your-project-name

# Закрытие портов firewall (опционально)
ufw delete allow 80/tcp
ufw delete allow 443/tcp
```

## Поддержка

При возникновении проблем:
1. Проверьте статус: `./scripts/status.sh`
2. Просмотрите логи: `./scripts/logs.sh`
3. Проверьте документацию: `cat README.md`
4. Используйте health endpoints для диагностики

## Лицензия

MIT License - свободное использование и модификация. 
