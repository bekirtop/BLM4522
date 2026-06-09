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
-- SORGU 1: Şema doğrulama — beklenen nesneler mevcut mu?
-- ─────────────────────────────────────────────────────────────
SELECT 'Tablo: sadakat_programi'    AS nesne, 'MEVCUT' AS durum
WHERE EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'bookings' AND table_name = 'sadakat_programi'
)
UNION ALL
SELECT 'View: gecikme_istatistikleri', 'MEVCUT'
WHERE EXISTS (
    SELECT 1 FROM information_schema.views
    WHERE table_schema = 'bookings' AND table_name = 'gecikme_istatistikleri'
)
UNION ALL
SELECT 'Kolon: tickets.ucus_puani', 'MEVCUT'
WHERE EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'bookings' AND table_name = 'tickets' AND column_name = 'ucus_puani'
)
UNION ALL
SELECT 'Kolon: tickets.uye_seviyesi', 'MEVCUT'
WHERE EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'bookings' AND table_name = 'tickets' AND column_name = 'uye_seviyesi'
)
UNION ALL
SELECT 'Kolon: flights.beklenen_gecikme_dk', 'MEVCUT'
WHERE EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'bookings' AND table_name = 'flights' AND column_name = 'beklenen_gecikme_dk'
)
UNION ALL
SELECT 'Indeks: idx_sadakat_seviye', 'MEVCUT'
WHERE EXISTS (
    SELECT 1 FROM pg_indexes
    WHERE schemaname = 'bookings' AND indexname = 'idx_sadakat_seviye'
)
ORDER BY nesne;


-- ─────────────────────────────────────────────────────────────
-- SORGU 2: Veri bütünlüğü — kopuk foreign key var mı?
-- ─────────────────────────────────────────────────────────────
SELECT
    COUNT(*)                          AS toplam_kayit,
    COUNT(t.ticket_no)                AS eslesen,
    COUNT(*) - COUNT(t.ticket_no)     AS kopuk_referans
FROM bookings.sadakat_programi sp
LEFT JOIN bookings.tickets t ON sp.ticket_no = t.ticket_no;


-- ─────────────────────────────────────────────────────────────
-- SORGU 3: Kısıt testi — geçersiz seviye reddediliyor mu?
-- ─────────────────────────────────────────────────────────────
DO $$
BEGIN
    INSERT INTO bookings.sadakat_programi (ticket_no, seviye)
    SELECT ticket_no, 'BRONZE' FROM bookings.tickets LIMIT 1;
    RAISE NOTICE 'HATA: BRONZE kabul edildi — CHECK kısıtı çalışmıyor!';
EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'BASARILI: CHECK kısıtı doğru çalışıyor — BRONZE reddedildi';
END;
$$;


-- ─────────────────────────────────────────────────────────────
-- SORGU 4: Performans testi — indeks kullanılıyor mu?
-- ─────────────────────────────────────────────────────────────
EXPLAIN (ANALYZE, COSTS OFF, FORMAT TEXT)
SELECT ticket_no, seviye, toplam_puan
FROM bookings.sadakat_programi
WHERE seviye = 'GOLD'
  AND aktif_mi = TRUE;


-- ─────────────────────────────────────────────────────────────
-- SORGU 5: View testi — gecikme istatistikleri doğru mu?
-- ─────────────────────────────────────────────────────────────
SELECT kalkis, varis, toplam_ucus, geciken, gecikme_orani_yuzde, ort_gecikme_dk
FROM bookings.gecikme_istatistikleri
LIMIT 5;


-- ─────────────────────────────────────────────────────────────
-- SORGU 6: DDL log — yükseltme sırasında yapılan şema değişiklikleri
-- ─────────────────────────────────────────────────────────────
SELECT
    log_id,
    komut_tipi,
    nesne_tipi,
    nesne_adi,
    TO_CHAR(zaman, 'HH24:MI:SS') AS saat
