# Raspberry Pi: Pi-hole + NordVPN Gateway (v2.0)

> 🇳🇴 [Norsk](README.md) · 🇬🇧 English version

This project sets up a Raspberry Pi as a combined DNS filtering server (Pi-hole) and an advanced NordVPN gateway. The solution uses the official NordVPN client with the NordLynx protocol and features **selective routing**, allowing you to send traffic from only selected devices and/or ports through the VPN tunnel.

The project includes robust startup, self-healing logic, and monitoring via `systemd` and MQTT.

---

## ✨ Key Features

*   **Selective Routing:** Choose exactly which devices (by IP) and ports should use the VPN. All other traffic goes through your regular internet connection for maximum speed.
*   **Official NordVPN Client:** Uses the fast and secure **NordLynx** protocol (WireGuard) for optimal performance.
*   **Pi-hole Integration:** All DNS traffic is handled by Pi-hole for network-wide ad and tracker blocking.
*   **Robust and Self-Healing:** A `systemd` service ensures automatic startup and restart on failure. The script actively verifies that the VPN connection is working and restores it if necessary.
*   **Secure Startup:** The service waits for the network and router to be available before starting, to avoid error states after a reboot.
*   **(Optional) Home Assistant Integration:** Send real-time data about VPN status, connected server, and CPU temperature to your MQTT broker for full monitoring.
*   **Easy Troubleshooting:** Includes a verification script to see live that the selective routing is working as expected.

---

## 📦 Requirements

*   Raspberry Pi 3, 4, or 5 (wired network is strongly recommended).
*   Raspberry Pi OS Lite (64-bit), Bookworm or newer.
*   An active NordVPN account.
*   (Optional) An MQTT broker for Home Assistant integration.

---

## 🔧 Step-by-Step Setup

### 0. System Setup

1.  Install Raspberry Pi OS Lite (64-bit).
2.  Connect via SSH.
3.  Update the system:
    
    sudo apt update && sudo apt full-upgrade -y
    sudo reboot
    
4.  **Set a static IP address:**
    On newer versions of Raspberry Pi OS, NetworkManager is used. **Adapt the IP addresses to your own network.**

    # Replace "Wired connection 1" with the name of your connection (check with 'nmcli con show')
    # Replace IP addresses, gateway (your router's IP), and DNS servers
    sudo nmcli con mod "Wired connection 1" ipv4.method manual
    sudo nmcli con mod "Wired connection 1" ipv4.addresses 192.168.1.102/24
    sudo nmcli con mod "Wired connection 1" ipv4.gateway 192.168.1.1
    sudo nmcli con mod "Wired connection 1" ipv4.dns "1.1.1.1,8.8.8.8"
    
    # Apply the changes
    sudo nmcli con up "Wired connection 1"
    sudo reboot

### 1. Install Pi-hole

    curl -sSL https://install.pi-hole.net | bash

Follow the instructions. Choose `eth0` as the interface and select an upstream DNS provider (e.g., Cloudflare). Note down the administrator password.

### 2. Enable IP Forwarding and install `iptables-persistent`

This allows the Pi to forward traffic and ensures that the firewall rules survive a reboot.

    sudo apt install iptables-persistent -y

Enable IP forwarding by editing `/etc/sysctl.conf`:

    sudo nano /etc/sysctl.conf

Find the line `#net.ipv4.ip_forward=1` and remove the `#` in front. Save the file (Ctrl+X, Y, Enter) and apply the change:

    sudo sysctl -p

### 3. Install and Configure NordVPN

