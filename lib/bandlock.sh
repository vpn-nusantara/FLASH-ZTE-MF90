#!/data/data/com.termux/files/usr/bin/bash
# Modul LOCK BAND ZTE MF90 (di-source oleh mf90-flash.sh)

zte_ad() {
  # Token AD untuk firmware ZTE yang mewajibkan (md5(md5(wa_inner_version+cr_version)+RD))
  local v rd wa cr
  v="$(zte_get "wa_inner_version,cr_version")"
  wa="$(echo "$v" | jq -r '.wa_inner_version // empty' 2>/dev/null)"
  cr="$(echo "$v" | jq -r '.cr_version // empty' 2>/dev/null)"
  rd="$(curl -s -m 10 -b "$WORK/cookie" -H "Referer: http://$MODEM_IP/index.html" \
        "http://$MODEM_IP/goform/goform_get_cmd_process?isTest=false&cmd=RD" | jq -r '.RD // empty' 2>/dev/null)"
  [ -z "$rd" ] && { echo ""; return; }
  local a; a="$(printf '%s' "$wa$cr" | md5sum | cut -d' ' -f1)"
  printf '%s' "$a$rd" | md5sum | cut -d' ' -f1
}

zte_set() {
  local ad; ad="$(zte_ad)"
  curl -s -m 10 -b "$WORK/cookie" -H "Referer: http://$MODEM_IP/index.html" \
    -d "isTest=false&$1${ad:+&AD=$ad}" "http://$MODEM_IP/goform/goform_set_cmd_process"; echo
}

bands_to_mask() {
  python - "$1" <<'EOF'
import sys
m = 0
for b in sys.argv[1].replace(',', '+').split('+'):
    b = b.strip()
    if b.isdigit() and 0 < int(b) <= 64:
        m |= 1 << (int(b) - 1)
print(hex(m) if m else "")
EOF
}

mask_to_bands() {
  python - "$1" <<'EOF'
import sys
try: m = int(sys.argv[1], 16)
except Exception: m = 0
print("+".join(str(i + 1) for i in range(64) if m >> i & 1) or "-")
EOF
}

band_status() {
  local s; s="$(zte_get "network_type,lte_band,lte_band_lock,net_select,lte_rsrp,lte_sinr,lte_rsrq,network_provider,cell_id,lte_pci")"
  echo "$s" | jq . 2>/dev/null || { warn "Tidak bisa membaca WebUI"; return; }
  local lk; lk="$(echo "$s" | jq -r '.lte_band_lock // empty')"
  [ -n "$lk" ] && echo -e "Band terkunci saat ini: ${Y}$(mask_to_bands "$lk")${N}"
}

lock_band() {
  echo -e "Band LTE umum di Indonesia: ${C}1 (2100), 3 (1800), 5 (850), 8 (900), 40 (2300)${N}"
  read -rp "Band yang dikunci (contoh: 3 atau 1+3+40): " bl
  local mask; mask="$(bands_to_mask "$bl")"
  [ -z "$mask" ] && { err "Format band salah"; return; }
  info "Band $bl → mask $mask"
  confirm "Kunci band LTE ke $bl?" || return
  info "Metode 1: BAND_SELECT"
  zte_set "goformId=BAND_SELECT&is_gw_band=0&gw_band_mask=0&is_lte_band=1&lte_band_mask=$mask"
  info "Metode 2: SET_NETWORK_BAND_LOCK"
  zte_set "goformId=SET_NETWORK_BAND_LOCK&lte_band_lock=$mask"
  info "Selesai. Jika hasil {\"result\":\"success\"}, putuskan & sambungkan ulang data (atau reboot modem)."
}

network_mode() {
  echo "  1) 4G saja (Only_LTE)"
  echo "  2) 3G saja (Only_WCDMA)"
  echo "  3) 2G saja (Only_GSM)"
  echo "  4) Otomatis 4G/3G/2G (NETWORK_auto)"
  echo "  5) 4G/3G (WCDMA_AND_LTE)"
  read -rp "Pilih: " n
  local m
  case $n in 1) m=Only_LTE;; 2) m=Only_WCDMA;; 3) m=Only_GSM;; 4) m=NETWORK_auto;; 5) m=WCDMA_AND_LTE;; *) return;; esac
  zte_set "goformId=DISCONNECT_NETWORK" >/dev/null
  zte_set "goformId=SET_BEARER_PREFERENCE&BearerPreference=$m"
  sleep 2; zte_set "goformId=CONNECT_NETWORK" >/dev/null
  info "Mode jaringan diubah ke $m"
}

bandlock_menu() {
  banner
  echo -e "  ${C}LOCK BAND ZTE MF90${N}"
  echo "  1) Cek band & sinyal saat ini"
  echo "  2) Lock band LTE"
  echo "  3) Buka lock (semua band)"
  echo "  4) Ganti mode jaringan (4G only / 3G / 2G / auto)"
  echo "  5) Pantau sinyal live (Ctrl+C untuk berhenti)"
  echo "  6) Lock band via AT command manual (ADB)"
  read -rp "Pilih: " p
  [ "$p" = "6" ] || zte_login >/dev/null
  case $p in
    1) band_status ;;
    2) lock_band ;;
    3) confirm "Buka semua band LTE?" && {
         zte_set "goformId=BAND_SELECT&is_gw_band=0&gw_band_mask=0&is_lte_band=1&lte_band_mask=0xA3E2AB0908DF"
         zte_set "goformId=SET_NETWORK_BAND_LOCK&lte_band_lock=0xA3E2AB0908DF"; } ;;
    4) network_mode ;;
    5) trap 'trap - INT; return' INT
       while true; do
         clear; echo -e "${C}Sinyal live $(date +%T)${N}"
         zte_get "network_type,lte_band,lte_rsrp,lte_rsrq,lte_sinr,cell_id,lte_pci" | jq . 2>/dev/null
         sleep 3
       done ;;
    6) pick_at_port
       echo "Contoh: AT+ZNLOCKBAND? (tergantung firmware). Ketik perintah AT:"
       read -rp "AT command: " c; at_cmd "$ATP" "$c" ;;
  esac
  pause
}
