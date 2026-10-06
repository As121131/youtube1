#!/usr/bin/env bash
# Шаг 2. Установка Telegram-бота Remnashop рядом с панелью.
# Запускать на том же сервере ПОСЛЕ install-panel.sh.
# Запуск: sudo bash install-bot.sh
set -euo pipefail

PANEL_DIR=/opt/remnawave
BOT_DIR=/opt/remnashop
RAW=https://raw.githubusercontent.com/snoups/remnashop/refs/heads/main

if [ "$(id -u)" -ne 0 ]; then
    echo "Запустите от root: sudo bash $0" >&2
    exit 1
fi
if [ ! -f "$PANEL_DIR/.env" ]; then
    echo "Не найдена панель в $PANEL_DIR. Сначала запустите install-panel.sh" >&2
    exit 1
fi

WEBHOOK_SECRET=$(grep -E '^WEBHOOK_SECRET_HEADER=' "$PANEL_DIR/.env" | cut -d= -f2-)

read -rp "Домен бота (тот же, что указали в install-panel.sh): " BOT_DOMAIN
read -rp "Токен бота от @BotFather: " BOT_TOKEN
read -rp "Ваш Telegram ID (число, узнать у @userinfobot): " OWNER_ID
read -rp "Username аккаунта поддержки (без @): " SUPPORT_USERNAME
read -rp "API-токен панели (Settings -> API Tokens): " REMNAWAVE_TOKEN

for v in BOT_DOMAIN BOT_TOKEN OWNER_ID SUPPORT_USERNAME REMNAWAVE_TOKEN; do
    if [ -z "${!v}" ]; then
        echo "Поле $v не заполнено." >&2
        exit 1
    fi
done

echo ">>> Скачиваю файлы бота в $BOT_DIR"
mkdir -p "$BOT_DIR"/{logs,assets,backups}
cd "$BOT_DIR"
# internal = бот и панель на одном сервере, в общей сети remnawave-network
curl -fsSL -o docker-compose.yml "$RAW/docker-compose.prod.internal.yml"
curl -fsSL -o .env "$RAW/.env.example"

set_env() {
    sed -i "s|^$1=.*|$1=$2|" .env
}

set_env APP_DOMAIN "$BOT_DOMAIN"
set_env APP_CRYPT_KEY "$(openssl rand -base64 32 | tr -d '\n')"
set_env BOT_TOKEN "$BOT_TOKEN"
set_env BOT_SECRET_TOKEN "$(openssl rand -hex 64)"
set_env BOT_OWNER_ID "$OWNER_ID"
set_env BOT_SUPPORT_USERNAME "$SUPPORT_USERNAME"
set_env REMNAWAVE_HOST "remnawave"
set_env REMNAWAVE_TOKEN "$REMNAWAVE_TOKEN"
set_env REMNAWAVE_WEBHOOK_SECRET "$WEBHOOK_SECRET"
set_env DATABASE_PASSWORD "$(openssl rand -hex 24)"
chmod 600 .env

docker compose up -d

cat <<EOF

==========================================================
 Бот запущен. Откройте его в Telegram и нажмите /start.
 Вы — владелец, поэтому увидите админ-панель прямо в боте:
   - тарифы и цены,
   - платёжные системы (Telegram Stars, CryptoPay и др.),
   - пробный период, промокоды, рефералка, рассылки.

 Логи:  cd $BOT_DIR && docker compose logs -f remnashop
==========================================================
EOF
