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
