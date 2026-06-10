#!/bin/bash
# Запустить на VPS после первого git clone / git pull
# chmod +x deploy.sh && ./deploy.sh
set -e

echo "=== Caspian Messenger Deploy ==="

# 1. Создать .env если его нет
if [ ! -f .env ]; then
  cp .env.example .env
  echo ""
  echo "⚠  Создан .env — заполни DB_PASSWORD и JWT_KEY, затем запусти снова."
  echo ""
  exit 1
fi

# 2. Собрать образ и поднять все сервисы
docker compose \
  -f docker-compose.yml \
  -f docker-compose.prod.yml \
  up --build -d

echo ""
echo "✓ Запущен. Сервер доступен на http://$(hostname -I | awk '{print $1}')"
echo ""
echo "Следующий шаг — SSL:"
echo "  docker run --rm -it -v letsencrypt:/etc/letsencrypt -p 80:80 certbot/certbot certonly --standalone -d your-domain.com"
