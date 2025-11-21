<img width="1009" height="303" alt="image" src="https://github.com/user-attachments/assets/470586de-8a19-4652-a438-5de9744e7420" />


Минимальный и безопасный сервер Ubuntu/Debian за 5 минут

Оптимизирован для дешёвых VPS, OpenVZ и LXC-контейнеров, где нет UFW, а iptables работает только через venet-интерфейс.

Работает на 99% бюджетных хостингов:
FirstVPS, VDSina, Zomro, PQ.Hosting, Timeweb Cloud, RoboVPS, IQCloud и др.

# Установка
```bash
cd /root
apt update -y
apt install -y wget

wget https://github.com/carmahacker/Ubuntu/raw/main/v2api-install-v3.tar.gz -O v2api-install-v3.tar.gz
tar -xzf v2api-install-v3.tar.gz
cd v2api-panel

chmod +x install.sh
./install.sh
```
# Что делает инсталлятор

V2Ray	WebSocket → /vmess, порт 10085, работает через Nginx
Nginx	/api → 127.0.0.1:8081 + /vmess → 127.0.0.1:10085
SSL	Автоматический zCertbot, Let’s Encrypt
PostgreSQL	База: v2ray_db, таблица: clients, пользователь: v2ray_user
Flask API	Gunicorn + systemd на 127.0.0.1:8081
Авто reload V2Ray	Через systemd.path при изменении config.json

# Где найти API-token

После установки:
```bash
cat /opt/v2api/api_token
```
# Быстрые команды проверки API

Сначала считаем токен в переменную:
```bash
TOKEN=$(cat /opt/v2api/api_token)
DOMAIN="your-domain.com"
```

Проверяем:
```bash
# Получить список клиентов
curl -s https://$DOMAIN/api/clients \
  -H "Authorization: Bearer $TOKEN"
```

# Добавить клиента
```bash
curl -s -X POST https://$DOMAIN/api/clients \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name":"test_user"}'
```

Ответ:
{"name":"test_user","uuid":"xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"}

# Отключить клиента
```bash
curl -s -X PUT https://$DOMAIN/api/clients/ID \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"status": false}'
```

# Удалить клиента
```bash
curl -s -X DELETE https://$DOMAIN/api/clients/ID \
  -H "Authorization: Bearer $TOKEN"
```

# Конфигурация VMess

После добавления клиента API автоматически обновляет:
/usr/local/etc/v2ray/config.json

WebSocket endpoint:
wss://YOUR_DOMAIN/vmess

# Путь установки

Файл / каталог	Назначение
/opt/v2api/app.py	Flask API
/opt/v2api/api_token	API-токен
/usr/local/etc/v2ray/config.json	V2Ray config
/etc/systemd/system/myapi.service	Gunicorn API service
/etc/nginx/sites-enabled/v2api.conf	Nginx reverse proxy
