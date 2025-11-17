# carmahacker/Ubuntu

Минимальный и безопасный сервер Ubuntu (Debian-based) для VPS/OpenVZ/LXC за 5 минут  
Идеально для тех, кто покупает дешёвую виртуалку и хочет сразу получить:
- открыты только порты 22, 80, 443
- всё остальное закрыто жёстким DROP
- правила iptables сохраняются после перезагрузки
- ничего лишнего

Подходит для 99 % дешёвых VPS (FirstVPS, VDSina, PQ.Hosting, Zomro, RoboVPS и т.д.), где нет ufw и обычного iptables в контейнере.

## Одноклик установка (рекомендуется)

Подключись по SSH под root и выполни одну команду:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/carmahacker/Ubuntu/main/setup-firewall.sh)


## Что делает скрипт

Очищает все старые правила
Устанавливает политику INPUT DROP
Открывает только:
SSH (22/tcp)
HTTP (80/tcp)
HTTPS (443/tcp)

Разрешает уже установленные соединения и loopback
Сохраняет правила в /etc/iptables.rules
Создаёт автозагрузку через /etc/network/if-pre-up.d/iptables

## Ручная установка (если вдруг не сработает curl)

bashwget https://raw.githubusercontent.com/carmahacker/Ubuntu/main/setup-firewall.sh
chmod +x setup-firewall.sh
./setup-firewall.sh

## Проверка
В любой момент (даже после перезагрузки):

bashiptables -L -v -n

Должна быть политика INPUT DROP и открыты только порты 22, 80, 443.
Как добавить ещё порт (например 8080)
bashiptables -A INPUT -p tcp --dport 8080 -j ACCEPT
iptables-save > /etc/iptables.rules

## Лицензия
MIT — делай что хочешь =)
⭐ Звёздочку поставь, если спасло твой VPS от китайских ботов в 3 часа ночи ;)
textПросто создай репозиторий https://github.com/carmahacker/Ubuntu  
залей туда один файл `setup-firewall.sh` (тот, что я давал выше)  
и этот `README.md` в корень — всё будет работать идеально.