FROM ddl_degisiklik_log
ORDER BY zaman;


-- =============================================================
-- BÖLÜM B — GERİ DÖNÜŞ PLANI (v2.0.0 → v1.0.0)
-- =============================================================

-- ─────────────────────────────────────────────────────────────
-- SORGU 7: ROLLBACK — tüm v2.0.0 değişikliklerini geri al
-- ─────────────────────────────────────────────────────────────
BEGIN;

-- Önce bağımlı nesneler (indeksler ve view)
DROP INDEX IF EXISTS bookings.idx_flights_gecikme;
DROP INDEX IF EXISTS bookings.idx_sadakat_seviye;
DROP INDEX IF EXISTS bookings.idx_sadakat_ticket;
DROP VIEW  IF EXISTS bookings.gecikme_istatistikleri;

-- Sonra foreign key içeren tablo
DROP TABLE IF EXISTS bookings.sadakat_programi;

-- Son olarak kolonlar
ALTER TABLE bookings.flights
    DROP COLUMN IF EXISTS beklenen_gecikme_dk,
    DROP COLUMN IF EXISTS iptal_nedeni;

ALTER TABLE bookings.tickets
    DROP COLUMN IF EXISTS ucus_puani,
    DROP COLUMN IF EXISTS uye_seviyesi;

COMMIT;


-- ─────────────────────────────────────────────────────────────
-- SORGU 8: Rollback doğrulama — v2.0.0 nesneleri silindi mi?
-- ─────────────────────────────────────────────────────────────
SELECT 'sadakat_programi tablosu' AS nesne,
       CASE WHEN EXISTS (
           SELECT 1 FROM information_schema.tables
           WHERE table_schema = 'bookings' AND table_name = 'sadakat_programi'
       ) THEN 'HALA MEVCUT' ELSE 'SILINDI' END AS durum
UNION ALL
SELECT 'tickets.ucus_puani kolonu',
       CASE WHEN EXISTS (
           SELECT 1 FROM information_schema.columns
           WHERE table_schema = 'bookings' AND table_name = 'tickets' AND column_name = 'ucus_puani'
       ) THEN 'HALA MEVCUT' ELSE 'SILINDI' END
UNION ALL
SELECT 'flights.beklenen_gecikme_dk kolonu',
       CASE WHEN EXISTS (
           SELECT 1 FROM information_schema.columns
           WHERE table_schema = 'bookings' AND table_name = 'flights' AND column_name = 'beklenen_gecikme_dk'
       ) THEN 'HALA MEVCUT' ELSE 'SILINDI' END
ORDER BY nesne;


-- ─────────────────────────────────────────────────────────────
-- SORGU 9: Rollback kaydı — tam sürüm geçmişi
-- ─────────────────────────────────────────────────────────────
INSERT INTO schema_versiyon (versiyon_no, aciklama, degisiklik_tipi, sql_betigi)
VALUES (
    '1.0.0',
    'v2.0.0 geri alındı — tüm yeni nesneler kaldırıldı, başlangıç haline dönüldü',
    'ROLLBACK',
    '03_test_geri_donus.sql'
);

SELECT
    id,
    versiyon_no,
    degisiklik_tipi,
    uygulayan,
    TO_CHAR(uygulama_tarihi, 'DD.MM.YYYY HH24:MI') AS tarih,
    aciklama
FROM schema_versiyon
ORDER BY id;


-- ─────────────────────────────────────────────────────────────
-- SORGU 10: Temizlik — DDL trigger kaldır
-- ─────────────────────────────────────────────────────────────
DROP EVENT TRIGGER IF EXISTS ddl_degisiklik_trigger;
DROP FUNCTION  IF EXISTS ddl_degisiklik_yakala();
DROP TABLE     IF EXISTS ddl_degisiklik_log;

SELECT 'Proje 6 tamamlandı — DDL trigger ve log tablosu kaldırıldı.' AS sonuc;
