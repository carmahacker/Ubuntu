<img width="1536" height="1024" alt="image" src="https://github.com/user-attachments/assets/64890a81-59bc-4f10-bca0-a776f81afdfd" />

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
# Что делает установщик

спрашивает доменное имя
ставит:
V2Ray (последняя версия)
PostgreSQL + база v2ray_db
Flask API (Gunicorn + systemd)
Nginx как reverse-proxy
выпускает SSL-сертификат Let's Encrypt
настраивает:
/api → Flask (127.0.0.1:8081)
/vmess → V2Ray WebSocket (127.0.0.1:10085)
создаёт API token в /opt/v2api/api_token
включает авто-обновление конфига V2Ray при изменении клиентов
