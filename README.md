Raspberry Pi: Pi-hole + NordVPN Gateway

🇳🇴 Norsk
 · 🇬🇧 English

Dette prosjektet setter opp en Raspberry Pi som en kombinert DNS-filtreringsserver (Pi-hole) og NordVPN-gateway med selektiv ruting basert på IP og/eller porter. Det inkluderer robust oppstart og overvåkning via MQTT og systemd.

🧭 Mål

Raspberry Pi med statisk IP-adresse.

Pi-hole for lokal DNS-blokkering på hele nettverket.

NordVPN-tilkobling for trafikk fra utvalgte enheter og/eller porter.

Automatisk gjenoppretting av VPN-tilkobling ved ruter-/nettverksfeil.

(Valgfritt) Integrasjon med Home Assistant via MQTT for overvåkning.

📦 Krav

Raspberry Pi 3, 4 eller 5 (kablet nettverk er sterkt anbefalt).

Raspberry Pi OS Lite (64-bit), Bookworm eller nyere.

NordVPN-konto.

MQTT-broker (valgfritt, kun for Home Assistant-integrasjon).

🔧 Steg-for-steg-oppsett
0. Systemoppsett

Installer Raspberry Pi OS Lite (64-bit).

Koble til via SSH.

Oppdater systemet:

sudo apt update && sudo apt full-upgrade -y
sudo reboot


Sett statisk IP-adresse:
På nyere versjoner av Raspberry Pi OS (Bookworm og nyere) brukes NetworkManager. Følgende kommandoer setter statisk IP. Tilpass IP-adresser til ditt eget nettverk.

sudo nmcli con mod "Wired connection 1" ipv4.method manual
sudo nmcli con mod "Wired connection 1" ipv4.addresses 192.168.1.102/24
sudo nmcli con mod "Wired connection 1" ipv4.gateway 192.168.1.1
sudo nmcli con mod "Wired connection 1" ipv4.dns "1.1.1.1,8.8.8.8"
sudo nmcli con up "Wired connection 1"


Etter endringene, ta en omstart for å være sikker på at alt er i orden:

sudo reboot


ℹ️ På eldre images uten NetworkManager kan du bruke dhcpcd.conf eller systemd-networkd i stedet.

1. Installer Pi-hole
curl -sSL https://install.pi-hole.net | bash

2. Installer iptables-persistent og aktiver IP forwarding
sudo apt install iptables-persistent -y


Rediger /etc/sysctl.conf og sørg for at følgende linje er aktiv:

net.ipv4.ip_forward=1


Aktiver:

sudo sysctl -p

3. Installer og konfigurer NordVPN

Installer den offisielle NordVPN-klienten:

sh <(curl -sSf https://downloads.nordcdn.com/apps/linux/install.sh)


Gi din bruker tilgang til NordVPN og start på nytt:

sudo usermod -aG nordvpn $USER
sudo reboot


Etter omstart, logg inn og konfigurer klienten. Deaktiver funksjoner som kan forstyrre manuell ruting:

nordvpn login
nordvpn set killswitch disabled
nordvpn set dns off
nordvpn set autoconnect disabled
nordvpn set firewall disabled
nordvpn set routing disabled
nordvpn set technology NordLynx
nordvpn set analytics disabled

4. Opprett egen routing-tabell for VPN
grep -qE '^\s*200\s+nordvpntabell\b' /etc/iproute2/rt_tables || \
  echo "200 nordvpntabell" | sudo tee -a /etc/iproute2/rt_tables

5. Konfigurer Brannmur og Selektiv Ruting (iptables)
# --- STEG 1: Tøm alt for en ren start ---
sudo iptables -F && sudo iptables -t nat -F && sudo iptables -t mangle -F
sudo iptables -X && sudo iptables -t nat -X && sudo iptables -t mangle -X

# --- STEG 2: Sett en sikker standard policy ---
sudo iptables -P INPUT DROP
sudo iptables -P FORWARD DROP
sudo iptables -P OUTPUT ACCEPT

# --- STEG 3: INPUT-regler ---
sudo iptables -A INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
sudo iptables -A INPUT -i lo -j ACCEPT
sudo iptables -A INPUT -p icmp -j ACCEPT
sudo iptables -A INPUT -s 192.168.1.0/24 -p tcp --dport 22 -j ACCEPT   # SSH
sudo iptables -A INPUT -s 192.168.1.0/24 -p udp --dport 53 -j ACCEPT   # Pi-hole DNS
sudo iptables -A INPUT -s 192.168.1.0/24 -p tcp --dport 53 -j ACCEPT   # Pi-hole DNS
sudo iptables -A INPUT -s 192.168.1.0/24 -p tcp --dport 80 -j ACCEPT   # Pi-hole Web

# --- STEG 4: MANGLE-regler (Marker den spesifikke trafikken for VPN) ---
# TILPASS: Legg til IP-adressene til klientene som skal bruke VPN.
CLIENT_IPS_TO_VPN="192.168.1.128 192.168.1.129 192.168.1.130"
for ip in $CLIENT_IPS_TO_VPN; do
    echo "Legger til MARK-regel for $ip (kun TCP port 8080)"
    # TILPASS: Endre portnummer/protokoll hvis du trenger noe annet enn TCP 8080.
    sudo iptables -t mangle -A PREROUTING -s "$ip" -p tcp --dport 8080 -j MARK --set-mark 1
done

# Eksempel: UDP-port i stedet for TCP
# sudo iptables -t mangle -A PREROUTING -s 192.168.1.150 -p udp --dport 51820 -j MARK --set-mark 1

# --- STEG 5: FORWARD-regler ---
sudo iptables -A FORWARD -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
sudo iptables -A FORWARD -i eth0 -o nordlynx -m mark --mark 1 -j ACCEPT
sudo iptables -A FORWARD -i eth0 -o eth0 -j ACCEPT

# --- STEG 6: NAT-regler ---
sudo iptables -t nat -A POSTROUTING -o nordlynx -j MASQUERADE
# Kun hvis Pi skal NAT-e til et annet subnett via eth0:
# sudo iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE

# --- STEG 7: Lagre ---
sudo netfilter-persistent save

6. Last ned og tilpass hovedskriptet
sudo wget -O /usr/local/bin/nordvpn-gateway.sh https://raw.githubusercontent.com/Howard0000/raspberrypi-nordvpn-gateway/main/nordvpn-gateway.sh
sudo chmod +x /usr/local/bin/nordvpn-gateway.sh
sudo nano /usr/local/bin/nordvpn-gateway.sh

7. Opprett systemd-tjeneste
sudo nano /etc/systemd/system/nordvpn-gateway.service


Lim inn systemd-unit og aktiver med:

sudo systemctl daemon-reload
sudo systemctl enable nordvpn-gateway.service
sudo systemctl start nordvpn-gateway.service

8. Konfigurer ruteren din

Sett Default Gateway til din Raspberry Pi IP (f.eks. 192.168.1.102).

Sett DNS Server til samme IP.
Start klientene på nytt for å hente nye DHCP-innstillinger.

9. Testing og Verifisering

Status: sudo systemctl status nordvpn-gateway.service

Logg: journalctl -u nordvpn-gateway -f

Ruting: ip rule show, ip route show table nordvpntabell

Installer tcpdump (kreves for verify-scriptet):

sudo apt install tcpdump


Last ned og kjør verifiseringsskriptet:

wget https://raw.githubusercontent.com/Howard0000/raspberrypi-nordvpn-gateway/main/verify_traffic.sh
chmod +x verify_traffic.sh
sudo ./verify_traffic.sh


Du kan tilpasse verify_traffic.sh ved å endre tre variabler i toppen:

PORT=8080
IFACE="nordlynx"
PROTO="tcp"

🙌 Anerkjennelser

Prosjektet er skrevet og vedlikeholdt av @Howard0000. En KI-assistent har hjulpet til med å forenkle forklaringer, rydde i README-en og pusse på skript. Alle forslag er manuelt vurdert før de ble tatt inn, og all konfigurasjon og testing er gjort av meg.

📝 Lisens

MIT — se LICENSE.
