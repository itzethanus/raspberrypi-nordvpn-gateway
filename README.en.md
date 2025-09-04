# Raspberry Pi: Pi-hole + NordVPN Gateway

English · [🇳🇴 Norsk](README.md)

This project sets up a Raspberry Pi as a combined DNS filtering server (Pi-hole) and NordVPN gateway with selective routing based on IP and/or ports. It includes robust startup and monitoring via MQTT and systemd.

---

## 🧭 Goals

* Raspberry Pi with a static IP address.
* Pi-hole for local DNS blocking across the network.
* NordVPN connection for traffic from selected devices and/or ports.
* Automatic recovery of VPN connection in case of router/network failure.
* (Optional) Integration with Home Assistant via MQTT for monitoring.

---

## 📦 Requirements

* Raspberry Pi 3, 4, or 5 (wired network strongly recommended).
* Raspberry Pi OS Lite (64-bit), Bookworm or newer.
* NordVPN account.
* MQTT broker (optional, only for Home Assistant integration).

---

## 🔧 Step-by-step setup

### 0. System setup

1. Install Raspberry Pi OS Lite (64-bit).
2. Connect via SSH.
3. Update system:

   ```bash
   sudo apt update && sudo apt full-upgrade -y
   sudo reboot
   ```
4. Set a static IP address (adjust to your network):

   ```bash
   sudo nmcli con mod "Wired connection 1" ipv4.method manual
   sudo nmcli con mod "Wired connection 1" ipv4.addresses 192.168.1.102/24
   sudo nmcli con mod "Wired connection 1" ipv4.gateway 192.168.1.1
   sudo nmcli con mod "Wired connection 1" ipv4.dns "1.1.1.1,8.8.8.8"
   sudo nmcli con up "Wired connection 1"
   sudo reboot
   ```

   > On older systems without NetworkManager, use `dhcpcd.conf` or `systemd-networkd`.

---

### 1. Install Pi-hole

```bash
curl -sSL https://install.pi-hole.net | bash
```

---

### 2. Install iptables-persistent and enable IP forwarding

```bash
sudo apt install iptables-persistent -y
```

Edit `/etc/sysctl.conf` and ensure:

```ini
net.ipv4.ip_forward=1
```

Activate:

```bash
sudo sysctl -p
```

---

### 3. Install and configure NordVPN

Install NordVPN client:

```bash
sh <(curl -sSf https://downloads.nordcdn.com/apps/linux/install.sh)
```

Grant user access and reboot:

```bash
sudo usermod -aG nordvpn $USER
sudo reboot
```

After reboot, log in and configure:

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

### 4. Create dedicated routing table

```bash
grep -qE '^\s*200\s+nordvpntable\b' /etc/iproute2/rt_tables || \
  echo "200 nordvpntable" | sudo tee -a /etc/iproute2/rt_tables
```

---

### 5. Configure firewall and selective routing (iptables)

```bash
# STEP 1: Flush existing rules
sudo iptables -F && sudo iptables -t nat -F && sudo iptables -t mangle -F
sudo iptables -X && sudo iptables -t nat -X && sudo iptables -t mangle -X

# STEP 2: Default policies
sudo iptables -P INPUT DROP
sudo iptables -P FORWARD DROP
sudo iptables -P OUTPUT ACCEPT

# STEP 3: INPUT rules
sudo iptables -A INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
sudo iptables -A INPUT -i lo -j ACCEPT
sudo iptables -A INPUT -p icmp -j ACCEPT
sudo iptables -A INPUT -s 192.168.1.0/24 -p tcp --dport 22 -j ACCEPT   # SSH
sudo iptables -A INPUT -s 192.168.1.0/24 -p udp --dport 53 -j ACCEPT   # DNS
sudo iptables -A INPUT -s 192.168.1.0/24 -p tcp --dport 53 -j ACCEPT   # DNS
sudo iptables -A INPUT -s 192.168.1.0/24 -p tcp --dport 80 -j ACCEPT   # Pi-hole Web

# STEP 4: MANGLE – mark traffic
# ADAPT: Change IP addresses and port/protocol as needed
CLIENT_IPS_TO_VPN="192.168.1.128 192.168.1.129 192.168.1.130"
for ip in $CLIENT_IPS_TO_VPN; do
    echo "Adding MARK rule for $ip (TCP port 8080)"
    sudo iptables -t mangle -A PREROUTING -s "$ip" -p tcp --dport 8080 -j MARK --set-mark 1
done

# Example: UDP instead of TCP
# sudo iptables -t mangle -A PREROUTING -s 192.168.1.150 -p udp --dport 51820 -j MARK --set-mark 1

# STEP 5: FORWARD rules
sudo iptables -A FORWARD -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
sudo iptables -A FORWARD -i eth0 -o nordlynx -m mark --mark 1 -j ACCEPT
sudo iptables -A FORWARD -i eth0 -o eth0 -j ACCEPT

# STEP 6: NAT rules
sudo iptables -t nat -A POSTROUTING -o nordlynx -j MASQUERADE
# Optional: only if Pi should NAT further via eth0
# sudo iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE

# STEP 7: Save
sudo netfilter-persistent save
```

