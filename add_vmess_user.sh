#!/usr/bin/env bash
set -e

# ===== Настройки =====
DOMAIN=$(cat /opt/v2api/domain 2>/dev/null)
TOKEN=$(cat /opt/v2api/api_token 2>/dev/null)
API="https://${DOMAIN}/api"

CONF_DIR="/usr/local/etc/v2ray/conf"

if [ -z "$DOMAIN" ] || [ -z "$TOKEN" ]; then
  echo "❌ Не найден файл /opt/v2api/domain или api_token"
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "❌ Требуется jq (apt install -y jq)"
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

if [ "$UUID" = "null" ] || [ -z "$UUID" ]; then
  echo "❌ Ошибка API:"
  echo "$RESP"
  exit 1
fi

echo "UUID: $UUID"

# ===== Текст частичного конфига (FHS) =====
CLIENT_FILE="${CONF_DIR}/client-${UUID}.json"

mkdir -p "$CONF_DIR"

cat > "$CLIENT_FILE" <<JSON
{
  "inbounds": [
    {
      "tag": "vmess_ws",
      "settings": {
        "clients": [
          {
            "id": "${UUID}",
            "alterId": 0,
            "email": "${NAME}"
          }
        ]
      }
    }
  ]
}
JSON

chown root:root "$CLIENT_FILE"
chmod 644 "$CLIENT_FILE"

systemctl restart v2ray

# ===== VMess JSON =====
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

# ===== Base64 =====
VMESS_B64=$(echo -n "$VMESS_JSON" | base64 -w0)
VMESS_LINK="vmess://${VMESS_B64}"

echo
echo "========================================"
echo "VMESS ссылка:"
echo "$VMESS_LINK"
echo
echo "========================================"
echo "QR JSON:"
echo "$VMESS_JSON"
echo "========================================"
