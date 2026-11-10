#!/data/data/com.termux/files/usr/bin/bash
# FLASH-ZTE-MF90 - Flash modem ZTE MF90 via Termux + OTG (tanpa root)
# Repo: https://github.com/vpn-nusantara/FLASH-ZTE-MF90-

VERSION="1.2.0"
WORK="$HOME/mf90"
FW_DIR="$WORK/firmware"
BK_DIR="$WORK/backup"
DL_DIR="$WORK/download"
EDL_PY="$HOME/edl/edl"
MODEM_IP="${MODEM_IP:-192.168.0.1}"
LOG="$WORK/mf90.log"

R='\033[1;31m'; G='\033[1;32m'; Y='\033[1;33m'; B='\033[1;34m'; C='\033[1;36m'; N='\033[0m'
mkdir -p "$FW_DIR" "$BK_DIR" "$DL_DIR"

ADB="$(command -v termux-adb || command -v adb)"
FASTBOOT="$(command -v termux-fastboot || command -v fastboot)"

info() { echo -e "${G}[*]${N} $*"; echo "[$(date '+%F %T')] $*" >> "$LOG"; }
warn() { echo -e "${Y}[!]${N} $*"; echo "[$(date '+%F %T')] WARN $*" >> "$LOG"; }
err()  { echo -e "${R}[x]${N} $*"; echo "[$(date '+%F %T')] ERR $*" >> "$LOG"; }
pause() { echo; read -rp "Tekan ENTER untuk lanjut..." _; }
confirm() { read -rp "$(echo -e "${Y}$1 Ketik YA untuk lanjut: ${N}")" a; [ "$a" = "YA" ]; }

banner() {
  clear
  echo -e "${C}"
  echo "  ███╗   ███╗███████╗ █████╗  ██████╗ "
  echo "  ████╗ ████║██╔════╝██╔══██╗██╔═████╗"
  echo "  ██╔████╔██║█████╗  ╚██████║██║██╔██║"
  echo "  ██║╚██╔╝██║██╔══╝   ╚═══██║████╔╝██║"
  echo "  ██║ ╚═╝ ██║██║      █████╔╝╚██████╔╝"
  echo "  ╚═╝     ╚═╝╚═╝      ╚════╝  ╚═════╝ "
  echo -e "${N}  ${B}FLASH ZTE MF90 via Termux OTG${N} v$VERSION"
  echo -e "  Firmware : ${Y}$FW_DIR${N}"
  echo "  ------------------------------------------"
}

