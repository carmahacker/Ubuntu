#!/usr/bin/env bash
set -e

# ===== Настройки =====
DOMAIN=$(cat /opt/v2api/domain 2>/dev/null)
TOKEN=$(cat /opt/v2api/api_token 2>/dev/null)
API="https://${DOMAIN}/api"

if [ -z "$DOMAIN" ] || [ -z "$TOKEN" ]; then
  echo "❌ Не найден файл /opt/v2api/domain или api_token"
  exit 1
fi

if [ -z "$1" ]; then
  echo "Использование: $0 <username>"
  exit 1
fi

NAME="$1"

echo "Добавляю клиента '${NAME}' ..."

RESP=$(curl -s -X POST "$API/clients" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"name\":\"$NAME\"}")

UUID=$(echo "$RESP" | jq -r '.uuid')

if [ "$UUID" = "null" ]; then
  echo "❌ Ошибка API:"
  echo "$RESP"
  exit 1
fi

echo "UUID: $UUID"

# ===== VMess JSON для клиентов =====
VMESS_JSON=$(cat <<EOF
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
EOF
)

# ===== Base64 кодирование =====
VMESS_B64=$(echo -n "$VMESS_JSON" | base64 -w0)
VMESS_LINK="vmess://${VMESS_B64}"

echo
echo "========================================"
echo "VMESS ссылка для подключения:"
echo
echo "$VMESS_LINK"
echo
echo "========================================"
echo "QR JSON (для v2rayNG):"
echo "$VMESS_JSON"
echo "========================================"

exit 0
