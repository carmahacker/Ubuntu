#!/usr/bin/env bash
set -e

# ============================================
# 0. Проверка прав
# ============================================
if [ "$EUID" -ne 0 ]; then
  echo "Запустите скрипт от root, например:"
  echo "  sudo -i"
  echo "  bash setup_v2r.sh"
  exit 1
fi

echo "=== Установка V2Ray VMess + API + PostgreSQL + Nginx ==="

# ============================================
# 1. Ввод доменного имени
# ============================================
read -rp "Введите доменное имя (например vp3.mt-2.ru): " DOMAIN

if [ -z "$DOMAIN" ]; then
  echo "Домен не может быть пустым"
  exit 1
fi

# ============================================
# 2. Создание системного пользователя v2api
# ============================================
if ! id v2api >/dev/null 2>&1; then
  useradd -r -s /usr/sbin/nologin v2api
fi

APP_DIR="/opt/v2api"
mkdir -p "$APP_DIR"
chown -R v2api:v2api "$APP_DIR"

# сохраняем домен для add_vmess_user.sh
echo "$DOMAIN" > "$APP_DIR/domain"
chown v2api:v2api "$APP_DIR/domain"
chmod 644 "$APP_DIR/domain"

# ============================================
# 3. API_TOKEN: читаем из файла или генерируем
# ============================================
TOKEN_FILE="$APP_DIR/api_token"

if [ -f "$TOKEN_FILE" ]; then
  API_TOKEN=$(cat "$TOKEN_FILE")
  echo "Найден существующий API_TOKEN:"
  echo "$API_TOKEN"
else
  API_TOKEN=$(tr -dc 'A-Za-z0-9_-' </dev/urandom | head -c 48)
  echo "$API_TOKEN" > "$TOKEN_FILE"
  chmod 600 "$TOKEN_FILE"
  chown v2api:v2api "$TOKEN_FILE"
  echo "Сгенерирован новый API_TOKEN:"
  echo "$API_TOKEN"
fi

echo

# ============================================
# 4. Установка пакетов
# ============================================
echo "=== Устанавливаю пакеты (Python, Nginx, PostgreSQL, UFW, curl, unzip, jq) ==="
apt update
DEBIAN_FRONTEND=noninteractive apt install -y \
  python3 python3-venv python3-pip \
  nginx certbot python3-certbot-nginx \
  postgresql postgresql-contrib \
  ufw jq curl unzip

# Если установлен пакетный v2ray — удалим его, чтобы не мешал FHS-версии
if dpkg -l | grep -q '^ii  v2ray '; then
  echo "=== Обнаружен пакет v2ray из репозитория — удаляю ==="
  apt remove --purge -y v2ray || true
  rm -rf /etc/v2ray || true
fi

# ============================================
# 5. Установка V2Ray через FHS installer
# ============================================
echo "=== Устанавливаю V2Ray через FHS installer (v2fly) ==="
curl -fsSL https://raw.githubusercontent.com/v2fly/fhs-install-v2ray/master/install-release.sh -o /tmp/install_v2ray.sh
bash /tmp/install_v2ray.sh
rm -f /tmp/install_v2ray.sh

# Директории V2Ray по FHS
V2RAY_ETC="/usr/local/etc/v2ray"
V2RAY_CONF_DIR="$V2RAY_ETC/conf"
mkdir -p "$V2RAY_CONF_DIR"

# Логи V2Ray
mkdir -p /var/log/v2ray
chown nobody:nogroup /var/log/v2ray || true
chmod 755 /var/log/v2ray || true

# ============================================
# 6. Настройка PostgreSQL
# ============================================
echo "=== Настраиваю PostgreSQL (пользователь v2ray_user, база v2ray_db) ==="

