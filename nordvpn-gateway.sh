#!/bin/bash
set -Eeuo pipefail
export LANG=C LC_ALL=C

# ==============================================================================
# NordVPN Gateway Script
# ==============================================================================
# - Holder NordVPN (NordLynx) tilkoblet og overvåker status
# - Sikrer at Pi sin egen default-gateway forblir på LAN (ikke “lekker” til VPN)
# - Setter opp og vedlikeholder ruting for selektiv VPN (fwmark 1 -> tabell)
# - (Valgfritt) Publiserer status/telemetri til MQTT og HA discovery
# ==============================================================================

# --- Konfigurasjon (tilpass disse) --------------------------------------------
VPN_CHECK_HOST="1.1.1.1"         # Ping for generell nett
VPN_ROBUST_CHECK="google.com"    # Ping via VPN for robust sjekk
MAX_PING_RETRIES=12              # 12 * 5s = maks ~1 min
RETRY_DELAY=5

CORRECT_GATEWAY="192.168.1.1"    # Din ruters IP
VPN_TABLE="nordvpntabell"        # Må finnes i /etc/iproute2/rt_tables
VPN_IFACE="nordlynx"             # NordVPN sitt WireGuard-interface
LAN_IFACE="eth0"                 # Pi sitt kablede interface

LOG_FILE="/var/log/nordvpn-gateway.log"

# --- NordVPN-innstillinger -----------------------------------------------------
NORDVPN_CONNECT_TARGET="recommended"   # f.eks. "Norway", "recommended"

# --- MQTT / Home Assistant -----------------------------------------------------
MQTT_ENABLED=false               # AV som standard – samsvarer med README
MQTT_BROKER="192.168.1.10"       # broker IP
MQTT_USER=""                     # ev. tom
MQTT_PASS=""                     # ev. tom
MQTT_CLIENT_ID="nordvpn_gateway_pi"
HA_DISCOVERY_PREFIX="homeassistant"

# --- Avhengigheter -------------------------------------------------------------
if ! command -v nordvpn >/dev/null 2>&1; then
  echo "Feil: 'nordvpn' CLI er ikke installert. Se README steg 3." >&2
  exit 1
fi

