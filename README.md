# Lucifer v2.86 World Scanner & Plant Checker

Skrip otomasi untuk Nuron's Lucifer (Growtopia Bot) v2.86 yang bertugas keliling world untuk:
1. Memeriksa apakah world **Nuked / Inaccessible** berdasarkan sinyal resmi server.
2. Memeriksa keberadaan **pohon siap panen** (`canHarvest`) dan **bibit bertumbuh**.
3. Mencatat seluruh hasil pemindaian secara rapi ke file `.txt` di dalam folder `output/`.

---

## Fitur Utama

- **Deteksi Ketat World Nuked / Inaccessible**: Memompa event server (`listenEvents`) untuk menangkap pesan `is inaccessible` atau `nuked`. Tidak menganggap lag / timeout sebagai nuke.
- **Deteksi Pohon & Bibit Tanpa False-Positive**: Menggunakan API resmi `tile:canHarvest()` dan filter bibit ber-ID ganjil dengan timer pertumbuhan `extra.growth`.
- **Anti False-Empty**: Jika bot disconnect atau data tile gagal dimuat, status dicatat sebagai `SCAN_FAILED` (bukan kosong).
- **Struktur Folder Output Khusus**:
  - `output/worlds_nuked.txt`: World yang terkena NUKED / Inaccessible.
  - `output/worlds_has_plant.txt`: World yang ada tanaman (lengkap dengan jumlah siap panen & tumbuh).
  - `output/worlds_empty.txt`: World yang terkonfirmasi bersih / 0 tanaman.
  - `output/worlds_failed.txt`: World yang gagal dimasuki / gagal discan (lag jaringan / offline).
  - `output/worlds_scan_report.txt`: Rekap lengkap seluruh riwayat scan dengan timestamp.
- **Dukungan File Daftar World**: Membaca otomatis dari `world_list.txt` (format `WORLD` atau `WORLD|DOOR`).
- **Monitoring Discord Webhook**: Opsional untuk laporan realtime ke server Discord.

---

## Cara Penggunaan

1. Siapkan daftar world di file `world_list.txt` (gunakan `world_list.example.txt` sebagai referensi).
2. Sesuaikan konfigurasi di bagian atas `world_checker.lua` jika diperlukan:
   - `TARGET_SEED_ID`: `0` untuk semua jenis tanaman, atau isi ID spesifik (misal `4585` untuk Pepper Tree).
   - `READY_ONLY`: `true` jika hanya ingin mencari pohon yang siap panen.
   - `LOOP_MODE`: `true` untuk keliling berulang kali secara terus-menerus.
3. Jalankan `world_checker.lua` di executor / console Lucifer bot.
4. Cek hasil laporan di folder `output/`.

---
*Pengembang: Tim Salsa & Anna (@anna) untuk Bos Anas (canas1257)*
