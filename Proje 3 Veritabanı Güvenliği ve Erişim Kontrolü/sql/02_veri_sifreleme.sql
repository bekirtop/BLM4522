-- ============================================================
-- PROJE 3 | ADIM 2: VERİ ŞİFRELEME
-- pgcrypto ile hassas verilerin şifrelenmesi
-- MSSQL'deki TDE (Transparent Data Encryption) muadili
-- ============================================================


-- ----------------------------------------------------------------
-- 1. pgcrypto eklentisini aktif et
-- ----------------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS pgcrypto;


-- ----------------------------------------------------------------
-- 2. Hassas veri tablosu oluştur
-- Yolcu kimlik ve iletişim bilgileri — şifreli saklanmalı
-- ----------------------------------------------------------------
DROP TABLE IF EXISTS guvenli_yolcu;

CREATE TABLE guvenli_yolcu (
    id              SERIAL PRIMARY KEY,
    ad_soyad        TEXT NOT NULL,
    tc_kimlik       BYTEA,          -- şifreli saklanır
    telefon         BYTEA,          -- şifreli saklanır
    email           TEXT,           -- düz metin (hassas değil)
    sifre_hash      TEXT,           -- hash ile saklanır (geri çevrilemez)
    kayit_tarihi    TIMESTAMP DEFAULT now()
);


-- ----------------------------------------------------------------
-- 3. Şifreli veri ekle
-- pgp_sym_encrypt: simetrik anahtar ile şifreler
-- Gerçek uygulamada anahtar ortam değişkeninden okunur
-- ----------------------------------------------------------------
INSERT INTO guvenli_yolcu (ad_soyad, tc_kimlik, telefon, email, sifre_hash)
VALUES (
    'Ahmet Yılmaz',
    pgp_sym_encrypt('12345678901', 'gizli_anahtar_2024'),
    pgp_sym_encrypt('05551234567', 'gizli_anahtar_2024'),
    'ahmet@email.com',
    crypt('sifre123', gen_salt('bf'))   -- bcrypt hash
);

INSERT INTO guvenli_yolcu (ad_soyad, tc_kimlik, telefon, email, sifre_hash)
VALUES (
    'Ayşe Kaya',
    pgp_sym_encrypt('98765432100', 'gizli_anahtar_2024'),
    pgp_sym_encrypt('05559876543', 'gizli_anahtar_2024'),
    'ayse@email.com',
    crypt('parola456', gen_salt('bf'))
);

INSERT INTO guvenli_yolcu (ad_soyad, tc_kimlik, telefon, email, sifre_hash)
VALUES (
    'Mehmet Demir',
    pgp_sym_encrypt('11122233344', 'gizli_anahtar_2024'),
    pgp_sym_encrypt('05341112233', 'gizli_anahtar_2024'),
    'mehmet@email.com',
    crypt('gizli789', gen_salt('bf'))
);


-- ----------------------------------------------------------------
-- 4. Ham veriyi göster — şifreli hali böyle görünür
-- Anahtarı bilmeden okunamaz
-- ----------------------------------------------------------------
SELECT id, ad_soyad, tc_kimlik, telefon, email, sifre_hash
FROM guvenli_yolcu;


-- ----------------------------------------------------------------
-- 5. Şifreyi çöz — anahtarla okunabilir hale getir
-- pgp_sym_decrypt: şifrelenmiş veriyi çözer
-- ----------------------------------------------------------------
SELECT
    id,
    ad_soyad,
    pgp_sym_decrypt(tc_kimlik, 'gizli_anahtar_2024') AS tc_kimlik_acik,
    pgp_sym_decrypt(telefon,   'gizli_anahtar_2024') AS telefon_acik,
    email
FROM guvenli_yolcu;


-- ----------------------------------------------------------------
-- 6. Yanlış anahtar ile çözmeye çalış → hata verir
-- ----------------------------------------------------------------
SELECT pgp_sym_decrypt(tc_kimlik, 'yanlis_anahtar')
FROM guvenli_yolcu
WHERE id = 1;


-- ----------------------------------------------------------------
-- 7. Şifre doğrulama — hash karşılaştırma
-- Doğru şifre true, yanlış şifre false döner
-- ----------------------------------------------------------------
SELECT
    ad_soyad,
    'sifre123'                                        AS girilen_sifre,
    (sifre_hash = crypt('sifre123', sifre_hash))      AS dogru_sifre,
    (sifre_hash = crypt('yanlis_sifre', sifre_hash))  AS yanlis_sifre
FROM guvenli_yolcu
WHERE ad_soyad = 'Ahmet Yılmaz';