check_deps() {
  local miss=()
  for c in termux-usb curl jq python; do command -v "$c" >/dev/null || miss+=("$c"); done
  [ -z "$ADB" ] && miss+=("termux-adb")
  [ -z "$FASTBOOT" ] && miss+=("termux-fastboot")
  if [ ${#miss[@]} -gt 0 ]; then
    err "Perintah belum terpasang: ${miss[*]}"
    warn "Jalankan dulu: bash install.sh"
    exit 1
  fi
}

# ---------- USB / OTG ----------
usb_list() { termux-usb -l 2>/dev/null | jq -r '.[]' 2>/dev/null; }

pick_usb() {
  local devs; mapfile -t devs < <(usb_list)
  if [ ${#devs[@]} -eq 0 ]; then
    err "Tidak ada perangkat USB terdeteksi. Cek kabel OTG & modem." >&2; return 1
  fi
  if [ ${#devs[@]} -eq 1 ]; then echo "${devs[0]}"; return 0; fi
  echo "Pilih perangkat USB:" >&2
  local i=1; for d in "${devs[@]}"; do echo "  $i) $d" >&2; i=$((i+1)); done
  read -rp "Nomor: " n
  echo "${devs[$((n-1))]}"
}

cek_koneksi() {
  banner
  info "Perangkat USB (OTG):"
  local list; list="$(usb_list)"
  [ -z "$list" ] && warn "Kosong. Colok modem via OTG lalu izinkan akses USB." || echo "$list"
  echo
  info "ADB devices:"; $ADB devices 2>&1 | tail -n +2
  info "Fastboot devices:"; timeout 8 $FASTBOOT devices 2>&1
  echo
  echo -e "Petunjuk VID:PID → ${C}19d2:xxxx${N}=ZTE normal/ADB, ${C}18d1:d00d${N}=fastboot, ${C}05c6:9008${N}=EDL"
  pause
}

# ---------- ADB via WebUI ----------
zte_login() {
  read -rsp "Password admin WebUI (default: admin, kosongkan jika tidak perlu): " pw; echo
  pw="${pw:-admin}"
  local b64; b64="$(printf '%s' "$pw" | base64)"
  curl -s -m 10 -c "$WORK/cookie" -H "Referer: http://$MODEM_IP/index.html" \
    -d "isTest=false&goformId=LOGIN&password=$b64" \
    "http://$MODEM_IP/goform/goform_set_cmd_process"; echo
}

aktifkan_adb() {
  banner
  info "Pastikan HP terhubung ke WiFi modem MF90 (IP $MODEM_IP)."
  zte_login
  info "Mengirim perintah USB_MODE_SWITCH (usb_mode=6 → ADB aktif)..."
  curl -s -m 10 -b "$WORK/cookie" -H "Referer: http://$MODEM_IP/index.html" \
    "http://$MODEM_IP/goform/goform_set_cmd_process?goformId=USB_MODE_SWITCH&usb_mode=6&isTest=false"; echo
  info "Metode alternatif (firmware lama: MODE_SWITCH FACTORY)..."
  curl -s -m 10 -b "$WORK/cookie" -H "Referer: http://$MODEM_IP/index.html" \
    "http://$MODEM_IP/goform/goform_process?goformId=MODE_SWITCH&switchCmd=FACTORY"; echo
  info "Cabut-colok modem ke OTG, lalu cek menu 1 (ADB devices)."
  pause
}

# ---------- Firmware ----------
extract_archive() {
  local f="$1" out="$FW_DIR"
  info "Mengekstrak $(basename "$f") ke $out"
  case "${f,,}" in
    *.zip) unzip -o "$f" -d "$out" ;;
    *.7z) 7z x -y -o"$out" "$f" ;;
    *.rar) if command -v unrar >/dev/null; then unrar x -o+ "$f" "$out/"; else 7z x -y -o"$out" "$f"; fi ;;
    *.tar.gz|*.tgz) tar -xzf "$f" -C "$out" ;;
    *.tar.xz) tar -xJf "$f" -C "$out" ;;
    *.tar) tar -xf "$f" -C "$out" ;;
    *) err "Format tidak dikenal: $f"; return 1 ;;
  esac && info "Ekstrak selesai." || err "Ekstrak gagal."
}

