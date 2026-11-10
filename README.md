# FLASH-ZTE-MF90

Script **Termux** untuk flash modem **ZTE MF90** lewat kabel **OTG** — **tanpa root**.

Fitur:
- Flash firmware via **Fastboot**
- Flash penuh via **EDL (9008)** + backup semua partisi
- **Unlock all operator** (kode NCK via WebUI / AT command, atau flash firmware debrand)
- Siapkan firmware: dari folder HP, **download dari link**, atau **ekstrak** `.zip/.rar/.7z/.tar` langsung di Termux
- **Lock band** LTE & ganti mode jaringan (4G only, dll) + pantau sinyal live
- **Ganti Web UI** modem (backup, pasang baru, restore)
- Aktifkan ADB modem lewat WebUI, reboot ke normal/fastboot/EDL, log otomatis

> ⚠️ **PERINGATAN**: Flash modem berisiko (brick). Selalu **backup** dulu (menu 6). Segala risiko ditanggung pengguna.

---

## 1. Yang dibutuhkan
- HP Android yang mendukung **OTG**
- Kabel/converter **OTG** + kabel USB modem
- Aplikasi **Termux** dan **Termux:API** dari **F-Droid** (versi Play Store tidak didukung)
- Modem ZTE MF90 (baterai terisi > 50%)
- File firmware MF90 (dan **loader firehose** jika pakai EDL)

## 2. Instalasi
```bash
pkg install -y git
git clone https://github.com/vpn-nusantara/FLASH-ZTE-MF90.git
cd FLASH-ZTE-MF90
bash install.sh
```
Installer memasang: `termux-api`, `termux-adb` + `termux-fastboot` (ADB/Fastboot via OTG tanpa root), tool `edl` (bkerler), alat ekstrak, dan perintah `mf90`.

Izinkan akses penyimpanan saat diminta (`termux-setup-storage`).

## 3. Menjalankan
```bash
mf90
```
Saat modem dicolok via OTG, Android akan menanyakan izin USB untuk Termux:API → pilih **Izinkan/OK**.

### Menu
| No | Menu | Fungsi |
|----|------|--------|
| 1 | Cek koneksi | Daftar USB OTG, `adb devices`, `fastboot devices` |
| 2 | Aktifkan ADB | Kirim `USB_MODE_SWITCH usb_mode=6` ke WebUI `192.168.0.1` |
| 3 | Siapkan firmware | Salin folder / download URL / ekstrak arsip ke `~/mf90/firmware` |
| 4 | Flash Fastboot | Deteksi file otomatis → `fastboot flash <partisi> <file>` |
| 5 | Flash EDL | `rawprogram*.xml` (qfil), per-partisi, manual, printgpt |
| 6 | Backup EDL | Backup semua partisi ke `~/mf90/backup/` |
| 7 | Unlock all operator | Cek status, NCK via WebUI, NCK via AT (ADB), AT manual |
| 8 | Reboot | Normal / Fastboot / EDL |
| 9 | Lock band | Cek band & sinyal, lock band LTE, buka lock, mode 4G/3G/2G, pantau sinyal live |
| 10 | Ganti Web UI | Deteksi, backup, pasang Web UI baru, restore, ganti judul |
| 11 | Penyimpanan cloud | Upload/unduh/hapus backup EDL, backup Web UI, log, firmware, Web UI |

## 4. Langkah flash via FASTBOOT (disarankan)
1. Sambungkan HP ke **WiFi modem**, jalankan `mf90` → menu **2** (aktifkan ADB). Masukkan password admin WebUI (default `admin`).
2. Colok modem ke HP via **OTG** → menu **1**, pastikan modem muncul di `adb devices`.
3. Menu **3** → siapkan firmware (folder / link / ekstrak arsip).
4. Menu **4** → script otomatis `adb reboot bootloader`, menampilkan rencana flash, ketik **YA**.
5. Tunggu selesai, modem reboot otomatis.

Pemetaan nama file → partisi otomatis:

| File | Partisi |
|------|---------|
| `appsboot.mbn` / `aboot*` | aboot |
| `*boot*.img` | boot |
| `*recovery*.img` | recovery |
| `NON-HLOS.bin` / `modem*` / `*amss*` | modem |
| `rpm.mbn` | rpm |
| `tz.mbn` | tz |
| `*sysfs*.yaffs2` / `system*` / `*rootfs*` | system |
| `sbl1.mbn` (opsional, berisiko) | sbl |

## 5. Langkah flash via EDL (9008)
Untuk modem **mati total / bootloop**.
1. Taruh firmware + **loader firehose** (`prog_nand_firehose_9x25.mbn` / `*firehose*.mbn`) di `~/mf90/firmware` (menu 3).
2. Masuk mode EDL: menu **8 → EDL**, atau manual (test point / kombinasi tombol) hingga USB terbaca **`05c6:9008`** (cek menu 1).
3. Menu **6** → **backup** dulu.
4. Menu **5** → pilih flash otomatis (rawprogram xml) atau per-partisi.

> Catatan: EDL memakai `termux-usb -E` (variabel `TERMUX_USB_FD`) agar libusb jalan tanpa root. Pastikan `libusb` Termux versi terbaru (`pkg upgrade`). Loader harus cocok dengan chipset MF90; tanpa loader yang benar, EDL tidak bisa jalan.

