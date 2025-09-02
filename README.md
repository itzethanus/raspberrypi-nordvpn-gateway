# Raspberry Pi: Pi‑hole + NordVPN Gateway (selektiv ruting)

> 🇳🇴 Norsk · 🇬🇧 [English version](README.en.md)

Dette prosjektet gjør Raspberry Pi til **DNS‑filter (Pi‑hole)** og **NordVPN‑gateway** med *selektiv ruting*: kun valgte klienter/porter går via VPN, resten går vanlig vei. Løsningen er herdet med iptables og starter robust via systemd.

## ✨ Egenskaper
- Pi‑hole som **primær DNS** i hjemmenettet (ingen DNS‑lekkasje – `nordvpn set dns off`).
- Selektiv ruting (f.eks. **TCP :8080** for noen få klienter) via **NordLynx** (WireGuard).
- Robust boot‑rekkefølge (venter på nett + Pi‑hole), egen **routing‑tabell** og auto‑reconnect.
- (Valgfritt) **MQTT/HA**‑status og CPU‑temperatur.
- Egnet som mal — alt er delt i `scripts/`, `systemd/`, `docs/`.

## 📦 Krav
- Raspberry Pi 3/4/5 med kablet nett (anbefalt) og Raspberry Pi OS (Bookworm+).
- NordVPN‑konto og Pi‑hole installert.
- `iptables-persistent` for å lagre regler.

## 🚀 Quick start
> **OBS!** Ikke sjekk inn hemmeligheter. Bruk miljøfil (`/etc/nordvpn-gateway.env`).

1. **Installer Pi‑hole** (eth0 som interface, velg upstream DNS).
2. **Installer avhengigheter**
   ```bash
   sudo apt update && sudo apt install -y iptables-persistent
   echo "200 nordvpntabell" | sudo tee -a /etc/iproute2/rt_tables
   sudo sysctl -w net.ipv4.ip_forward=1
   ```
3. **Kopier filer**
   ```bash
   sudo cp scripts/nordvpn-gateway.sh /usr/local/bin/
   sudo chmod +x /usr/local/bin/nordvpn-gateway.sh
   sudo cp scripts/iptables-setup.sh /usr/local/bin/
   sudo chmod +x /usr/local/bin/iptables-setup.sh
   sudo cp scripts/verify_traffic.sh /usr/local/bin/
   sudo chmod +x /usr/local/bin/verify_traffic.sh
   sudo cp systemd/nordvpn-gateway.service /etc/systemd/system/
   ```
4. **Miljøfil (hemmeligheter)**
   ```bash
   sudo cp examples/nordvpn-gateway.env.example /etc/nordvpn-gateway.env
   sudo nano /etc/nordvpn-gateway.env   # fyll inn verdier
   ```
5. **Sett brannmurregler**
   ```bash
   sudo /usr/local/bin/iptables-setup.sh
   ```
6. **Konfigurer NordVPN‑klient**
   ```bash
   nordvpn login
   nordvpn set killswitch disabled
   nordvpn set dns off
   nordvpn set autoconnect disabled
   nordvpn set firewall disabled
   nordvpn set routing disabled
   nordvpn set technology NordLynx
   ```
7. **Aktiver tjenesten**
   ```bash
   sudo systemctl daemon-reload
   sudo systemctl enable --now nordvpn-gateway.service
   sudo systemctl status nordvpn-gateway.service
   tail -f /var/log/nordvpn-gateway.log
   ```

## 🧪 Verifisering
```bash
# Sjekk at port 8080-regelen treffes og at trafikk går ut via 'nordlynx'
sudo /usr/local/bin/verify_traffic.sh
```

## 🔗 Pi‑hole sin rolle (kort)
- Pi‑hole er **DNS** for hele nettverket. Åpne bare **53/UDP+TCP** og **80/TCP** til Pi‑en i INPUT‑reglene.
- Systemd‑enheten venter på `pihole-FTL.service` før gateway‑scriptet starter.
- Mer detaljer i `docs/PIHOLE.no.md`.

## ⚠️ Sikkerhet
- Ikke eksponer Pi‑hole‑web på WAN.
- Bruk **/etc/nordvpn-gateway.env** for MQTT‑bruker/pass og andre hemmeligheter.
- Vurder logrotate for `/var/log/nordvpn-gateway.log` hvis loggen blir stor.

## 🛠️ Feilsøking
- `nordvpn status` — er VPN oppe?
- `ip rule show` + `ip route show table nordvpntabell` — treffer merkingen riktig tabell?
- `sudo iptables -t mangle -L PREROUTING -v -n` — øker tellerne for `tcp dpt:8080`?
- `sudo tcpdump -i nordlynx -n 'tcp and port 8080'` — ser du pakker?

## 📝 Lisens
MIT — se `LICENSE`.