# --- Hjelpefunksjoner ----------------------------------------------------------
log_msg() {
  # logg til stdout + fil
  echo "$(date +'%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

send_mqtt_status() {
  [[ "$MQTT_ENABLED" == true ]] || return 0
  command -v mosquitto_pub >/dev/null 2>&1 || return 0
  local msg="$1"
  local args=()
  [[ -n "$MQTT_USER" ]] && args+=(-u "$MQTT_USER")
  [[ -n "$MQTT_PASS" ]] && args+=(-P "$MQTT_PASS")
  mosquitto_pub -h "$MQTT_BROKER" -i "$MQTT_CLIENT_ID" "${args[@]}" -r \
    -t "nordvpn/gateway/status" -m "$msg"
  mosquitto_pub -h "$MQTT_BROKER" -i "$MQTT_CLIENT_ID" "${args[@]}" -r \
    -t "nordvpn/gateway/last_seen" -m "$(date +'%Y-%m-%d %H:%M:%S')"
}

send_mqtt_ha_discovery() {
  [[ "$MQTT_ENABLED" == true ]] || return 0
  command -v mosquitto_pub >/dev/null 2>&1 || { log_msg "mosquitto_pub ikke funnet"; return 0; }
  local DEVICE_JSON='{"identifiers":["nordvpn_gateway_pi_device"],"name":"NordVPN Gateway","model":"Raspberry Pi","manufacturer":"Custom Script"}'
  local args=()
  [[ -n "$MQTT_USER" ]] && args+=(-u "$MQTT_USER")
  [[ -n "$MQTT_PASS" ]] && args+=(-P "$MQTT_PASS")

  mosquitto_pub -h "$MQTT_BROKER" -i "$MQTT_CLIENT_ID" "${args[@]}" -r \
    -t "$HA_DISCOVERY_PREFIX/sensor/nordvpn_gateway_pi/status/config" \
    -m "{ \"name\": \"NordVPN Status\", \"state_topic\": \"nordvpn/gateway/status\", \"unique_id\": \"nordvpn_gateway_pi_status\", \"icon\": \"mdi:vpn\", \"device\": $DEVICE_JSON }"

  mosquitto_pub -h "$MQTT_BROKER" -i "$MQTT_CLIENT_ID" "${args[@]}" -r \
    -t "$HA_DISCOVERY_PREFIX/sensor/nordvpn_gateway_pi/last_seen/config" \
    -m "{ \"name\": \"NordVPN Sist Sett\", \"state_topic\": \"nordvpn/gateway/last_seen\", \"unique_id\": \"nordvpn_gateway_pi_last_seen\", \"icon\": \"mdi:clock-outline\", \"device\": $DEVICE_JSON }"
}

send_cpu_temp() {
  [[ "$MQTT_ENABLED" == true ]] || return 0
  command -v mosquitto_pub >/dev/null 2>&1 || return 0
  local f="/sys/class/thermal/thermal_zone0/temp"
  [[ -r "$f" ]] || return 0
  local raw; raw=$(cat "$f" 2>/dev/null) || return 0
  local t_c; t_c=$(awk "BEGIN { printf \"%.1f\", $raw/1000 }")
  local args=()
  [[ -n "$MQTT_USER" ]] && args+=(-u "$MQTT_USER")
  [[ -n "$MQTT_PASS" ]] && args+=(-P "$MQTT_PASS")
  mosquitto_pub -h "$MQTT_BROKER" -i "$MQTT_CLIENT_ID" "${args[@]}" -r \
    -t "nordvpn/gateway/cpu_temp" -m "$t_c"
}

check_internet_robust() {
  # usage: check_internet_robust HOST IFACE
  local host="$1"; local iface="$2"
  ping -I "$iface" -c 1 -W 2 "$host" >/dev/null 2>&1
}

setup_vpn_routing_rules() {
  log_msg "Setter opp rutingregler for tabell $VPN_TABLE ..."
  if ! ip rule show | grep -q "fwmark 0x1 lookup $VPN_TABLE"; then
    ip rule add fwmark 1 table "$VPN_TABLE"
    log_msg "Lagt til ip rule: fwmark 1 -> $VPN_TABLE"
  else
    log_msg "ip rule for fwmark 1 finnes allerede."
  fi
  ip route replace default dev "$VPN_IFACE" table "$VPN_TABLE"
  ip route flush cache
  log_msg "Ruting for $VPN_TABLE satt til dev $VPN_IFACE, cache tømt."
}

ensure_pi_gateway_is_correct() {
  # Sikre at Pi selv bruker ruterens gateway, ikke $VPN_IFACE
  local cur_gw_iface
  cur_gw_iface=$(ip route show default | awk '/default/ {print $5; exit}')
  if [[ "$cur_gw_iface" == "$VPN_IFACE" ]]; then
    log_msg "ADVARSEL: Default går via $VPN_IFACE. Setter LAN-gateway $CORRECT_GATEWAY ..."
    ip route replace default via "$CORRECT_GATEWAY" dev "$LAN_IFACE" || true
  fi
}

disconnect_vpn() {
  log_msg "Kobler fra NordVPN ..."
  nordvpn disconnect >/dev/null 2>&1 || true
  send_mqtt_status "VPN Frakoblet"
}

connect_nordvpn() {
  log_msg "Starter tilkobling mot NordVPN ..."
  send_mqtt_status "Starter VPN tilkobling ..."

  # Krev nett på LAN først
  if ! check_internet_robust "$VPN_CHECK_HOST" "$LAN_IFACE"; then
    log_msg "Ingen nett via $LAN_IFACE ennå – venter ..."
    send_mqtt_status "Venter på nett ($LAN_IFACE)"
    return 1
  fi

  log_msg "nordvpn connect $NORDVPN_CONNECT_TARGET"
  nordvpn connect "$NORDVPN_CONNECT_TARGET" >/dev/null 2>&1 || true

  # Vent til både status=Connected og interface opp
  local tries=0
  while (( tries < 12 )); do
    sleep 5
    if nordvpn status | grep -q '^Status: Connected'; then
      ip link show "$VPN_IFACE" >/dev/null 2>&1 && break
    fi
    ((tries++))
    log_msg "Venter på 'Connected' + $VPN_IFACE ... (forsøk $tries/12)"
  done

  if ! nordvpn status | grep -q '^Status: Connected'; then
    log_msg "Klarte ikke å oppnå 'Connected' fra nordvpn status."
    send_mqtt_status "VPN tilkobling feilet"
    return 1
  fi
  if ! ip link show "$VPN_IFACE" >/dev/null 2>&1; then
    log_msg "$VPN_IFACE kom ikke opp etter tilkobling."
    send_mqtt_status "VPN if ikke oppe"
    return 1
  fi

  log_msg "Tilkoblet. Setter ruting ..."
  setup_vpn_routing_rules
  send_mqtt_status "VPN Tilkoblet"
  return 0
}

# --- Hoved ---------------------------------------------------------------------
trap 'log_msg "Avslutter. Koble fra VPN ..."; disconnect_vpn; exit 0' SIGINT SIGTERM

# Forbered loggfil
touch "$LOG_FILE" && chmod 644 "$LOG_FILE"
log_msg "--- NordVPN Gateway script starter (PID: $$) ---"

send_mqtt_ha_discovery
ensure_pi_gateway_is_correct
connect_nordvpn || true

log_msg "Starter overvåkningsløkke ..."
while true; do
  if ip link show "$VPN_IFACE" >/dev/null 2>&1 && nordvpn status | grep -q '^Status: Connected'; then
    if check_internet_robust "$VPN_ROBUST_CHECK" "$VPN_IFACE"; then
      send_mqtt_status "VPN OK"
    else
      log_msg "VPN-grensesnitt er oppe, men ping via $VPN_IFACE feiler. Reconnect ..."
      send_mqtt_status "VPN test feilet"
      disconnect_vpn
      sleep 5
      connect_nordvpn || true
    fi
  else
    log_msg "VPN ikke tilkoblet, forsøker ny tilkobling ..."
    send_mqtt_status "VPN Frakoblet"
    connect_nordvpn || true
  fi

  send_cpu_temp
  ensure_pi_gateway_is_correct
  sleep 60
done
