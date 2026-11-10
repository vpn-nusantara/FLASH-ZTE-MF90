#!/data/data/com.termux/files/usr/bin/bash
# Modul PENYIMPANAN CLOUD (di-source oleh mf90-flash.sh)

CLOUD_CONF="$WORK/cloud.conf"
CLOUD_URL_DEFAULT="https://zte-mf90-flash--0r42iomw.preview.emergentagent.com"
[ -f "$CLOUD_CONF" ] && . "$CLOUD_CONF"
CLOUD_URL="${CLOUD_URL:-$CLOUD_URL_DEFAULT}"
CLOUD_CODE="${CLOUD_CODE:-}"

cloud_api() { echo "${CLOUD_URL%/}/api"; }

cloud_setup() {
  read -rp "Alamat server cloud [$CLOUD_URL]: " u; CLOUD_URL="${u:-$CLOUD_URL}"
  read -rsp "Kode akses owner (kosongkan jika hanya mengunduh file publik): " c; echo
  CLOUD_CODE="$c"
  if [ -n "$CLOUD_CODE" ]; then
    if curl -s -f -m 15 -X POST -H "X-Access-Code: $CLOUD_CODE" "$(cloud_api)/auth/check" >/dev/null; then
      info "Kode akses benar (mode owner)."
    else
      err "Kode akses salah atau server tidak bisa dihubungi."; CLOUD_CODE=""
    fi
  fi
  printf 'CLOUD_URL=%q\nCLOUD_CODE=%q\n' "$CLOUD_URL" "$CLOUD_CODE" > "$CLOUD_CONF"
  chmod 600 "$CLOUD_CONF"
}

cloud_hdr() { [ -n "$CLOUD_CODE" ] && printf '%s' "X-Access-Code: $CLOUD_CODE" || printf '%s' "X-None: 1"; }

cloud_upload_file() {
  local f="$1" cat="$2" note="$3"
  [ -z "$CLOUD_CODE" ] && { err "Upload butuh kode akses (opsi 1)."; return 1; }
  [ -f "$f" ] || { err "File tidak ada: $f"; return 1; }
  info "Upload $(basename "$f") ($(du -h "$f" | cut -f1)) → kategori $cat"
  local out
  out="$(curl -s --progress-bar -m 1800 -H "$(cloud_hdr)" \
    -F "file=@$f" -F "category=$cat" -F "note=$note" "$(cloud_api)/files")"
  if echo "$out" | jq -e .id >/dev/null 2>&1; then
    info "Berhasil. ID: $(echo "$out" | jq -r .id) | $(echo "$out" | jq -r 'if .is_public then "Publik" else "Privat" end')"
  else
    err "Upload gagal: $out"
  fi
}

pick_latest() { ls -1td "$@" 2>/dev/null | head -n1; }

cloud_upload_menu() {
  echo "  1) Backup EDL terbaru (dikompres .tar.gz)"
  echo "  2) Backup Web UI terbaru"
  echo "  3) Log flash (mf90.log)"
  echo "  4) File firmware (path)"
  echo "  5) File Web UI (path)"
  read -rp "Pilih: " p
  local f note
  read -rp "Catatan (opsional): " note
  case $p in
    1) local d; d="$(pick_latest "$BK_DIR"/mf90_*)"
       [ -z "$d" ] && { err "Belum ada backup EDL (menu 6)."; return; }
       f="$WORK/$(basename "$d").tar.gz"; info "Kompres $d ..."
       tar -czf "$f" -C "$BK_DIR" "$(basename "$d")" && cloud_upload_file "$f" backup_edl "$note"; rm -f "$f" ;;
    2) f="$(pick_latest "$WORK"/webui/backup/*.tar)"
       [ -z "$f" ] && { err "Belum ada backup Web UI (menu 10)."; return; }
       cloud_upload_file "$f" backup_webui "$note" ;;
    3) cloud_upload_file "$LOG" log "$note" ;;
    4) read -rp "Path file firmware: " f; cloud_upload_file "$f" firmware "$note" ;;
    5) read -rp "Path file Web UI: " f; cloud_upload_file "$f" webui "$note" ;;
  esac
}

