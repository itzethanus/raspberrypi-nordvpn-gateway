# Pi‑hole i dette oppsettet

## Hva gjør Pi‑hole her?
- Fungerer som **primær DNS** for hele LAN.
- Kombineres med NordVPN der **kun utvalgt trafikk** går i VPN, mens DNS går lokalt via Pi‑hole.

## Viktige punkter
- Deaktiver NordVPNs egen DNS: `nordvpn set dns off` — ellers bypasses Pi‑hole.
- Åpne kun nødvendige porter inn til Pi‑en i iptables:
  - 53/UDP+TCP (DNS til Pi‑hole)
  - 80/TCP (Pi‑hole web, kun internt)
- Systemd‑enheten er satt til `After=pihole-FTL.service` for å sikre at DNS er oppe før gateway‑scriptet starter.

## DHCP / Router
- Sett **Gateway** og **DNS** i ruteren til Pi‑ens IP (f.eks. 192.168.1.102).
- Alternativt kan Pi‑hole være DHCP‑server (valgfritt) — da annonserer den automatisk seg selv som DNS.

## Feilsøk
- `pihole -t` — se live DNS‑spørringer.
- `dig example.com @127.0.0.1` — svarer Pi‑hole lokalt?
