<img width="1536" height="1024" alt="image" src="https://github.com/user-attachments/assets/64890a81-59bc-4f10-bca0-a776f81afdfd" />

Минимальный и безопасный сервер Ubuntu/Debian за 5 минут

Оптимизирован для дешёвых VPS, OpenVZ и LXC-контейнеров, где нет UFW, а iptables работает только через venet-интерфейс.

Работает на 99% бюджетных хостингов:
FirstVPS, VDSina, Zomro, PQ.Hosting, Timeweb Cloud, RoboVPS, IQCloud и др.

🧩 Что даёт установка
🔐 Безопасный firewall

Открыты только порты:
22 — SSH
80 — HTTP
443 — HTTPS (включая V2Ray WS+TLS)
Всё остальное — DROP.

Правила сохраняются автоматически и поднимаются при каждой перезагрузке.
🛰 V2Ray VMess + WebSocket + TLS

Устанавливается полный стек:
V2Ray (VMess WS → Nginx → TLS)
PostgreSQL для хранения клиентов
API (Flask + Gunicorn) для управления пользователями
Автоперезагрузка V2Ray через systemd timer
Защита API: rate-limit + авторизация

Полностью готовый SSL от Let’s Encrypt
После установки доступна команда:
```bash
/opt/v2api/add_vmess_user.sh <username>
```

Она:
создаёт пользователя в базе
обновляет конфиг
выдаёт vmess:// ссылку + JSON для QR

🚀 Быстрый старт (3 команды)
1️⃣ Установка V2Ray + API + PostgreSQL + Nginx
```bash
bash <(curl -fsSL https://raw.githubusercontent.com/carmahacker/Ubuntu/main/setup_v2r.sh)
```

2️⃣ Минимальный firewall (22/80/443 открыты)
```bash
bash <(curl -fsSL https://raw.githubusercontent.com/carmahacker/Ubuntu/main/setup-firewall.sh)
```

3️⃣ Добавить пользователя и получить VMess
```bash
/opt/v2api/add_vmess_user.sh myuser
```

Вы получите:
vmess:// ссылку
JSON для v2rayNG / Nekobox / Qv2ray
Готовое подключение WS+TLS (/vmess, порт 443)

🧪 API (опционально)
Проверить работу API
```bash
curl -H "Authorization: Bearer <TOKEN>" https://<DOMAIN>/api/clients
```
Добавить клиента
```bash
curl -X POST https://<DOMAIN>/api/clients \
  -H "Authorization: Bearer <TOKEN>" \
  -H "Content-Type: application/json" \
  -d '{"name":"test"}'
```

Получить список клиентов
```bash
curl -H "Authorization: Bearer <TOKEN>" https://<DOMAIN>/api/clients
```

Удалить клиента
```bash
curl -X DELETE \
  -H "Authorization: Bearer <TOKEN>" \
  https://<DOMAIN>/api/clients/1
```

🔧 Полезные команды
Логи API
```bash
journalctl -u myapi -n 50
```

Логи V2Ray
```bash
journalctl -u v2ray -n 50
```

Логи автоперезагрузки
```bash
journalctl -u v2ray-reload.service -n 50
```

📦 Состав проекта

setup_v2r.sh — установка V2Ray, API, PostgreSQL, Nginx
setup-firewall.sh — минимальная настройка firewall
add_vmess_user.sh — добавление клиента + генерация vmess://

README.md — документация
