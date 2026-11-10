#!/data/data/com.termux/files/usr/bin/bash
# Installer FLASH-ZTE-MF90 untuk Termux (tanpa root)
set -e
G='\033[1;32m'; Y='\033[1;33m'; R='\033[1;31m'; N='\033[0m'

echo -e "${G}[*] Update paket Termux...${N}"
pkg update -y && pkg upgrade -y

echo -e "${G}[*] Install paket dasar...${N}"
pkg install -y termux-api python git curl wget unzip p7zip tar xz-utils jq libusb clang make binutils which
pkg install -y unrar 2>/dev/null || echo -e "${Y}[!] unrar tidak tersedia, file .rar diekstrak pakai 7z${N}"

echo -e "${G}[*] Install termux-adb & termux-fastboot (ADB/Fastboot via OTG tanpa root)...${N}"
if ! command -v termux-adb >/dev/null 2>&1; then
  curl -fsSL https://raw.githubusercontent.com/nohajc/termux-adb/master/install.sh | bash
fi

echo -e "${G}[*] Install EDL tool (bkerler/edl)...${N}"
if [ ! -d "$HOME/edl" ]; then
  git clone --depth 1 --recursive https://github.com/bkerler/edl "$HOME/edl"
else
  git -C "$HOME/edl" pull --ff-only || true
fi
pip install --upgrade pip wheel setuptools || true
pip install pyusb pyserial docopt pycryptodome colorama lxml requests passlib wheel || true
pip install -r "$HOME/edl/requirements.txt" 2>/dev/null || echo -e "${Y}[!] Sebagian dependensi opsional EDL gagal dipasang (normal di Termux)${N}"

echo -e "${G}[*] Pasang perintah 'mf90'...${N}"
DIR="$(cd "$(dirname "$0")" && pwd)"
chmod +x "$DIR/mf90-flash.sh" "$DIR"/lib/*.sh
ln -sf "$DIR/mf90-flash.sh" "$PREFIX/bin/mf90"

[ -d "$HOME/storage" ] || termux-setup-storage || true
mkdir -p "$HOME/mf90/firmware" "$HOME/mf90/backup" "$HOME/mf90/download"

echo -e "${G}[✓] Instalasi selesai. Jalankan dengan perintah: ${Y}mf90${N}"
