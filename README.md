Script Termux sudah bisa Anda unduh dalam satu file zip. 
Saya sudah mencoba mengunduh dan membukanya, dan keenam file lengkap.

#Cara 1 – Langsung di Termux (paling praktis):

pkg install -y curl unzip
curl -L -o FLASH-ZTE-MF90.zip https://zte-mf90-flash--0r42iomw.preview.emergentagent.com/api/toolkit.zip
unzip -o FLASH-ZTE-MF90.zip
cd FLASH-ZTE-MF90
bash install.sh
mf90

Cara 2 – Lewat browser HP:

Buka link ini: https://zte-mf90-flash--0r42iomw.preview.emergentagent.com/api/toolkit.zip
Atau buka halaman web lalu tekan tombol "Unduh script Termux (.zip)".
File masuk ke folder Download. Lalu jalankan di Termux:

termux-setup-storage
unzip -o /sdcard/Download/FLASH-ZTE-MF90.zip -d ~
cd ~/FLASH-ZTE-MF90 && bash install.sh

Isi zip: install.sh, mf90-flash.sh, README.md, serta folder lib/ (bandlock.sh, webui.sh, cloud.sh).
Link ini selalu memberi versi script terbaru. Link ini alamat preview, jadi bisa berhenti bekerja nanti. Supaya bisa diunduh terus, deploy aplikasinya atau simpan ke GitHub lewat tombol "Save to GitHub".