siapkan_firmware() {
  banner
  echo "  1) Pakai folder firmware dari HP (mis. /sdcard/Download/MF90)"
  echo "  2) Download firmware dari link"
  echo "  3) Ekstrak file arsip (.zip/.rar/.7z/.tar) yang ada di HP"
  echo "  4) Lihat isi folder firmware"
  echo "  5) Kosongkan folder firmware"
  read -rp "Pilih: " p
  case $p in
    1) read -rp "Path folder: " src
       [ -d "$src" ] || { err "Folder tidak ada: $src"; pause; return; }
       cp -rv "$src"/. "$FW_DIR"/ && info "Firmware disalin ke $FW_DIR" ;;
    2) read -rp "URL firmware: " url
       [ -z "$url" ] && { err "URL kosong"; pause; return; }
       local name; name="$(basename "${url%%\?*}")"; [ -z "$name" ] && name="firmware.zip"
       info "Download $name ..."
       if curl -fL --progress-bar -o "$DL_DIR/$name" "$url"; then
         info "Tersimpan: $DL_DIR/$name"
         case "${name,,}" in *.zip|*.7z|*.rar|*.tar|*.tgz|*.tar.gz|*.tar.xz) extract_archive "$DL_DIR/$name";;
           *) cp "$DL_DIR/$name" "$FW_DIR/";; esac
       else err "Download gagal."; fi ;;
    3) read -rp "Path file arsip: " f
       [ -f "$f" ] && extract_archive "$f" || err "File tidak ada: $f" ;;
    4) find "$FW_DIR" -maxdepth 3 -type f -exec ls -lh {} \; | awk '{print $5"\t"$9}' ;;
    5) confirm "Hapus semua isi $FW_DIR?" && rm -rf "${FW_DIR:?}"/* && info "Folder dikosongkan." ;;
  esac
  pause
}

# nama file → nama partisi MF90 (MDM9x25)
part_of() {
  local b; b="$(basename "${1,,}")"
  case "$b" in
    sbl1*|sbl*.mbn) echo sbl ;;
    appsboot*|aboot*|emmc_appsboot*) echo aboot ;;
    *recovery*.img|recovery*) echo recovery ;;
    *boot*.img|boot.*) echo boot ;;
    non-hlos*|modem*.bin|modem*.ubi|*amss*) echo modem ;;
    rpm*.mbn|rpm*) echo rpm ;;
    tz*.mbn|tz*) echo tz ;;
    *sysfs*|system*|*rootfs*) echo system ;;
    *cache*) echo cache ;;
    *usrfs*|*userdata*) echo userdata ;;
    *) echo "" ;;
  esac
}

build_plan() {
  PLAN=()
  while IFS= read -r f; do
    local p; p="$(part_of "$f")"
    [ -z "$p" ] && continue
    [ "$p" = "sbl" ] && [ "$WITH_SBL" != "1" ] && continue
    PLAN+=("$p|$f")
  done < <(find "$FW_DIR" -maxdepth 3 -type f \( -iname '*.img' -o -iname '*.mbn' -o -iname '*.bin' -o -iname '*.yaffs2' -o -iname '*.ubi' -o -iname '*.ubifs' \) | sort)
}

show_plan() {
  echo -e "${C}Rencana flash:${N}"
  for x in "${PLAN[@]}"; do printf "  %-10s ← %s\n" "${x%%|*}" "$(basename "${x#*|}")"; done
}

# ---------- Fastboot ----------
flash_fastboot() {
  banner
  read -rp "Ikutkan bootloader SBL? (berisiko, y/N): " s; [ "${s,,}" = "y" ] && WITH_SBL=1 || WITH_SBL=0
  build_plan
  [ ${#PLAN[@]} -eq 0 ] && { err "Tidak ada file firmware dikenali di $FW_DIR"; pause; return; }
  show_plan
  if ! timeout 8 $FASTBOOT devices | grep -q .; then
    info "Modem belum di fastboot. Mencoba: adb reboot bootloader"
    $ADB reboot bootloader 2>&1; info "Menunggu fastboot (maks 40 dtk)..."
    for _ in $(seq 1 20); do sleep 2; timeout 5 $FASTBOOT devices | grep -q . && break; done
  fi
  timeout 8 $FASTBOOT devices | grep -q . || { err "Fastboot tidak terdeteksi."; pause; return; }
  confirm "JANGAN cabut kabel/OTG selama flash!" || return
  local ok=0 fail=0
  for x in "${PLAN[@]}"; do
    local p="${x%%|*}" f="${x#*|}"
    info "fastboot flash $p $(basename "$f")"
    if $FASTBOOT flash "$p" "$f" 2>&1 | tee -a "$LOG"; then ok=$((ok+1)); else fail=$((fail+1)); err "Gagal: $p"; fi
  done
  info "Selesai. Berhasil: $ok | Gagal: $fail"
  read -rp "Reboot modem sekarang? (Y/n): " r; [ "${r,,}" != "n" ] && $FASTBOOT reboot
  pause
}

# ---------- EDL ----------
edl_run() {
  [ -f "$EDL_PY" ] || { err "EDL tool belum ada di $EDL_PY, jalankan install.sh"; return 1; }
  local dev; dev="$(pick_usb)" || return 1
  local wrap="$WORK/.edl_wrap.sh"
  { echo '#!/data/data/com.termux/files/usr/bin/bash'
    printf 'cd %q && python %q' "$WORK" "$EDL_PY"
    for a in "$@"; do printf ' %q' "$a"; done; echo; } > "$wrap"
  chmod +x "$wrap"
  info "EDL: $* (device $dev)"
  termux-usb -r -E -e "$wrap" "$dev" 2>&1 | tee -a "$LOG"
}

find_loader() {
  LOADER="$(find "$FW_DIR" -maxdepth 3 -type f \( -iname '*firehose*' -o -iname 'prog_*' -o -iname '*nprg*' \) | head -n1)"
  if [ -n "$LOADER" ]; then
    info "Loader ditemukan: $(basename "$LOADER")"
    read -rp "Pakai loader ini? (Y/n): " a; [ "${a,,}" = "n" ] && LOADER=""
  fi
  [ -z "$LOADER" ] && read -rp "Path loader firehose (.mbn/.elf): " LOADER
  [ -f "$LOADER" ] || { err "Loader tidak ditemukan."; return 1; }
}

to_edl() {
  info "Mencoba masuk EDL: adb reboot edl"
  $ADB reboot edl 2>/dev/null || $FASTBOOT oem edl 2>/dev/null
  sleep 5
  usb_list
  warn "Jika gagal, masuk EDL manual (test point / tombol) sampai muncul 05c6:9008."
}

flash_edl() {
  banner
  echo "  1) Flash otomatis (rawprogram*.xml + patch*.xml jika ada)"
  echo "  2) Flash per-partisi dari folder firmware"
  echo "  3) Tulis 1 partisi manual"
  echo "  4) Lihat tabel partisi (printgpt)"
  echo "  5) Reboot modem dari EDL"
  read -rp "Pilih: " p
  find_loader || { pause; return; }
  case $p in
    1) local raw patch; raw="$(find "$FW_DIR" -maxdepth 3 -iname 'rawprogram*.xml' | head -n1)"
       patch="$(find "$FW_DIR" -maxdepth 3 -iname 'patch*.xml' | head -n1)"
       [ -z "$raw" ] && { err "rawprogram*.xml tidak ada, pakai opsi 2."; pause; return; }
       confirm "Flash penuh via EDL. Pastikan sudah BACKUP!" || return
       edl_run qfil "$raw" "${patch:-$raw}" "$(dirname "$raw")" --loader="$LOADER" --memory=nand ;;
    2) read -rp "Ikutkan SBL? (y/N): " s; [ "${s,,}" = "y" ] && WITH_SBL=1 || WITH_SBL=0
       build_plan; [ ${#PLAN[@]} -eq 0 ] && { err "Tidak ada file dikenali."; pause; return; }
       show_plan; confirm "Flash per-partisi via EDL." || return
       for x in "${PLAN[@]}"; do edl_run w "${x%%|*}" "${x#*|}" --loader="$LOADER" --memory=nand; done
       edl_run reset --loader="$LOADER" ;;
    3) read -rp "Nama partisi: " pn; read -rp "Path file: " pf
       [ -f "$pf" ] && confirm "Tulis $pf ke $pn?" && edl_run w "$pn" "$pf" --loader="$LOADER" --memory=nand ;;
    4) edl_run printgpt --loader="$LOADER" --memory=nand ;;
    5) edl_run reset --loader="$LOADER" ;;
  esac
  pause
}

backup_edl() {
  banner
  find_loader || { pause; return; }
  local out; out="$BK_DIR/mf90_$(date +%Y%m%d_%H%M%S)"
  mkdir -p "$out"
  info "Backup semua partisi ke $out (lama, sabar)..."
  edl_run rl "$out" --loader="$LOADER" --memory=nand --genxml
  info "Backup selesai: $out"
  pause
}

# ---------- Unlock all operator ----------
zte_get() {
  curl -s -m 10 -b "$WORK/cookie" -H "Referer: http://$MODEM_IP/index.html" \
    "http://$MODEM_IP/goform/goform_get_cmd_process?isTest=false&multi_data=1&cmd=$1"
}

at_cmd() {
  local port="$1" cmd="$2"
  $ADB shell "cat $port > /tmp/at.out & P=\$!; printf '%s\r' '$cmd' > $port; sleep 2; kill \$P; cat /tmp/at.out" 2>&1
}

pick_at_port() {
  echo "Port AT umum MF90: /dev/smd11, /dev/smd8, /dev/smd7, /dev/smd0"
  read -rp "Port AT [/dev/smd11]: " ATP; ATP="${ATP:-/dev/smd11}"
}

unlock_operator() {
  banner
  echo -e "  ${C}UNLOCK ALL OPERATOR (SIM lock / network lock)${N}"
  echo "  1) Cek status kunci SIM (WebUI)"
  echo "  2) Unlock pakai kode NCK via WebUI"
  echo "  3) Unlock pakai kode NCK via AT command (ADB)"
  echo "  4) Cek status kunci via AT command (ADB)"
  echo "  5) Kirim AT command manual (ADB)"
  echo "  6) Flash firmware debrand/open-line (ke menu Fastboot)"
  read -rp "Pilih: " p
  case $p in
    1) zte_login >/dev/null
       zte_get "modem_main_state,unlock_nck_time,sim_imsi,network_provider,imei" | jq . 2>/dev/null || warn "Tidak bisa baca WebUI"
       echo -e "Jika modem_main_state = ${Y}modem_imsi_waitnck${N} → modem terkunci operator." ;;
    2) zte_login >/dev/null
       read -rp "Masukkan kode NCK (16 digit): " nck
       [ -z "$nck" ] && { err "Kode kosong"; pause; return; }
       warn "Sisa percobaan: $(zte_get unlock_nck_time | jq -r .unlock_nck_time 2>/dev/null)"
       confirm "Salah kode berkali-kali bisa mengunci permanen." || return
       curl -s -m 10 -b "$WORK/cookie" -H "Referer: http://$MODEM_IP/index.html" \
         -d "isTest=false&goformId=UNLOCK_NETWORK&unlock_network_code=$nck" \
         "http://$MODEM_IP/goform/goform_set_cmd_process"; echo
       info "Restart modem, lalu masukkan SIM operator lain." ;;
    3) pick_at_port; read -rp "Masukkan kode NCK: " nck
       [ -z "$nck" ] && { err "Kode kosong"; pause; return; }
       confirm "Kirim AT+ZNCK ke modem." || return
       at_cmd "$ATP" "AT+ZNCK=\"$nck\"" ;;
    4) pick_at_port
       at_cmd "$ATP" "AT+ZNCK?"; at_cmd "$ATP" "AT+CLCK=\"PN\",2" ;;
    5) pick_at_port; read -rp "AT command: " c; at_cmd "$ATP" "$c" ;;
    6) flash_fastboot; return ;;
  esac
  pause
}

reboot_menu() {
  banner
  echo "  1) Normal   2) Fastboot   3) EDL"
  read -rp "Pilih: " p
  case $p in
    1) $ADB reboot 2>/dev/null || $FASTBOOT reboot ;;
    2) $ADB reboot bootloader ;;
    3) to_edl ;;
  esac
  pause
}

main_menu() {
  while true; do
    banner
    echo "  1) Cek koneksi modem (OTG/ADB/Fastboot/EDL)"
    echo "  2) Aktifkan ADB modem (via WebUI)"
    echo "  3) Siapkan firmware (folder / download / ekstrak)"
    echo "  4) Flash via FASTBOOT"
    echo "  5) Flash via EDL (9008)"
    echo "  6) Backup firmware via EDL"
    echo "  7) Unlock all operator"
    echo "  8) Reboot modem (normal/fastboot/EDL)"
    echo "  9) Lock band / mode jaringan"
    echo " 10) Ganti Web UI"
    echo " 11) Penyimpanan cloud (upload/unduh backup, firmware, log)"
    echo "  0) Keluar"
    read -rp "Pilih menu: " m
    case $m in
      1) cek_koneksi ;; 2) aktifkan_adb ;; 3) siapkan_firmware ;;
      4) flash_fastboot ;; 5) flash_edl ;; 6) backup_edl ;;
      7) unlock_operator ;; 8) reboot_menu ;; 9) bandlock_menu ;;
      10) webui_menu ;; 11) cloud_menu ;; 0) exit 0 ;;
      *) warn "Pilihan tidak valid"; sleep 1 ;;
    esac
  done
}

BASE_DIR="$(dirname "$(readlink -f "$0")")"
. "$BASE_DIR/lib/bandlock.sh"
. "$BASE_DIR/lib/webui.sh"
. "$BASE_DIR/lib/cloud.sh"

check_deps
main_menu