PG_HBA=$(ls /etc/postgresql/*/main/pg_hba.conf | head -n1)

# create role if not exists
(cd /tmp && sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='v2ray_user'" | grep -q 1) || \
  (cd /tmp && sudo -u postgres psql -c "CREATE ROLE v2ray_user LOGIN PASSWORD '${API_TOKEN}';")

# ensure db exists
(cd /tmp && sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname='v2ray_db'" | grep -q 1) || \
  (cd /tmp && sudo -u postgres createdb -O v2ray_user v2ray_db)

# ensure password is synced with API_TOKEN
(cd /tmp && sudo -u postgres psql -c "ALTER ROLE v2ray_user WITH PASSWORD '${API_TOKEN}';")

# ensure pg_hba has proper line
if ! grep -q "v2ray_db" "$PG_HBA"; then
  sed -i "1ilocal   v2ray_db   v2ray_user                                md5" "$PG_HBA"
fi

systemctl restart postgresql

# create table if not exists, then fix ownership
cd /tmp
sudo -u postgres psql -d v2ray_db -c "
CREATE TABLE IF NOT EXISTS clients (
    id SERIAL PRIMARY KEY,
    name TEXT,
    comment TEXT,
    uuid TEXT,
    status BOOLEAN DEFAULT TRUE
);"

sudo -u postgres psql -d v2ray_db -c "ALTER TABLE clients OWNER TO v2ray_user;" || true
sudo -u postgres psql -d v2ray_db -c "ALTER SEQUENCE clients_id_seq OWNER TO v2ray_user;" || true

# ============================================
# 7. Развёртывание API в /opt/v2api
# ============================================
echo "=== Разворачиваю API в $APP_DIR ==="

cd "$APP_DIR"

# venv
if [ ! -d venv ]; then
  sudo -u v2api python3 -m venv venv
fi

# установка зависимостей
source venv/bin/activate
pip install --upgrade pip
pip install flask flask-cors psycopg2-binary gunicorn
deactivate

# ============================================
# 8. Пишем app.py (VMess + единый clients.json через configDir)
# ============================================
cat > "$APP_DIR/app.py" <<EOF
import json
import uuid
import os
from flask import Flask, jsonify, request, Response
from flask_cors import CORS
import psycopg2

app = Flask(__name__)
CORS(app, supports_credentials=True)

# -------------------------------------------------------
# Константы и конфиг
# -------------------------------------------------------
API_TOKEN = "${API_TOKEN}"

DB_CONFIG = {
    "dbname": "v2ray_db",
    "user": "v2ray_user",
    "password": API_TOKEN,
    "host": "localhost",
}

# Лимит тела запроса (например 1 МБ), чтобы не убить воркеры огромным JSON
app.config["MAX_CONTENT_LENGTH"] = 1 * 1024 * 1024  # 1 MB

# Путь к доп. конфигу V2Ray с клиентами (configDir)
V2RAY_CLIENTS_FILE = "/usr/local/etc/v2ray/conf/clients.json"

# Флаг-файл, который будет отслеживать systemd timer/service
V2RAY_RELOAD_FLAG = "/run/v2ray_reload.flag"

# Сколько байт логов читаем с конца файла
LOG_TAIL_BYTES = 50 * 1024  # 50 KB


# -------------------------------------------------------
# Вспомогательные функции
# -------------------------------------------------------
def check_auth(req):
    token = req.headers.get("Authorization", "").replace("Bearer ", "")
    return token == API_TOKEN


def get_db_connection():
    return psycopg2.connect(**DB_CONFIG)


def mark_v2ray_reload_needed():
    """
    Ставит флаг, что требуется перезапуск/перечтение V2Ray.
    Этим флагом занимается отдельный systemd-сервис/таймер.
    """
    try:
        os.makedirs(os.path.dirname(V2RAY_RELOAD_FLAG), exist_ok=True)
        with open(V2RAY_RELOAD_FLAG, "w") as f:
            f.write("reload_requested\\n")
    except Exception as e:
        print(f"Failed to set V2Ray reload flag: {e}")


def tail_file(path: str, max_bytes: int) -> str:
    """
    Возвращает последние max_bytes байт файла в виде строки.
    Если файл меньше, читается целиком.
    """
    with open(path, "rb") as f:
        f.seek(0, os.SEEK_END)
        size = f.tell()
        offset = max(size - max_bytes, 0)
        f.seek(offset)
        data = f.read()
    return data.decode(errors="ignore")


# -------------------------------------------------------
# CORS / заголовки
# -------------------------------------------------------
@app.after_request
def add_cors_headers(response):
    response.headers["Access-Control-Allow-Origin"] = "*"
    response.headers["Access-Control-Allow-Headers"] = "Authorization, Content-Type"
    response.headers["Access-Control-Allow-Methods"] = "GET, POST, PUT, DELETE, OPTIONS"
    return response


@app.route("/api/<path:path>", methods=["OPTIONS"])
def api_options(path):
    resp = jsonify({"status": "ok"})
    resp.headers["Access-Control-Allow-Origin"] = "*"
    resp.headers["Access-Control-Allow-Headers"] = "Authorization, Content-Type"
    resp.headers["Access-Control-Allow-Methods"] = "GET, POST, PUT, DELETE, OPTIONS"
    return resp, 200


# -------------------------------------------------------
# Обновление V2Ray (/usr/local/etc/v2ray/conf/clients.json)
# через configDir + merge по tag = "vmess_ws"
# -------------------------------------------------------
def update_v2ray_config():
    """
    Читает активных клиентов из БД, перезаписывает clients.json
    и ставит флаг для последующего перезапуска/перечитывания V2Ray
    через systemd timer/service.
    Формат файла:
    {
      "inbounds": [
        {
          "tag": "vmess_ws",
          "settings": {
            "clients": [...]
          }
        }
      ]
    }
    Основной config.json уже содержит inbound vmess_ws (port, path и т.д.).
    Здесь мы обновляем только список clients.
    """
    with get_db_connection() as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT uuid, name FROM clients WHERE status = TRUE;")
            active = cur.fetchall()

    inbound = {
        "tag": "vmess_ws",
        "settings": {
            "clients": []
        }
    }

    for uid, name in active:
        inbound["settings"]["clients"].append(
            {
                "id": uid,
                "alterId": 0,
                "level": 0,
                "email": name,
            }
        )

    full = {"inbounds": [inbound]}

    try:
        os.makedirs(os.path.dirname(V2RAY_CLIENTS_FILE), exist_ok=True)
        with open(V2RAY_CLIENTS_FILE, "w") as f:
            json.dump(full, f, indent=4)
    except Exception as e:
        print(f"Failed to write V2Ray clients config: {e}")

    mark_v2ray_reload_needed()


# -------------------------------------------------------
# Авторизация
# -------------------------------------------------------
@app.before_request
def secure():
    # preflight OPTIONS пропускаем
    if request.method == "OPTIONS":
        return None

    if request.path.startswith("/api") and not check_auth(request):
        return jsonify({"error": "Unauthorized"}), 401


# -------------------------------------------------------
# API — клиенты
# -------------------------------------------------------
@app.route("/api/clients", methods=["GET"])
def get_clients():
    with get_db_connection() as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT * FROM clients ORDER BY id;")
            rows = cur.fetchall()
    return jsonify(rows)


@app.route("/api/clients", methods=["POST"])
def add_client():
    data = request.json or {}
    name = data.get("name")
    if not name:
        return jsonify({"error": "name is required"}), 400

    status = data.get("status", True)
    uid = str(uuid.uuid4())

    with get_db_connection() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "INSERT INTO clients (name, comment, uuid, status) "
                "VALUES (%s,%s,%s,%s) RETURNING id;",
                (name, "", uid, status),
            )
            cid = cur.fetchone()[0]
        conn.commit()

    update_v2ray_config()
    return jsonify({"id": cid, "uuid": uid, "name": name})


@app.route("/api/clients/<int:cid>", methods=["PUT"])
def update_client(cid):
    data = request.json or {}

    name = data.get("name", None)
    status = data.get("status", None)

    if name is None and status is None:
        return jsonify({"error": "nothing to update"}), 400

    fields = []
    params = []

    if name is not None:
        fields.append("name = %s")
        params.append(name)

    if status is not None:
        fields.append("status = %s")
        params.append(status)

    params.append(cid)

    sql = "UPDATE clients SET " + ", ".join(fields) + " WHERE id = %s RETURNING uuid;"

    with get_db_connection() as conn:
        with conn.cursor() as cur:
            cur.execute(sql, tuple(params))
            row = cur.fetchone()
        conn.commit()

    if not row:
        return jsonify({"error": "Not found"}), 404

    update_v2ray_config()
    return jsonify({"id": cid, "name": name, "status": status})


@app.route("/api/clients/<int:cid>", methods=["DELETE"])
def delete_client(cid):
    with get_db_connection() as conn:
        with conn.cursor() as cur:
            cur.execute("DELETE FROM clients WHERE id=%s RETURNING uuid;", (cid,))
            row = cur.fetchone()
        conn.commit()

    if not row:
        return jsonify({"error": "Not found"}), 404

    update_v2ray_config()
    return "", 204


# -------------------------------------------------------
# API — логи V2Ray /var/log/v2ray/access.log
# -------------------------------------------------------
@app.route("/api/logs", methods=["GET"])
def get_logs():
    log_path = "/var/log/v2ray/access.log"
    try:
        data = tail_file(log_path, LOG_TAIL_BYTES)
        return Response(data, mimetype="text/plain")
    except FileNotFoundError:
        return jsonify({"error": f"log file not found: {log_path}"}), 404
    except Exception as e:
        return jsonify({"error": str(e)}), 500


# -------------------------------------------------------
# Запуск в debug (локально)
# -------------------------------------------------------
if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8081)
EOF

chown v2api:v2api "$APP_DIR/app.py"
chmod 755 "$APP_DIR/app.py"

# ============================================
# 9. Пишем /opt/v2api/add_vmess_user.sh
# ============================================
cat > "$APP_DIR/add_vmess_user.sh" <<'EOF'
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

# ===== VMess JSON для клиентов (AEAD, alterId=0) =====
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
echo "QR JSON (для v2rayNG / Nekobox / Qv2ray):"
echo "$VMESS_JSON"
echo "========================================"
EOF

chown v2api:v2api "$APP_DIR/add_vmess_user.sh"
chmod 755 "$APP_DIR/add_vmess_user.sh"

# ============================================
# 10. Настройка V2Ray (основной config.json + configDir)
# ============================================
echo "=== Настраиваю V2Ray (FHS) ==="

# Основной конфиг V2Ray — единый, без clients внутри, но с configDir
cat > "$V2RAY_ETC/config.json" <<'EOF'
{
  "log": {
    "access": "/var/log/v2ray/access.log",
    "error": "/var/log/v2ray/error.log",
    "loglevel": "warning"
  },

  "api": {
    "tag": "api",
    "services": [
      "HandlerService",
      "LoggerService",
      "StatsService"
    ]
  },

  "stats": {},
  "dns": {},

  "policy": {
    "levels": {
      "0": {
        "handshake": 6,
        "connIdle": 240,
        "uplinkOnly": 1,
        "downlinkOnly": 4,
        "statsUserUplink": true,
        "statsUserDownlink": true
      }
    },
    "system": {
      "statsInboundUplink": true,
      "statsInboundDownlink": true,
      "statsOutboundUplink": true,
      "statsOutboundDownlink": true
    }
  },

  "routing": {
    "domainStrategy": "AsIs",
    "rules": [
      {
        "type": "field",
        "inboundTag": ["api"],
        "outboundTag": "api"
      }
    ]
  },

  "inbounds": [
    {
      "tag": "vmess_ws",
      "listen": "127.0.0.1",
      "port": 10085,
      "protocol": "vmess",
      "settings": {
        "clients": []
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
          "path": "/vmess"
        }
      }
    },
    {
      "tag": "api",
      "listen": "127.0.0.1",
      "port": 52018,
      "protocol": "dokodemo-door",
      "settings": {
        "address": "127.0.0.1"
      }
    }
  ],

  "outbounds": [
    {
      "tag": "direct",
      "protocol": "freedom"
    },
    {
      "tag": "block",
      "protocol": "blackhole"
    }
  ],

  "configDir": "/usr/local/etc/v2ray/conf"
}
EOF

# Начальный clients.json — пустой список VMess-клиентов, только tag + settings
cat > "$V2RAY_CONF_DIR/clients.json" <<'EOF'
{
  "inbounds": [
    {
      "tag": "vmess_ws",
      "settings": {
        "clients": []
      }
    }
  ]
}
EOF

chown v2api:v2api "$V2RAY_CONF_DIR/clients.json"
chmod 644 "$V2RAY_CONF_DIR/clients.json"

systemctl enable --now v2ray

# ============================================
# 11. systemd сервисы: myapi + v2ray-reload
# ============================================
echo "=== Настраиваю systemd сервисы ==="

cat > /etc/systemd/system/myapi.service <<EOF
[Unit]
Description=Flask API for v2ray clients
After=network.target postgresql.service v2ray.service

[Service]
Type=simple
User=v2api
Group=v2api
WorkingDirectory=$APP_DIR

ExecStart=$APP_DIR/venv/bin/gunicorn \\
    --workers 4 \\
    --threads 2 \\
    --bind 127.0.0.1:8081 \\
    --timeout 90 \\
    --limit-request-line 4096 \\
    --limit-request-field_size 8192 \\
    --log-level info \\
    app:app

Restart=always
Environment="PATH=$APP_DIR/venv/bin"

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/v2ray-reload.service <<'EOF'
[Unit]
Description=Reload V2Ray configuration if reload flag exists
After=network.target v2ray.service

[Service]
Type=oneshot
ExecStart=/bin/bash -c '\
    if [ -f /run/v2ray_reload.flag ]; then \
         echo "[v2ray-reload] Flag found, restarting v2ray"; \
         systemctl restart v2ray; \
         rm -f /run/v2ray_reload.flag; \
     else \
         echo "[v2ray-reload] No flag, nothing to do"; \
     fi'
EOF

cat > /etc/systemd/system/v2ray-reload.timer <<'EOF'
[Unit]
Description=Check V2Ray reload flag periodically

[Timer]
OnBootSec=5s
OnUnitActiveSec=10s
Unit=v2ray-reload.service

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable --now myapi.service
systemctl enable --now v2ray-reload.timer

# ============================================
# 12. Nginx: HTTP-конфиг, затем SSL через certbot
# ============================================
echo "=== Настраиваю Nginx и SSL (Certbot) ==="

NGINX_CONF="/etc/nginx/sites-available/vmess.conf"

cat > "$NGINX_CONF" <<EOF
limit_req_zone \$binary_remote_addr zone=api_limit:10m rate=20r/s;

server {
    listen 80;
    server_name $DOMAIN;

    # API
    location /api/ {
        limit_req zone=api_limit burst=40 nodelay;

        proxy_pass http://127.0.0.1:8081;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    # VMess WebSocket
    location /vmess {
        proxy_pass http://127.0.0.1:10085;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
    }

    # редирект всего остального на HTTPS
    location / {
        return 301 https://\$host\$request_uri;
    }
}
EOF

ln -sf "$NGINX_CONF" /etc/nginx/sites-enabled/vmess.conf
rm -f /etc/nginx/sites-enabled/default || true

nginx -t
systemctl reload nginx

# SSL
certbot --nginx --non-interactive --agree-tos --register-unsafely-without-email -d "$DOMAIN" || true

nginx -t
systemctl reload nginx

# ============================================
# 13. UFW (фаервол)
# ============================================
echo "=== Настраиваю UFW (фаервол) ==="

ufw allow 22/tcp || true
ufw allow 80/tcp || true
ufw allow 443/tcp || true
# 10085 слушает только 127.0.0.1 — в ufw не нужен, но на всякий случай:
# ufw allow 10085/tcp || true
ufw --force enable || true

# ============================================
# 14. Финальная информация
# ============================================
echo
echo "============================================"
echo "Установка завершена."
echo
echo "Домен:          $DOMAIN"
echo "API endpoint:   https://$DOMAIN/api/clients"
echo "API токен:      $API_TOKEN"
echo
echo "Проверка API:"
echo "  curl -H \"Authorization: Bearer $API_TOKEN\" https://$DOMAIN/api/clients"
echo
echo "VMess WS+TLS:"
echo "  wss://$DOMAIN/vmess"
echo "  порт: 443 (через HTTPS)"
echo "  внутренний порт V2Ray: 10085 (127.0.0.1)"
echo
echo "Добавление пользователя и vmess:// ссылки:"
echo "  /opt/v2api/add_vmess_user.sh myuser"
echo
echo "Логи сервисов:"
echo "  journalctl -u myapi -n 50"
echo "  journalctl -u v2ray -n 50"
echo "  journalctl -u v2ray-reload.service -n 50"
echo "============================================"
