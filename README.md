# Raspberry Pi: Pi-hole + NordVPN Gateway

Norsk · [English](README.en.md)

Dette prosjektet setter opp en Raspberry Pi som en kombinert DNS-filtreringsserver (Pi-hole) og NordVPN-gateway med selektiv ruting basert på IP og/eller porter. Det inkluderer robust oppstart og overvåkning via MQTT og systemd.

---

## Mål

* Raspberry Pi med statisk IP-adresse.
* Pi-hole for lokal DNS-blokkering på hele nettverket.
* NordVPN-tilkobling for trafikk fra utvalgte enheter og/eller porter.
* Automatisk gjenoppretting av VPN-tilkobling ved ruter-/nettverksfeil.
* (Valgfritt) Integrasjon med Home Assistant via MQTT for overvåkning.

---

## Krav

* Raspberry Pi 3, 4 eller 5 (kablet nettverk er sterkt anbefalt).
* Raspberry Pi OS Lite (64-bit), Bookworm eller nyere.
* NordVPN-konto.
* MQTT-broker (valgfritt, kun for Home Assistant-integrasjon).

---

## Steg-for-steg-oppsett

### 0. Systemoppsett

1. Installer Raspberry Pi OS Lite (64-bit).
2. Koble til via SSH.
3. Oppdater systemet:

   ```bash
   sudo apt update && sudo apt full-upgrade -y
   sudo reboot
   ```
4. Sett statisk IP-adresse (tilpass til ditt nettverk):

   ```bash
   sudo nmcli con mod "Wired connection 1" ipv4.method manual
   sudo nmcli con mod "Wired connection 1" ipv4.addresses 192.168.1.102/24
   sudo nmcli con mod "Wired connection 1" ipv4.gateway 192.168.1.1
   sudo nmcli con mod "Wired connection 1" ipv4.dns "1.1.1.1,8.8.8.8"
   sudo nmcli con up "Wired connection 1"
   sudo reboot
   ```

   > På eldre systemer uten NetworkManager kan du bruke `dhcpcd.conf` eller `systemd-networkd`.

---

### 1. Installer Pi-hole

```bash
curl -sSL https://install.pi-hole.net | bash
```

---

### 2. Installer iptables-persistent og aktiver IP forwarding

```bash
sudo apt install iptables-persistent -y
```

Rediger `/etc/sysctl.conf` og sørg for at:

```ini
net.ipv4.ip_forward=1
```

Aktiver:

```bash
sudo sysctl -p
```

---

### 3. Installer og konfigurer NordVPN

Installer NordVPN-klienten:

```bash
sh <(curl -sSf https://downloads.nordcdn.com/apps/linux/install.sh)
```

Gi brukeren tilgang og start på nytt:

```bash
sudo usermod -aG nordvpn $USER
sudo reboot
```

Etter omstart, logg inn og konfigurer:

```bash
nordvpn login
nordvpn set killswitch disabled
nordvpn set dns off
nordvpn set autoconnect disabled
nordvpn set firewall disabled
nordvpn set routing disabled
nordvpn set technology NordLynx
nordvpn set analytics disabled
```

---

### 4. Opprett egen routing-tabell

```bash
grep -qE '^\s*200\s+nordvpntabell\b' /etc/iproute2/rt_tables || \
  echo "200 nordvpntabell" | sudo tee -a /etc/iproute2/rt_tables
```

---

### 5. Konfigurer brannmur og selektiv ruting (iptables)

