#!/usr/bin/env bash
# Шаг 1. Установка панели Remnawave + Caddy (HTTPS) на основной сервер.
# Запуск: sudo bash install-panel.sh
set -euo pipefail

PANEL_DIR=/opt/remnawave
CADDY_DIR=/opt/remnawave/caddy
RAW=https://raw.githubusercontent.com/remnawave/backend/refs/heads/main

if [ "$(id -u)" -ne 0 ]; then
    echo "Запустите от root: sudo bash $0" >&2
    exit 1
fi

read -rp "Домен панели (например panel.example.com): " PANEL_DOMAIN
read -rp "Домен бота   (например bot.example.com):   " BOT_DOMAIN
if [ -z "$PANEL_DOMAIN" ] || [ -z "$BOT_DOMAIN" ]; then
    echo "Оба домена обязательны." >&2
    exit 1
fi

# --- Docker ---
if ! command -v docker >/dev/null 2>&1; then
    echo ">>> Устанавливаю Docker"
    curl -fsSL https://get.docker.com | sh
fi
apt-get install -y openssl curl >/dev/null 2>&1 || true

# --- Панель ---
echo ">>> Скачиваю файлы панели в $PANEL_DIR"
mkdir -p "$PANEL_DIR"
cd "$PANEL_DIR"
curl -fsSL -o docker-compose.yml "$RAW/docker-compose-prod.yml"
curl -fsSL -o .env "$RAW/.env.sample"

echo ">>> Генерирую секреты"
sed -i "s|^APP_SECRET=.*|APP_SECRET=$(openssl rand -hex 64)|" .env
sed -i "s|^METRICS_PASS=.*|METRICS_PASS=$(openssl rand -hex 64)|" .env
sed -i "s|^WEBHOOK_SECRET_HEADER=.*|WEBHOOK_SECRET_HEADER=$(openssl rand -hex 32)|" .env
pw=$(openssl rand -hex 24)
sed -i "s|^POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=$pw|" .env
sed -i "s|^\(DATABASE_URL=\"postgresql://postgres:\)[^@]*\(@.*\)|\1$pw\2|" .env

echo ">>> Прописываю домены и вебхук для бота"
sed -i "s|^PANEL_DOMAIN=.*|PANEL_DOMAIN=$PANEL_DOMAIN|" .env
sed -i "s|^FRONT_END_DOMAIN=.*|FRONT_END_DOMAIN=$PANEL_DOMAIN|" .env
sed -i "s|^SUB_PUBLIC_DOMAIN=.*|SUB_PUBLIC_DOMAIN=$PANEL_DOMAIN/api/sub|" .env
# Панель шлёт события (продление, окончание трафика и т.д.) боту по внутренней сети Docker.
sed -i "s|^WEBHOOK_ENABLED=.*|WEBHOOK_ENABLED=true|" .env
sed -i "s|^WEBHOOK_URL=.*|WEBHOOK_URL=http://remnashop:5000/api/v1/remnawave|" .env

docker compose up -d

# --- Caddy (HTTPS-сертификаты автоматически) ---
echo ">>> Настраиваю Caddy"
mkdir -p "$CADDY_DIR"
cat > "$CADDY_DIR/Caddyfile" <<EOF
https://$PANEL_DOMAIN {
    encode
    reverse_proxy * http://remnawave:3000
}

https://$BOT_DOMAIN {
    encode
    reverse_proxy * http://remnashop:5000
}

:443 {
    tls internal
    respond 204
}
EOF

cat > "$CADDY_DIR/docker-compose.yml" <<'EOF'
services:
  caddy:
    image: caddy:2.9
    container_name: caddy
    hostname: caddy
    restart: always
    ports:
      - '0.0.0.0:443:443'
      - '0.0.0.0:80:80'
    networks:
      - remnawave-network
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile
      - caddy-ssl-data:/data

networks:
  remnawave-network:
    name: remnawave-network
    driver: bridge
    external: true

volumes:
  caddy-ssl-data:
    name: caddy-ssl-data
    driver: local
EOF

(cd "$CADDY_DIR" && docker compose up -d)

cat <<EOF

==========================================================
 Панель запущена: https://$PANEL_DOMAIN

 СРАЗУ откройте её и зарегистрируйтесь — первый
 зарегистрированный пользователь становится супер-админом.

 Дальше по инструкции README.md:
   1) подключите ноду (VPN-сервер);
   2) создайте API-токен: Settings -> API Tokens;
   3) запустите: sudo bash install-bot.sh
==========================================================
EOF
