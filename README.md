<img width="1009" height="303" alt="image" src="https://github.com/user-attachments/assets/470586de-8a19-4652-a438-5de9744e7420" />

Минимальный и безопасный сервер Ubuntu/Debian за 5 минут

Позволяет динамически управлять V2Ray клиентами (VMess) через API:
создание, включение/выключение, удаление и автоматическое обновление конфига V2Ray.

Весь разворот происходит одной командой.
Подходит для VPS / Bare Metal установок.

📦 Возможности

🟦 V2Ray (VMess + WebSocket + TLS)
🟩 Flask API управления клиентами
🟧 PostgreSQL база для хранения клиентов
🟥 Nginx reverse-proxy + Let's Encrypt SSL
🔁 Авто-перезагрузка V2Ray при изменении config.json
🔑 Автогенерация API Token
👤 Обособленный системный пользователь v2api
🛠 Полностью автономный инсталлятор

🚀 Установка
1. Скачайте архив
wget https://raw.githubusercontent.com/carmahacker/Ubuntu/main/v2api-install-v3.tar.gz -O v2api.tar.gz

2. Распакуйте
tar -xzf v2api.tar.gz
cd v2api-panel

3. Запустите установку
bash install.sh


Установка спросит домен:

Введите доменное имя (например: v2.example.com): vp3.mt-2.ru


После установки будут выданы:

🌐 API URL

🔑 API Token

🔌 V2Ray VMess WebSocket endpoint

📁 Путь к конфигам

🧪 Проверка API через curl
0. Загрузить токен в переменную:
TOKEN=$(cat /opt/v2api/api_token)
echo $TOKEN

1. Получить список клиентов
curl -s https://YOUR_DOMAIN/api/clients \
  -H "Authorization: Bearer $TOKEN"

2. Создать клиента
curl -s -X POST https://YOUR_DOMAIN/api/clients \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name":"alice"}'


Ответ:

{
  "name": "alice",
  "uuid": "dc2b577f-2e5f-40d0-8511-875a1cc2b9b6"
}

3. Отключить клиента
curl -s -X PUT https://YOUR_DOMAIN/api/clients/1 \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"status": false}'

4. Удалить клиента
curl -s -X DELETE https://YOUR_DOMAIN/api/clients/1 \
  -H "Authorization: Bearer $TOKEN"

📂 Структура репозитория
v2api-panel/
├── app.py
├── install.sh
├── requirements.txt
├── sql/
│   └── init.sql
├── nginx/
│   └── v2api.conf.template
├── systemd/
│   ├── myapi.service
│   ├── v2ray-reload.path
│   └── v2ray-reload.service
└── uninstall.sh

📜 Что делает инсталлятор

✔️ Устанавливает Python3 + venv
✔️ Устанавливает PostgreSQL
✔️ Создаёт БД v2ray_db и пользователя v2ray_user
✔️ Устанавливает V2Ray (последний release)
✔️ Разворачивает API в /opt/v2api
✔️ Настраивает systemd услуги
✔️ Устанавливает Nginx + Certbot SSL
✔️ Настраивает WebSocket + TLS + Proxy на API
✔️ Создаёт автоперезапуск V2Ray при изменении конфига

❌ Удаление
cd v2api-panel
bash uninstall.sh


Удаляет:

systemd-службы

Nginx конфиг

PostgreSQL базу

/opt/v2api

Логи и темп-файлы