```bash
# STEG 1: Tøm eksisterende regler
sudo iptables -F && sudo iptables -t nat -F && sudo iptables -t mangle -F
sudo iptables -X && sudo iptables -t nat -X && sudo iptables -t mangle -X

# STEG 2: Standardpolicy
sudo iptables -P INPUT DROP
sudo iptables -P FORWARD DROP
sudo iptables -P OUTPUT ACCEPT

# STEG 3: INPUT-regler
sudo iptables -A INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
sudo iptables -A INPUT -i lo -j ACCEPT
sudo iptables -A INPUT -p icmp -j ACCEPT
sudo iptables -A INPUT -s 192.168.1.0/24 -p tcp --dport 22 -j ACCEPT   # SSH
sudo iptables -A INPUT -s 192.168.1.0/24 -p udp --dport 53 -j ACCEPT   # DNS
sudo iptables -A INPUT -s 192.168.1.0/24 -p tcp --dport 53 -j ACCEPT   # DNS
sudo iptables -A INPUT -s 192.168.1.0/24 -p tcp --dport 80 -j ACCEPT   # Pi-hole Web

# STEG 4: MANGLE – marker trafikk
# TILPASS: Endre IP-adressene og port/protokoll etter behov
CLIENT_IPS_TO_VPN="192.168.1.128 192.168.1.129 192.168.1.130"
for ip in $CLIENT_IPS_TO_VPN; do
    echo "Legger til MARK-regel for $ip (kun TCP port 8080)"
    sudo iptables -t mangle -A PREROUTING -s "$ip" -p tcp --dport 8080 -j MARK --set-mark 1
done

# Eksempel: UDP i stedet for TCP
# sudo iptables -t mangle -A PREROUTING -s 192.168.1.150 -p udp --dport 51820 -j MARK --set-mark 1

# STEG 5: FORWARD-regler
sudo iptables -A FORWARD -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
sudo iptables -A FORWARD -i eth0 -o nordlynx -m mark --mark 1 -j ACCEPT
sudo iptables -A FORWARD -i eth0 -o eth0 -j ACCEPT

# STEG 6: NAT-regler
sudo iptables -t nat -A POSTROUTING -o nordlynx -j MASQUERADE
# Valgfritt: Kun hvis Pi skal NAT-e videre via eth0
# sudo iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE

# STEG 7: Lagre
sudo netfilter-persistent save
```

---

### 6. Last ned og tilpass hovedskriptet

```bash
sudo wget -O /usr/local/bin/nordvpn-gateway.sh https://raw.githubusercontent.com/Howard0000/raspberrypi-nordvpn-gateway/main/nordvpn-gateway.sh
sudo chmod +x /usr/local/bin/nordvpn-gateway.sh
sudo nano /usr/local/bin/nordvpn-gateway.sh
```

---

### 7. Opprett systemd-tjeneste

```bash
sudo nano /etc/systemd/system/nordvpn-gateway.service
```

Lim inn unit, og aktiver:

```bash
sudo systemctl daemon-reload
sudo systemctl enable nordvpn-gateway.service
sudo systemctl start nordvpn-gateway.service
```

---

### 8. Konfigurer ruteren

* Sett **Default Gateway** til Raspberry Pi (eks. `192.168.1.102`).
* Sett **DNS-server** til samme adresse.
* Start klientene på nytt.

---

### 9. Testing og verifisering

```bash
sudo systemctl status nordvpn-gateway.service
journalctl -u nordvpn-gateway -f
ip rule show
ip route show table nordvpntabell
```

Installer tcpdump:

```bash
sudo apt install tcpdump
```

Kjør verifiseringsskript:

```bash
wget https://raw.githubusercontent.com/Howard0000/raspberrypi-nordvpn-gateway/main/verify_traffic.sh
chmod +x verify_traffic.sh
sudo ./verify_traffic.sh
```

Tilpass i toppen av skriptet:

```bash
PORT=8080
IFACE="nordlynx"
PROTO="tcp"
```

---

## Anerkjennelser

Prosjektet er skrevet og vedlikeholdt av @Howard0000. En KI-assistent har hjulpet til med å forenkle forklaringer, rydde i README-en og pusse på skript. Alle forslag er manuelt vurdert før de ble tatt inn, og all konfigurasjon og testing er gjort av meg.

---

## Lisens

MIT — se LICENSE.

