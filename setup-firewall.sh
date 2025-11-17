#!/bin/sh

# 1. Применяем правила (открываем только 22, 80, 443)
iptables -F
iptables -X
iptables -t nat -F
iptables -t mangle -F
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT ACCEPT

iptables -A INPUT -i lo -j ACCEPT
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A INPUT -p tcp --dport 22 -j ACCEPT
iptables -A INPUT -p tcp --dport 80 -j ACCEPT
iptables -A INPUT -p tcp --dport 443 -j ACCEPT
iptables -A INPUT -j DROP

# 2. Сохраняем правила
iptables-save > /etc/iptables.rules

# 3. Создаём скрипт автозагрузки (если ещё нет)
cat > /etc/network/if-pre-up.d/iptables <<EOF
#!/bin/sh
iptables-restore < /etc/iptables.rules
EOF
chmod +x /etc/network/if-pre-up.d/iptables

# 4. Проверка, что всё применилось сейчас
echo "=== Текущие правила после применения ==="
iptables -L -v -n
