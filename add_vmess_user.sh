#!/usr/bin/env bash
set -e

DOMAIN=$(cat /opt/v2api/domain 2>/dev/null)
TOKEN=$(cat /opt/v2api/api_token 2>/dev/null)

API_HTTPS="https://${DOMAIN}/api"
API_HTTP="http://127.0.0.1:8081/api"

if [ -z "$DOMAIN" ] || [ -z "$TOKEN" ]; then
  echo "❌ Не найден домен или токен"
  exit 1
fi

if [ -z "$1" ]; then
  echo "Использование: $0 <username>"
  exit 1
fi

NAME="$1"

echo "Добавляю клиента '${NAME}' ..."

# =====================================================
# 1. Пытаемся создать клиента через HTTPS (игнорируем SSL)
# =====================================================
RESP=$(
  curl -sS -k -X POST "${API_HTTPS}/clients" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"name\":\"$NAME\"}" \
  || true
)

# Если пусто — пробуем fallback на локальное API
if [ -z "$RESP" ]; then
  echo "⚠ HTTPS API недоступен — пробуем локальное API ..."
  RESP=$(
    curl -sS -X POST "${API_HTTP}/clients" \
      -H "Authorization: Bearer $TOKEN" \
      -H "Content-Type: application/json" \
      -d "{\"name\":\"$NAME\"}" \
    || true
  )
fi

UUID=$(echo "$RESP" | jq -r '.uuid')

if [ "$UUID" = "null" ] || [ -z "$UUID" ]; then
  echo "❌ Ошибка API:"
  echo "$RESP"
  exit 1
fi

echo "UUID: $UUID"

# =====================================================
# 2. Генерация JSON для v2rayNG
# =====================================================
VMESS_JSON=$(cat <<JSON
{
  "v": "2",
  "ps": "$NAME",
  "add": "$DOMAIN",
  "port": "443",
  "id": "$UUID",
  "aid": "0",
  "scy": "auto",
  "net": "ws",
  "type": "",
  "host": "$DOMAIN",
  "path": "/vmess",
  "tls": "tls"
}
JSON
)

# =====================================================
# 3. vmess:// base64
# =====================================================
VMESS_B64=$(echo -n "$VMESS_JSON" | base64 -w0)
VMESS_LINK="vmess://${VMESS_B64}"

echo
echo "========================================"
echo "VMESS ссылка:"
echo
echo "$VMESS_LINK"
echo
echo "========================================"
echo "QR JSON:"
echo "$VMESS_JSON"
echo "========================================"
