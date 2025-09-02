#!/bin/bash
set -euo pipefail

# iptables-setup.sh
# Setter opp en herdet brannmur med selektiv ruting (merkede pakker -> VPN).
# Basert på brukerens fungerende regler, pakket som kjørbart skript.

# --- STEG 1: Tøm absolutt alt ---
sudo iptables -F && sudo iptables -t nat -F && sudo iptables -t mangle -F
sudo iptables -X && sudo iptables -t nat -X && sudo iptables -t mangle -X

# --- STEG 2: Sett en sikker standard policy ---
sudo iptables -P INPUT DROP
sudo iptables -P FORWARD DROP
sudo iptables -P OUTPUT ACCEPT

# --- STEG 3: INPUT-regler (Trafikk til selve Pi-en) ---
sudo iptables -A INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
sudo iptables -A INPUT -i lo -j ACCEPT
sudo iptables -A INPUT -p icmp -j ACCEPT
sudo iptables -A INPUT -p tcp --dport 22 -j ACCEPT
sudo iptables -A INPUT -p udp --dport 53 -j ACCEPT
sudo iptables -A INPUT -p tcp --dport 53 -j ACCEPT
sudo iptables -A INPUT -p tcp --dport 80 -j ACCEPT

# --- STEG 4: MANGLE-regler (Marker den spesifikke port-trafikken) ---
CLIENT_IPS_TO_VPN="192.168.1.128 192.168.1.129 192.168.1.130 192.168.1.131"
for ip in $CLIENT_IPS_TO_VPN; do
    sudo iptables -t mangle -A PREROUTING -s "$ip" -p tcp --dport 8080 -j MARK --set-mark 1
done

# --- STEG 5: FORWARD-regler (NY, ENKLERE LOGIKK) ---
sudo iptables -A FORWARD -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
# Regel for VPN-trafikk (kommer først)
sudo iptables -A FORWARD -i eth0 -o nordlynx -m mark --mark 1 -j ACCEPT
# Regel for all annen trafikk fra LAN (kommer sist)
sudo iptables -A FORWARD -i eth0 -o eth0 -j ACCEPT

# --- STEG 6: NAT-regler (Kritisk) ---
sudo iptables -t nat -A POSTROUTING -o nordlynx -j MASQUERADE
sudo iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE

# --- STEG 7: Lagre reglene permanent ---
sudo netfilter-persistent save
# Frivillig reboot for å sikre at alt lastes korrekt fra start
# sudo reboot

echo "iptables-regler lagt og lagret. Husk å verifisere med scripts/verify_traffic.sh"
