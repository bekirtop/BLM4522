-- =============================================================
-- PROJE 6 — Veritabanı Yükseltme ve Sürüm Yönetimi
-- Adım 3: Test ve Geri Dönüş Planı
-- Platform: PostgreSQL 16
-- Veritabanı: demo (bookings şeması)
-- =============================================================

SET search_path TO bookings;

-- =============================================================
-- BÖLÜM A — YÜKSELTME SONRASI TEST PLANI
-- =============================================================

-- ─────────────────────────────────────────────────────────────
-- SORGU 1: Şema doğrulama — tüm beklenen nesneler var mı?
-- ─────────────────────────────────────────────────────────────
SELECT
    'Tablo: ' || table_name        AS nesne,
    'MEVCUT'                       AS durum
FROM information_schema.tables
WHERE table_schema = 'bookings'
  AND table_type   = 'BASE TABLE'
  AND table_name IN (
      'flights', 'tickets', 'ticket_flights',
      'bookings', 'seats', 'airports_data',
      'aircrafts_data', 'sadakat_programi'
  )

UNION ALL

SELECT
    'View: ' || table_name,
    'MEVCUT'
FROM information_schema.views
WHERE table_schema = 'bookings'
  AND table_name   = 'gecikme_istatistikleri'

UNION ALL

SELECT
    'Kolon: tickets.' || column_name,
    'MEVCUT'
FROM information_schema.columns
WHERE table_schema = 'bookings'
  AND table_name   = 'tickets'
  AND column_name IN ('ucus_puani', 'uye_seviyesi')

UNION ALL

SELECT
    'Kolon: flights.' || column_name,
    'MEVCUT'
FROM information_schema.columns
WHERE table_schema = 'bookings'
  AND table_name   = 'flights'
  AND column_name IN ('beklenen_gecikme_dk', 'iptal_nedeni')

ORDER BY nesne;


-- ─────────────────────────────────────────────────────────────
-- SORGU 2: Veri bütünlüğü testi — foreign key referansları sağlam mı?
-- ─────────────────────────────────────────────────────────────
-- sadakat_programi tablosundaki ticket_no'ların tickets'ta karşılığı var mı?
SELECT
    COUNT(*) AS toplam_kayit,
    COUNT(t.ticket_no) AS eslesme_sayisi,
    COUNT(*) - COUNT(t.ticket_no) AS kopuk_referans
FROM bookings.sadakat_programi sp
LEFT JOIN bookings.tickets t ON sp.ticket_no = t.ticket_no;


-- ─────────────────────────────────────────────────────────────
-- SORGU 3: Kısıt testi — CHECK constraint çalışıyor mu?
-- ─────────────────────────────────────────────────────────────
-- Geçerli değerle test (başarılı olmalı)
DO $$
BEGIN
    INSERT INTO bookings.sadakat_programi (ticket_no, seviye)
    SELECT ticket_no, 'GOLD'
    FROM bookings.tickets LIMIT 1
    ON CONFLICT DO NOTHING;
    RAISE NOTICE 'Geçerli seviye eklendi: BASARILI';
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Geçerli ekleme hatası: %', SQLERRM;
END;
$$;

-- Geçersiz değerle test (hata vermeli)
DO $$
BEGIN
    INSERT INTO bookings.sadakat_programi (ticket_no, seviye)
    SELECT ticket_no, 'BRONZE'   -- geçersiz seviye
    FROM bookings.tickets LIMIT 1;
    RAISE NOTICE 'BRONZE kabul edildi — CHECK kısıtı çalışmıyor!';
EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'CHECK kısıtı doğru çalışıyor: BRONZE reddedildi — BASARILI';
END;
$$;


-- ─────────────────────────────────────────────────────────────
-- SORGU 4: Performans testi — yeni indeksler kullanılıyor mu?
-- ─────────────────────────────────────────────────────────────
EXPLAIN (ANALYZE, FORMAT TEXT)
SELECT ticket_no, seviye, toplam_puan
FROM bookings.sadakat_programi
WHERE seviye = 'GOLD'
  AND aktif_mi = TRUE;


-- ─────────────────────────────────────────────────────────────
-- SORGU 5: View testi — gecikme_istatistikleri doğru çalışıyor mu?
-- ─────────────────────────────────────────────────────────────
SELECT
    kalkis_havaalani,
    varis_havaalani,
    toplam_ucus,
    geciken_ucus,
    gecikme_orani_yuzde,
    ort_gecikme_dk
FROM bookings.gecikme_istatistikleri
ORDER BY gecikme_orani_yuzde DESC
LIMIT 5;


