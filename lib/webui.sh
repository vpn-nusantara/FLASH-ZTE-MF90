#!/data/data/com.termux/files/usr/bin/bash
# Modul GANTI WEB UI ZTE MF90 (di-source oleh mf90-flash.sh)

WEBUI_DIR="$WORK/webui"
WEBUI_SRC="$WEBUI_DIR/baru"
WEBUI_ROOT_FILE="$WORK/.webroot"

adb_ok() { $ADB get-state 2>/dev/null | grep -q device || { err "Modem belum terhubung ADB (menu 2 lalu menu 1)."; return 1; }; }

detect_webroot() {
  if [ -s "$WEBUI_ROOT_FILE" ]; then WEBROOT="$(cat "$WEBUI_ROOT_FILE")"; else WEBROOT=""; fi
  if [ -z "$WEBROOT" ]; then
    info "Mencari folder Web UI di modem..."
    local cand
    cand="$($ADB shell 'for d in /etc_ro/web /usr/zte_web/web /usr/zte/web /data/web /var/www /www /web; do [ -f $d/index.html ] && echo $d; done' 2>/dev/null | tr -d '\r' | head -n1)"
    [ -z "$cand" ] && cand="$($ADB shell 'find / -xdev -name index.html 2>/dev/null | grep -i web | head -n1' | tr -d '\r' | xargs -r dirname 2>/dev/null)"
    WEBROOT="$cand"
  fi
  echo -e "Folder Web UI terdeteksi: ${Y}${WEBROOT:-tidak ditemukan}${N}"
  read -rp "Pakai folder ini? (Y/n, atau ketik path lain): " a
  case "${a,,}" in ""|y) ;; n) read -rp "Path Web UI di modem: " WEBROOT ;; *) WEBROOT="$a" ;; esac
  [ -z "$WEBROOT" ] && { err "Folder Web UI kosong"; return 1; }
  echo "$WEBROOT" > "$WEBUI_ROOT_FILE"
}

remount_rw() {
  $ADB shell "mount -o remount,rw / 2>/dev/null; mount -o remount,rw \$(df $WEBROOT | tail -1 | awk '{print \$6}') 2>/dev/null; touch $WEBROOT/.rwtest && rm $WEBROOT/.rwtest && echo RW_OK" | grep -q RW_OK
}

webui_backup() {
  adb_ok && detect_webroot || return
  mkdir -p "$WEBUI_DIR/backup"
  local f="$WEBUI_DIR/backup/webui_$(date +%Y%m%d_%H%M%S).tar"
  info "Backup $WEBROOT → $f"
  $ADB shell "cd $WEBROOT && tar -cf /tmp/webui_bk.tar ." && $ADB pull /tmp/webui_bk.tar "$f" \
    && $ADB shell rm -f /tmp/webui_bk.tar && info "Backup tersimpan: $f" || err "Backup gagal"
}

webui_prepare() {
  echo "  1) Dari folder di HP"
  echo "  2) Download dari link (.zip/.rar/.7z/.tar)"
  echo "  3) Ekstrak arsip di HP"
  read -rp "Pilih: " p
  rm -rf "$WEBUI_SRC"; mkdir -p "$WEBUI_SRC"
  local f
  case $p in
    1) read -rp "Path folder Web UI: " s; [ -d "$s" ] && cp -r "$s"/. "$WEBUI_SRC"/ || { err "Folder tidak ada"; return 1; } ;;
    2) read -rp "URL Web UI: " url; f="$DL_DIR/$(basename "${url%%\?*}")"
       curl -fL --progress-bar -o "$f" "$url" || { err "Download gagal"; return 1; }
       FW_DIR="$WEBUI_SRC" extract_archive "$f" ;;
    3) read -rp "Path arsip: " f; [ -f "$f" ] || { err "File tidak ada"; return 1; }
       FW_DIR="$WEBUI_SRC" extract_archive "$f" ;;
    *) return 1 ;;
  esac
  local idx; idx="$(find "$WEBUI_SRC" -maxdepth 3 -name index.html | head -n1)"
  [ -z "$idx" ] && { err "index.html tidak ditemukan di Web UI baru"; return 1; }
  WEBUI_SRC_ROOT="$(dirname "$idx")"
  info "Web UI baru siap: $WEBUI_SRC_ROOT ($(find "$WEBUI_SRC_ROOT" -type f | wc -l) file)"
}

webui_push_tar() {
  local src="$1"
  local t="$WORK/.webui_push.tar"
  tar -cf "$t" -C "$src" . || return 1
  $ADB push "$t" /tmp/webui_new.tar || return 1
  remount_rw || { err "Folder $WEBROOT read-only (tidak bisa ditulis). Gunakan firmware yang Web UI-nya bisa diubah."; return 1; }
  $ADB shell "cd $WEBROOT && rm -rf ./* && tar -xf /tmp/webui_new.tar && rm -f /tmp/webui_new.tar && sync && echo PUSH_OK" | grep -q PUSH_OK
}

webui_install() {
  adb_ok && detect_webroot || return
  webui_prepare || return
  warn "Web UI lama akan di-backup otomatis dulu."
  webui_backup
  confirm "Ganti Web UI di $WEBROOT?" || return
  if webui_push_tar "$WEBUI_SRC_ROOT"; then
    info "Web UI berhasil diganti. Buka http://$MODEM_IP (hapus cache browser)."
    read -rp "Reboot modem? (Y/n): " r; [ "${r,,}" != "n" ] && $ADB reboot
  else err "Gagal mengganti Web UI."; fi
}

webui_restore() {
  adb_ok && detect_webroot || return
  local list; mapfile -t list < <(ls -1t "$WEBUI_DIR"/backup/*.tar 2>/dev/null)
  [ ${#list[@]} -eq 0 ] && { err "Belum ada backup"; return; }
  local i=1; for b in "${list[@]}"; do echo "  $i) $(basename "$b")"; i=$((i+1)); done
  read -rp "Pilih backup: " n
  local b="${list[$((n-1))]}"; [ -f "$b" ] || return
  local tmp="$WORK/.webui_restore"; rm -rf "$tmp"; mkdir -p "$tmp"; tar -xf "$b" -C "$tmp"
  confirm "Restore $(basename "$b") ke $WEBROOT?" || return
  webui_push_tar "$tmp" && info "Restore berhasil." || err "Restore gagal."
}

webui_edit_title() {
  adb_ok && detect_webroot || return
  read -rp "Judul baru halaman (title): " t
  [ -z "$t" ] && return
  remount_rw || { err "Folder read-only"; return; }
  $ADB shell "sed -i 's|<title>[^<]*</title>|<title>$t</title>|' $WEBROOT/index.html && grep -o '<title>.*</title>' $WEBROOT/index.html"
}

webui_menu() {
  banner
  echo -e "  ${C}GANTI WEB UI ZTE MF90${N} (butuh ADB aktif)"
  echo "  1) Deteksi folder Web UI di modem"
  echo "  2) Backup Web UI asli"
  echo "  3) Pasang / ganti Web UI baru"
  echo "  4) Restore Web UI dari backup"
  echo "  5) Ganti judul halaman Web UI"
  read -rp "Pilih: " p
  case $p in
    1) adb_ok && detect_webroot ;;
    2) webui_backup ;;
    3) webui_install ;;
    4) webui_restore ;;
    5) webui_edit_title ;;
  esac
  pause
}