## 6. Unlock all operator
Menu **7**:
1. **Cek status** – bila `modem_main_state = modem_imsi_waitnck`, modem terkunci operator.
2. **NCK via WebUI** – masukkan kode NCK 16 digit (dari penyedia jasa unlock berdasarkan IMEI).
3. **NCK via AT** – kirim `AT+ZNCK="kode"` lewat ADB ke port AT (`/dev/smd11` default; coba `/dev/smd8`, `/dev/smd7`, `/dev/smd0`).
4. **Flash firmware debrand / open-line** – firmware tanpa kunci operator via Fastboot.

> ⚠️ Jangan salah masukkan NCK berkali-kali — modem bisa terkunci permanen. Cek sisa percobaan (`unlock_nck_time`) terlebih dahulu.

## 7. Lock band (menu 9)
HP cukup terhubung ke **WiFi modem** (tidak perlu OTG). Masukkan password admin WebUI saat diminta.
1. **Cek band & sinyal** – tampilkan `lte_band`, RSRP, RSRQ, SINR, Cell ID, PCI.
2. **Lock band LTE** – ketik band, contoh `3` atau `1+3+40`. Script mengubahnya jadi mask hex (Band N = 2^(N-1)), lalu mengirim `BAND_SELECT` dan `SET_NETWORK_BAND_LOCK`.
3. **Buka lock** – kembali ke semua band.
4. **Mode jaringan** – 4G only / 3G only / 2G only / auto / 4G+3G.
5. **Pantau sinyal live** – refresh tiap 3 detik, `Ctrl+C` untuk berhenti.
6. **AT manual** – untuk firmware yang lock band-nya hanya lewat AT command.

Band LTE umum di Indonesia: **1 (2100), 3 (1800), 5 (850), 8 (900), 40 (2300)**.

> Token keamanan `AD` dihitung otomatis untuk firmware yang membutuhkannya. Jika hasilnya `failure`, firmware MF90 Anda mungkin tidak mendukung lock band lewat WebUI → coba AT manual atau flash firmware lain.

## 8. Ganti Web UI (menu 10)
Butuh **ADB aktif** (menu 2) dan modem terhubung via **OTG** (cek menu 1).
1. **Deteksi folder Web UI** – script mencari `index.html` di `/etc_ro/web`, `/usr/zte_web/web`, dll. Bisa diisi manual.
2. **Backup Web UI asli** – disimpan ke `~/mf90/webui/backup/*.tar`. **Wajib sebelum mengganti.**
3. **Pasang Web UI baru** – dari folder HP, link download, atau ekstrak arsip. Harus ada `index.html`. Script backup otomatis, remount read-write, mengganti file, lalu reboot.
4. **Restore** – kembalikan Web UI dari backup.
5. **Ganti judul** – ubah `<title>` halaman Web UI.

> Jika muncul pesan *read-only*, partisi Web UI di firmware Anda tidak bisa ditulis; pakai firmware yang Web UI-nya bisa diubah. Setelah mengganti, hapus cache browser lalu buka `http://192.168.0.1`.

## 9. Penyimpanan cloud (menu 11)
Simpan file secara online lalu unduh lagi dari HP mana pun. Tersedia juga halaman web untuk melihat dan mengunduh file.

| Kategori | Default | Siapa yang bisa unduh |
|----------|---------|-----------------------|
| Firmware, Web UI | Publik | Siapa saja yang pakai script / buka halaman web |
| Backup Web UI, Backup EDL, Log | Privat | Hanya owner (pakai kode akses) |

Upload, hapus, dan ubah publik/privat **hanya bisa dengan kode akses owner**.

Langkah:
1. Menu **11 → 1**: isi alamat server (default sudah terisi) dan kode akses owner. Kosongkan kode jika hanya ingin mengunduh file publik.
2. Menu **11 → 2**: upload backup EDL terbaru (otomatis dikompres), backup Web UI terbaru, log, atau file firmware/Web UI.
3. Menu **11 → 3/4**: lihat daftar & unduh. Firmware yang diunduh bisa langsung diekstrak ke folder firmware.
4. Menu **11 → 5**: hapus file.

Halaman web: buka alamat server di browser → tekan **Kode akses** untuk mode owner (unggah, hapus, ubah publik/privat).

Pengaturan disimpan di `~/mf90/cloud.conf`.

## 10. Troubleshooting
| Masalah | Solusi |
|---------|--------|
| USB tidak terdeteksi | Cek OTG aktif di setelan HP, ganti kabel, pastikan Termux:API terpasang |
| `adb devices` kosong | Ulangi menu 2, cabut-colok modem |
| Fastboot tidak muncul | Menu 8 → Fastboot, tunggu 10–20 detik |
| EDL `No device` | Pastikan `05c6:9008`, `pkg upgrade libusb`, ulangi izin USB |
| `.rar` gagal ekstrak | `pkg install unrar` atau gunakan `7z` |

Log tersimpan di `~/mf90/mf90.log`.

## Lisensi
MIT — gunakan dengan bijak dan tanggung jawab sendiri.