---

### 6. Download and customize main script

```bash
sudo wget -O /usr/local/bin/nordvpn-gateway.sh https://raw.githubusercontent.com/Howard0000/raspberrypi-nordvpn-gateway/main/nordvpn-gateway.sh
sudo chmod +x /usr/local/bin/nordvpn-gateway.sh
sudo nano /usr/local/bin/nordvpn-gateway.sh
```

---

### 7. Create systemd service

```bash
sudo nano /etc/systemd/system/nordvpn-gateway.service
```

Paste in the following content:

```ini
[Unit]
Description=NordVPN Gateway Service
After=network-online.target nordvpnd.service
Wants=network-online.target

[Service]
Type=simple
User=root
Environment=LANG=C LC_ALL=C
ExecStart=/usr/local/bin/nordvpn-gateway.sh
Restart=always
RestartSec=15
# (Optional hardening – test in your environment first)
# CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_RAW
# AmbientCapabilities=CAP_NET_ADMIN CAP_NET_RAW
# NoNewPrivileges=yes
# ProtectSystem=full
# ProtectHome=true
# PrivateTmp=true

[Install]
WantedBy=multi-user.target
```

Enable the service:

```bash
sudo systemctl daemon-reload
sudo systemctl enable nordvpn-gateway.service
sudo systemctl start nordvpn-gateway.service
```

---

### 8. Configure your router

* Set **Default Gateway** to the Raspberry Pi (e.g. `192.168.1.102`).
* Set **DNS Server** to the same address.
* Restart clients.

---

### 9. Testing and verification

```bash
sudo systemctl status nordvpn-gateway.service
journalctl -u nordvpn-gateway -f
ip rule show
ip route show table nordvpntable
```

Install tcpdump:

```bash
sudo apt install tcpdump
```

Run verification script:

```bash
wget https://raw.githubusercontent.com/Howard0000/raspberrypi-nordvpn-gateway/main/verify_traffic.sh
chmod +x verify_traffic.sh
sudo ./verify_traffic.sh
```

Adapt variables at the top of the script:

```bash
PORT=8080
IFACE="nordlynx"
PROTO="tcp"
```

---

## 💾 Backup and Maintenance

* Backup `/etc/iptables/rules.v4`, `nordvpn-gateway.sh`, and the systemd unit file.
* Set up logrotate if you use file logging.

---

## 📡 MQTT and Home Assistant

MQTT is **disabled** by default (`MQTT_ENABLED=false`).
Set to `true` and fill in broker/user/password in `nordvpn-gateway.sh` to enable.

The script supports Home Assistant discovery for status, last\_seen, and CPU temperature.

---

## 🙌 Acknowledgements

The project is written and maintained by @Howard0000. An AI assistant has helped simplify explanations, clean up the README, and polish the scripts. All suggestions were manually reviewed before inclusion, and all configuration and testing was done by me.

---

## 📝 License

MIT — see LICENSE.