-- ─────────────────────────────────────────────────────────────
-- SORGU 6: DDL log testi — yükseltme sürecinde yapılan değişiklikler
-- ─────────────────────────────────────────────────────────────
SELECT
    log_id,
    komut_tipi,
    nesne_tipi,
    nesne_adi,
    TO_CHAR(zaman, 'DD.MM.YYYY HH24:MI:SS') AS degisiklik_zamani
FROM bookings.ddl_degisiklik_log
ORDER BY zaman DESC;


-- =============================================================
-- BÖLÜM B — GERİ DÖNÜŞ (ROLLBACK) PLANI
-- v2.0.0 → v1.1.0 ve v1.1.0 → v1.0.0
-- =============================================================

-- ─────────────────────────────────────────────────────────────
-- SORGU 7: ROLLBACK v2.0.0 → v1.1.0
-- Geri alınacaklar: flights kolonları, view, indeksler
-- ─────────────────────────────────────────────────────────────
BEGIN;

-- İndeksleri kaldır
DROP INDEX IF EXISTS bookings.idx_flights_gecikme;

-- View'ı kaldır
DROP VIEW IF EXISTS bookings.gecikme_istatistikleri;

-- flights tablosuna eklenen kolonları kaldır
ALTER TABLE bookings.flights
    DROP COLUMN IF EXISTS beklenen_gecikme_dk,
    DROP COLUMN IF EXISTS iptal_nedeni;

COMMIT;

-- Geri dönüşü doğrula
SELECT column_name
FROM information_schema.columns
WHERE table_schema = 'bookings'
  AND table_name   = 'flights'
  AND column_name IN ('beklenen_gecikme_dk', 'iptal_nedeni');
-- Sonuç boş olmalı

-- Rollback kaydını sürüm tablosuna ekle
INSERT INTO schema_versiyon (versiyon_no, aciklama, degisiklik_tipi, sql_betigi)
VALUES (
    '1.1.0',
    'v2.0.0 → v1.1.0 geri dönüşü: flights kolonları, gecikme_istatistikleri view ve idx_flights_gecikme kaldırıldı',
    'ROLLBACK',
    '03_test_geri_donus.sql — SORGU 7'
);


-- ─────────────────────────────────────────────────────────────
-- SORGU 8: ROLLBACK v1.1.0 → v1.0.0
-- Geri alınacaklar: sadakat_programi tablosu, tickets kolonları, indeksler
-- ─────────────────────────────────────────────────────────────
BEGIN;

-- Sadakat indekslerini kaldır
DROP INDEX IF EXISTS bookings.idx_sadakat_seviye;
DROP INDEX IF EXISTS bookings.idx_sadakat_ticket;

-- sadakat_programi tablosunu kaldır
DROP TABLE IF EXISTS bookings.sadakat_programi;

-- tickets tablosundan eklenen kolonları kaldır
ALTER TABLE bookings.tickets
    DROP COLUMN IF EXISTS ucus_puani,
    DROP COLUMN IF EXISTS uye_seviyesi;

COMMIT;

-- Geri dönüşü doğrula
SELECT column_name
FROM information_schema.columns
WHERE table_schema = 'bookings'
  AND table_name   = 'tickets'
  AND column_name IN ('ucus_puani', 'uye_seviyesi');
-- Sonuç boş olmalı

-- Rollback kaydını sürüm tablosuna ekle
INSERT INTO schema_versiyon (versiyon_no, aciklama, degisiklik_tipi, sql_betigi)
VALUES (
    '1.0.0',
    'v1.1.0 → v1.0.0 geri dönüşü: sadakat_programi tablosu ve tickets kolonları (ucus_puani, uye_seviyesi) kaldırıldı',
    'ROLLBACK',
    '03_test_geri_donus.sql — SORGU 8'
);


-- ─────────────────────────────────────────────────────────────
-- SORGU 9: Tam sürüm geçmişi — yükseltme ve geri dönüş dahil
-- ─────────────────────────────────────────────────────────────
SELECT
    id,
    versiyon_no                             AS versiyon,
    degisiklik_tipi,
    uygulayan,
    TO_CHAR(uygulama_tarihi, 'DD.MM.YYYY HH24:MI') AS tarih,
    aciklama
FROM schema_versiyon
ORDER BY id;


-- ─────────────────────────────────────────────────────────────
-- SORGU 10: DDL event trigger'ı kaldır (proje sonunda temizlik)
-- ─────────────────────────────────────────────────────────────
DROP EVENT TRIGGER IF EXISTS ddl_degisiklik_trigger;
DROP FUNCTION IF EXISTS ddl_degisiklik_yakala();
DROP TABLE IF EXISTS ddl_degisiklik_log;

-- schema_versiyon tablosu kalıcı olarak bırakılabilir
-- istersen kaldırmak için:
-- DROP TABLE IF EXISTS schema_versiyon;

SELECT 'Temizlik tamamlandı — DDL trigger ve log tablosu kaldırıldı' AS sonuc;
