<img width="1536" height="1024" alt="image" src="https://github.com/user-attachments/assets/64890a81-59bc-4f10-bca0-a776f81afdfd" />


Минимальный и безопасный сервер Ubuntu/Debian за 5 минут
Оптимизирован для дешёвых VPS, OpenVZ и LXC-контейнеров, где нет UFW, а iptables работает только через venet-интерфейс.

Работает на 99% бюджетных хостингов:
FirstVPS, VDSina, Zomro, PQ.Hosting, Timeweb Cloud, RoboVPS, IQCloud и т.д.

🧩 Что даёт установка
🔐 Безопасный firewall

Открыты только порты:

22 — SSH

80 — HTTP

443 — HTTPS (включая V2Ray WS+TLS)

Всё остальное — DROP.
Правила сохраняются автоматически и поднимаются при каждой перезагрузке.

🛰 V2Ray VMess + WebSocket + TLS

Автоматически устанавливается современный стек:

V2Ray (VMess WS → Nginx → TLS)

PostgreSQL для хранения клиентов

API (Flask + Gunicorn) для управления пользователями

Автоматический reload V2Ray через systemd timer

Защита API (rate-limit + авторизация)

Полностью готовый SSL от Let’s Encrypt

После установки доступна команда:

/opt/v2api/add_vmess_user.sh <username>


Она создаёт пользователя в базе, обновляет конфиг и выдаёт готовую
vmess:// ссылку + JSON для QR.

🚀 Быстрый старт (3 команды)
1️⃣ Установить V2Ray + API + PostgreSQL + Nginx
bash <(curl -fsSL https://raw.githubusercontent.com/carmahacker/Ubuntu/main/setup_v2r.sh)

2️⃣ Настроить минимальный firewall

(Открыты только 22/80/443, всё остальное — DROP)

bash <(curl -fsSL https://raw.githubusercontent.com/carmahacker/Ubuntu/main/setup-firewall.sh)

3️⃣ Добавить пользователя и получить ссылку VMess
/opt/v2api/add_vmess_user.sh myuser


Вы получите:

vmess:// ссылку

JSON для v2rayNG / Nekobox / Qv2ray

Готовое подключение WS+TLS /vmess по порту 443

🧪 API (опционально)

Проверить работу API:

curl -H "Authorization: Bearer <TOKEN>" https://<DOMAIN>/api/clients


Добавить клиента через API:

curl -X POST https://<DOMAIN>/api/clients \
  -H "Authorization: Bearer <TOKEN>" \
  -H "Content-Type: application/json" \
  -d '{"name":"test"}'


Список:

curl -H "Authorization: Bearer <TOKEN>" https://<DOMAIN>/api/clients


Удалить:

curl -X DELETE \
  -H "Authorization: Bearer <TOKEN>" \
  https://<DOMAIN>/api/clients/1

🔧 Полезные команды

Логи API:

journalctl -u myapi -n 50


Логи V2Ray:

journalctl -u v2ray -n 50


Логи автоперезагрузки:

journalctl -u v2ray-reload.service -n 50

📦 Состав проекта

Файлы:

setup_v2r.sh — установка V2Ray, API, PostgreSQL, Nginx

setup-firewall.sh — минимальная настройка firewall

add_vmess_user.sh — добавление клиента + генерация vmess:// ссылки

README.md — документация

🎯 Готово к продакшену

Полностью автономно

Поддерживает OpenVZ / LXC

Не требует systemd-journald логов

Работает с read-only root