cloud_list() {
  local cat="${1:-all}"
  CLOUD_LIST="$(curl -s -m 20 -H "$(cloud_hdr)" "$(cloud_api)/files?category=$cat")"
  if ! echo "$CLOUD_LIST" | jq -e 'type=="array"' >/dev/null 2>&1; then
    err "Gagal mengambil daftar: $CLOUD_LIST"; CLOUD_LIST="[]"; return 1
  fi
  [ "$(echo "$CLOUD_LIST" | jq length)" = "0" ] && { warn "Belum ada file."; return 1; }
  echo "$CLOUD_LIST" | jq -r 'to_entries[] | "\(.key+1)) [\(.value.category)] \(.value.original_filename)  \((.value.size/1048576*100|floor)/100) MB  \(if .value.is_public then "Publik" else "Privat" end)"'
}

cloud_pick() {
  cloud_list "$1" || return 1
  read -rp "Nomor file: " n
  CLOUD_ID="$(echo "$CLOUD_LIST" | jq -r ".[$((n-1))].id // empty")"
  CLOUD_NAME="$(echo "$CLOUD_LIST" | jq -r ".[$((n-1))].original_filename // empty")"
  CLOUD_CAT="$(echo "$CLOUD_LIST" | jq -r ".[$((n-1))].category // empty")"
  [ -n "$CLOUD_ID" ] || { err "Nomor tidak valid"; return 1; }
}

cloud_download() {
  cloud_pick all || return
  local dest="$DL_DIR/$CLOUD_NAME"
  info "Mengunduh $CLOUD_NAME ..."
  if curl -f --progress-bar -m 1800 -H "$(cloud_hdr)" -o "$dest" "$(cloud_api)/files/$CLOUD_ID/download"; then
    info "Tersimpan: $dest"
    case "$CLOUD_CAT" in
      firmware) read -rp "Ekstrak/salin ke folder firmware sekarang? (Y/n): " a
        if [ "${a,,}" != "n" ]; then
          case "${CLOUD_NAME,,}" in *.zip|*.7z|*.rar|*.tar|*.tgz|*.tar.gz|*.tar.xz) extract_archive "$dest" ;; *) cp "$dest" "$FW_DIR/" ;; esac
        fi ;;
      webui|backup_webui) info "Pakai file ini di menu 10 → Pasang Web UI (opsi ekstrak arsip): $dest" ;;
    esac
  else err "Unduh gagal (file privat butuh kode akses)."; rm -f "$dest"; fi
}

cloud_delete() {
  [ -z "$CLOUD_CODE" ] && { err "Hapus butuh kode akses."; return; }
  cloud_pick all || return
  confirm "Hapus $CLOUD_NAME dari cloud?" || return
  curl -s -m 20 -X DELETE -H "$(cloud_hdr)" "$(cloud_api)/files/$CLOUD_ID"; echo
}

cloud_menu() {
  banner
  echo -e "  ${C}PENYIMPANAN CLOUD${N}  server: ${Y}$CLOUD_URL${N}"
  echo -e "  Mode: $([ -n "$CLOUD_CODE" ] && echo "${G}Owner${N}" || echo "${Y}Publik (hanya unduh file publik)${N}")"
  echo "  1) Atur server & kode akses"
  echo "  2) Upload (backup EDL / backup Web UI / log / firmware / Web UI)"
  echo "  3) Lihat daftar file"
  echo "  4) Unduh file"
  echo "  5) Hapus file"
  read -rp "Pilih: " p
  case $p in
    1) cloud_setup ;; 2) cloud_upload_menu ;; 3) cloud_list all ;;
    4) cloud_download ;; 5) cloud_delete ;;
  esac
  pause
}