Install the official NordVPN client:

    sh <(curl -sSf https://downloads.nordcdn.com/apps/linux/install.sh)

Give your user access to NordVPN and reboot:

    sudo usermod -aG nordvpn $USER
    sudo reboot

After rebooting, log in and configure the client. We disable all features that could interfere with our manual routing:
    
    nordvpn login
    nordvpn set killswitch disabled
    nordvpn set dns off
    nordvpn set autoconnect disabled
    nordvpn set firewall disabled
    nordvpn set routing disabled
    nordvpn set technology NordLynx
    nordvpn set analytics disabled

### 4. Create a custom routing table for the VPN

    echo "200 nordvpntabell" | sudo tee -a /etc/iproute2/rt_tables

### 5. Configure Firewall and Selective Routing

These `iptables` rules set up a secure firewall and implement selective routing.

    # --- STEP 1: Flush everything for a clean start ---
    sudo iptables -F && sudo iptables -t nat -F && sudo iptables -t mangle -F
    sudo iptables -X && sudo iptables -t nat -X && sudo iptables -t mangle -X

    # --- STEP 2: Set a secure default policy ---
    sudo iptables -P INPUT DROP
    sudo iptables -P FORWARD DROP
    sudo iptables -P OUTPUT ACCEPT

    # --- STEP 3: INPUT rules (Necessary exceptions for the Pi itself) ---
    sudo iptables -A INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
    sudo iptables -A INPUT -i lo -j ACCEPT
    sudo iptables -A INPUT -p icmp -j ACCEPT
    sudo iptables -A INPUT -p tcp --dport 22 -j ACCEPT # SSH
    sudo iptables -A INPUT -p udp --dport 53 -j ACCEPT # Pi-hole DNS
    sudo iptables -A INPUT -p tcp --dport 53 -j ACCEPT # Pi-hole DNS
    sudo iptables -A INPUT -p tcp --dport 80 -j ACCEPT # Pi-hole Web

    # --- STEP 4: MANGLE rules (Mark the specific traffic for the VPN) ---
    # CUSTOMIZE: Add the IP addresses of the clients that should use the VPN.
    CLIENT_IPS_TO_VPN="192.168.1.128 192.168.1.129 192.168.1.130"
    for ip in $CLIENT_IPS_TO_VPN; do
        echo "Adding MARK rule for $ip (TCP port 8080 only)"
        # CUSTOMIZE: Change the port number if you need something other than 8080.
        sudo iptables -t mangle -A PREROUTING -s "$ip" -p tcp --dport 8080 -j MARK --set-mark 1
    done

    # --- STEP 5: FORWARD rules (Correct logic for selective routing) ---
    sudo iptables -A FORWARD -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
    # Rule 1: Allow marked traffic to go out the VPN tunnel.
    sudo iptables -A FORWARD -i eth0 -o nordlynx -m mark --mark 1 -j ACCEPT
    # Rule 2: Allow all other traffic from the LAN to go out the regular way.
    sudo iptables -A FORWARD -i eth0 -o eth0 -j ACCEPT

    # --- STEP 6: NAT rules (Critical for both traffic types to work) ---
    sudo iptables -t nat -A POSTROUTING -o nordlynx -j MASQUERADE
    sudo iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE

    # --- STEP 7: Save the rules permanently ---
    sudo netfilter-persistent save
    echo "Firewall rules have been set and saved."

### 6. Create the main script `nordvpn-gateway.sh`

Instead of pasting the script here, users can now download it directly from the repository.

    # Download the script from GitHub (remember to change username/repo if necessary)
    sudo wget -O /usr/local/bin/nordvpn-gateway.sh https://raw.githubusercontent.com/Howard0000/raspberrypi-nordvpn-gateway/main/nordvpn-gateway.sh

    # Make it executable
    sudo chmod +x /usr/local/bin/nordvpn-gateway.sh

    # Open the file to customize your personal variables (especially MQTT)
    sudo nano /usr/local/bin/nordvpn-gateway.sh

### 7. Create the `systemd` service

This ensures that the script starts automatically.

1.  Create the service file:
    
    sudo nano /etc/systemd/system/nordvpn-gateway.service
    
2.  Paste the content below:
    
    [Unit]
    Description=NordVPN Gateway Service
    After=network-online.target pihole-FTL.service
    Wants=network-online.target

    [Service]
    Type=simple
    User=root

    # Waits until it can ping the gateway before starting the main script.
    ExecStartPre=/bin/bash -c 'GATEWAY_IP=$(grep -oP "CORRECT_GATEWAY=\K\S+" /usr/local/bin/nordvpn-gateway.sh | tr -d "\""); echo "Waiting for gateway ($GATEWAY_IP) to respond..."; while ! ping -c 1 -W 2 $GATEWAY_IP &>/dev/null; do sleep 5; done; echo "Gateway is responding, starting main script."'

    ExecStart=/usr/local/bin/nordvpn-gateway.sh

    Restart=always
    RestartSec=30

    StandardOutput=file:/var/log/nordvpn-gateway.log
    StandardError=file:/var/log/nordvpn-gateway.log

    [Install]
    WantedBy=multi-user.target
    
3.  Save and close the file.
4.  Enable and start the service:
    
    sudo systemctl daemon-reload
    sudo systemctl enable nordvpn-gateway.service
    sudo systemctl start nordvpn-gateway.service

### 8. Configure your router

Log in to your router and make the following changes in the DHCP settings for your local network:
*   Set **Default Gateway** to your Raspberry Pi's IP (e.g., `192.168.1.102`).
*   Set **DNS Server** to your Raspberry Pi's IP (e.g., `192.168.1.102`).

Reboot the devices on your network for them to get the new settings.

---

## Acknowledgements
The project is written and maintained by @Howard0000. An AI assistant has helped simplify explanations, clean up the README, and polish the script. All suggestions were manually reviewed before being incorporated, and all configuration and testing were done by me.


## 📝 License
MIT — see `LICENSE`.


## 🔬 Testing and Verification

Use these commands to check that everything is working:

*   **Check service status:** `sudo systemctl status nordvpn-gateway.service`
*   **Watch the log live:** `tail -f /var/log/nordvpn-gateway.log`
*   **Check VPN status:** `nordvpn status`
*   **Check routing rules:** `ip rule show` and `ip route show table nordvpntabell`

### Verification Script

To get final proof that the selective routing is working, download and run `verify_traffic.sh` from this repository.

    wget https://raw.githubusercontent.com/Howard0000/raspberrypi-nordvpn-gateway/main/verify_traffic.sh
    chmod +x verify_traffic.sh
    sudo ./verify_traffic.sh

