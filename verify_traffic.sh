#!/bin/bash
# ==============================================================================
# verify_traffic.sh — Verifiser selektiv ruting via NordVPN (nordlynx)
# ==============================================================================
# Hva den gjør:
#  1) Viser relevante iptables-regler (mangle/FW-mark) for valgt PROTO/PORT
#  2) Viser ip-rule og rutingtabell brukt for MARK 0x1
#  3) Lytter på VPN-grensesnittet med tcpdump for valgt PROTO/PORT i en periode
#
# Hvordan bruke:
#  - Kjør fra Pi-en (som gateway): sudo ./verify_traffic.sh
#  - Generér trafikk fra en klient-IP som er med i MANGLE-reglene (f.eks. gå til
#    http://example.com:8080 eller bruk en app/tjeneste på porten du tester).
#
# TIPS:
#  - Endre variablene under for å teste andre porter/protokoller/grensesnitt.
#  - For UDP (f.eks. WireGuard/WG): sett PROTO=udp og PORT=51820
# ==============================================================================

set -euo pipefail

# --- Konfigurasjon (TILPASS) --------------------------------------------------
PORT=8080          # Porten du har merket i MANGLE for å gå via VPN
IFACE="nordlynx"   # VPN-grensesnittet (NordVPN NordLynx)
PROTO="tcp"        # "tcp" eller "udp"
DURATION=20        # Hvor lenge tcpdump skal lytte (sekunder)

# --- Interne innstillinger -----------------------------------------------------
MARK_HEX="0x1"     # Vi bruker MARK 1 i oppskriftene (endre hvis du bruker en annen)
RT_TABLE_CANDIDATES=("nordvpntabell" "nordvpntable" "vpn_table")  # støtt begge språk/varianter

# --- Funksjoner ----------------------------------------------------------------
need_root() {
  if [[ $EUID -ne 0 ]]; then
    echo "Denne skriptet må kjøres som root. Prøv: sudo $0" >&2
    exit 1
  fi
}

check_deps() {
  local missing=()
  for bin in iptables ip rule ip route tcpdump timeout grep awk sed; do
    command -v "$bin" >/dev/null 2>&1 || missing+=("$bin")
  done
  if (( ${#missing[@]} )); then
    echo "Mangler verktøy: ${missing[*]}" >&2
    echo "Installer f.eks.: sudo apt update && sudo apt install tcpdump -y" >&2
    exit 1
  fi
}

detect_rt_table() {
  for name in "${RT_TABLE_CANDIDATES[@]}"; do
    if grep -Eq "[[:space:]]${name}\$" /etc/iproute2/rt_tables 2>/dev/null; then
      echo "$name"
      return 0
    fi
  done
  # Fallback (kan fortsatt eksistere selv om ikke registrert i rt_tables)
  echo "${RT_TABLE_CANDIDATES[0]}"
}

print_header() {
  echo "=============================================================================="
  echo " Verifisering av selektiv ruting via VPN"
  echo "  - IFACE : $IFACE"
  echo "  - PROTO : $PROTO"
  echo "  - PORT  : $PORT"
  echo "  - LYTT  : ${DURATION}s med tcpdump"
  echo "=============================================================================="
}

show_rules() {
  echo
  echo "[1/3] Søker etter MANGLE-regler som merker ${PROTO^^} trafikk til port $PORT med MARK $MARK_HEX ..."
  iptables -t mangle -S PREROUTING | grep -iE "\-p[[:space:]]+$PROTO" | grep -iE "--dport[[:space:]]+$PORT" | grep -iE "MARK --set-mark[[:space:]]+1|MARK --set-mark[[:space:]]+$MARK_HEX" || {
    echo "⚠️  Fant ingen matchende mangle-regel for $PROTO/$PORT som setter MARK 1." >&2
  }

  echo
  echo "[2/3] Viser ip-rule som sender MARK $MARK_HEX til egen rutetabell ..."
  ip rule show | grep -i "fwmark 0x1" || echo "⚠️  Fant ingen 'ip rule' for fwmark 0x1."

  local rt_table
  rt_table="$(detect_rt_table)"
  echo
  echo "[2b/3] Viser rutingtabell '${rt_table}' ..."
  ip route show table "$rt_table" || echo "⚠️  Fant ingen ruter i tabellen '$rt_table'."
}

run_tcpdump() {
  echo
  echo "[3/3] Starter tcpdump på $IFACE for $PROTO port $PORT i ${DURATION}s ..."
  echo "     (Generer trafikk fra en klient som er merket i MANGLE-reglene nå.)"
  echo

  # Velg riktig filter-uttrykk
  local filter
  if [[ "$PROTO" == "tcp" ]]; then
    filter="tcp port $PORT"
  elif [[ "$PROTO" == "udp" ]]; then
    filter="udp port $PORT"
  else
    echo "Ukjent PROTO: $PROTO (må være 'tcp' eller 'udp')" >&2
    exit 1
  fi

  # -n: ikke DNS-oppslag, -i: interface, -vv: litt mer detalj
  # Bruk timeout for å stoppe automatisk
  timeout "${DURATION}" tcpdump -ni "$IFACE" -vv "$filter" || true

  echo
  echo "Tips:"
  echo "  - Hvis du ikke så pakker: dobbeltsjekk at klient-IP er merket i MANGLE,"
  echo "    at du faktisk genererte $PROTO-trafikk til port $PORT, og at $IFACE er riktig."
}

# --- Kjør ----------------------------------------------------------------------
need_root
check_deps
print_header
show_rules
run_tcpdump

echo
echo "Ferdig. Hvis du så pakker på $IFACE for $PROTO/$PORT, fungerer selektiv ruting via VPN."
