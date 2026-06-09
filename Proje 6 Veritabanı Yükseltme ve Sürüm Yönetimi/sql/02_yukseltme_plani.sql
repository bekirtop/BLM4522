-- =============================================================
-- PROJE 6 — Veritabanı Yükseltme ve Sürüm Yönetimi
-- Adım 2: Yükseltme Planı — v1.0.0 → v1.1.0 → v2.0.0
-- Platform: PostgreSQL 16
-- Veritabanı: demo (bookings şeması)
-- =============================================================

SET search_path TO bookings;

-- =============================================================
-- YÜKSELTME v1.0.0 → v1.1.0
-- Değişiklik: tickets tablosuna ucus_puani kolonu eklenir,
--             sadakat_programi tablosu oluşturulur
-- =============================================================

-- ─────────────────────────────────────────────────────────────
-- SORGU 1: v1.1.0 öncesi — tickets tablosunun mevcut yapısı
-- ─────────────────────────────────────────────────────────────
SELECT
    column_name    AS kolon,
    data_type      AS tip,
    is_nullable    AS bos_olabilir
FROM information_schema.columns
WHERE table_schema = 'bookings'
  AND table_name   = 'tickets'
ORDER BY ordinal_position;


-- ─────────────────────────────────────────────────────────────
-- SORGU 2: v1.1.0 YÜKSELTME — tickets tablosuna yeni kolon ekle
-- ─────────────────────────────────────────────────────────────
BEGIN;

ALTER TABLE bookings.tickets
    ADD COLUMN IF NOT EXISTS ucus_puani      INTEGER DEFAULT 0,
    ADD COLUMN IF NOT EXISTS uye_seviyesi    TEXT    DEFAULT 'STANDART'
        CHECK (uye_seviyesi IN ('STANDART', 'SILVER', 'GOLD', 'PLATINUM'));

COMMIT;

-- Değişikliği doğrula
SELECT column_name, data_type, column_default
FROM information_schema.columns
WHERE table_schema = 'bookings'
  AND table_name   = 'tickets'
  AND column_name IN ('ucus_puani', 'uye_seviyesi');


-- ─────────────────────────────────────────────────────────────
-- SORGU 3: v1.1.0 YÜKSELTME — sadakat_programi tablosunu oluştur
-- ─────────────────────────────────────────────────────────────
BEGIN;

DROP TABLE IF EXISTS bookings.sadakat_programi;

CREATE TABLE bookings.sadakat_programi (
    program_id      SERIAL PRIMARY KEY,
    ticket_no       CHAR(13)     REFERENCES bookings.tickets(ticket_no),
    toplam_puan     INTEGER      DEFAULT 0,
    seviye          TEXT         DEFAULT 'STANDART'
        CHECK (seviye IN ('STANDART', 'SILVER', 'GOLD', 'PLATINUM')),
    kayit_tarihi    DATE         DEFAULT CURRENT_DATE,
    son_ucus_tarihi TIMESTAMP,
    aktif_mi        BOOLEAN      DEFAULT TRUE
);

-- İlk 10000 bilet için sadakat kaydı oluştur (EXPLAIN testinde indeks görünmesi için yeterli hacim)
INSERT INTO bookings.sadakat_programi
    (ticket_no, toplam_puan, seviye, son_ucus_tarihi)
SELECT
    t.ticket_no,
    (RANDOM() * 50000)::INTEGER         AS toplam_puan,
    CASE
        WHEN RANDOM() < 0.6  THEN 'STANDART'
        WHEN RANDOM() < 0.85 THEN 'SILVER'
        WHEN RANDOM() < 0.95 THEN 'GOLD'
        ELSE                      'PLATINUM'
    END                                 AS seviye,
    NOW() - (RANDOM() * 365 || ' days')::INTERVAL AS son_ucus_tarihi
FROM bookings.tickets t
LIMIT 10000;

COMMIT;

SELECT COUNT(*) AS kayit_sayisi, seviye
FROM bookings.sadakat_programi
GROUP BY seviye
ORDER BY seviye;


-- ─────────────────────────────────────────────────────────────
-- SORGU 4: v1.1.0 sürüm kaydını ekle
-- ─────────────────────────────────────────────────────────────
INSERT INTO schema_versiyon (versiyon_no, aciklama, degisiklik_tipi, sql_betigi)
VALUES (
    '1.1.0',
    'tickets tablosuna ucus_puani ve uye_seviyesi kolonları eklendi; sadakat_programi tablosu oluşturuldu',
    'UPGRADE',
    '02_yukseltme_plani.sql — SORGU 2 & 3'
);

SELECT * FROM schema_versiyon ORDER BY id;


-- =============================================================
-- YÜKSELTME v1.1.0 → v2.0.0
-- Değişiklik: flights tablosuna yeni kolonlar,
--             gecikme_istatistikleri view'ı,
--             performans indeksleri
-- =============================================================

-- ─────────────────────────────────────────────────────────────
-- SORGU 5: v2.0.0 YÜKSELTME — flights tablosuna kolon ekle
-- ─────────────────────────────────────────────────────────────
BEGIN;

ALTER TABLE bookings.flights
    ADD COLUMN IF NOT EXISTS beklenen_gecikme_dk  INTEGER DEFAULT 0,
    ADD COLUMN IF NOT EXISTS iptal_nedeni          TEXT;

COMMIT;

-- Bazı uçuşlara örnek gecikme verisi ekle
UPDATE bookings.flights
SET beklenen_gecikme_dk = (RANDOM() * 120)::INTEGER
WHERE status IN ('Delayed', 'Departed')
  AND scheduled_departure > '2017-01-01';

SELECT
    status,
    COUNT(*)                              AS ucus_sayisi,
    AVG(beklenen_gecikme_dk)::INTEGER     AS ort_gecikme_dk
FROM bookings.flights
WHERE beklenen_gecikme_dk > 0
GROUP BY status
ORDER BY ort_gecikme_dk DESC;


-- ─────────────────────────────────────────────────────────────
-- SORGU 6: v2.0.0 YÜKSELTME — gecikme_istatistikleri view'ı oluştur
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE VIEW bookings.gecikme_istatistikleri AS
SELECT
    f.departure_airport                          AS kalkis_havaalani,
    f.arrival_airport                            AS varis_havaalani,
    COUNT(*)                                     AS toplam_ucus,
    SUM(CASE WHEN f.status = 'Delayed' THEN 1 ELSE 0 END)  AS geciken_ucus,
    ROUND(
        100.0 * SUM(CASE WHEN f.status = 'Delayed' THEN 1 ELSE 0 END)
        / COUNT(*), 2
    )                                            AS gecikme_orani_yuzde,
    AVG(f.beklenen_gecikme_dk)::INTEGER          AS ort_gecikme_dk
FROM bookings.flights f
GROUP BY f.departure_airport, f.arrival_airport
HAVING COUNT(*) > 5
ORDER BY gecikme_orani_yuzde DESC;

SELECT * FROM bookings.gecikme_istatistikleri LIMIT 10;


-- ─────────────────────────────────────────────────────────────
-- SORGU 7: v2.0.0 YÜKSELTME — yeni kolonlar için indeks ekle
-- ─────────────────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_flights_gecikme
    ON bookings.flights (beklenen_gecikme_dk)
    WHERE beklenen_gecikme_dk > 0;

-- Sadakat programı için indeks
CREATE INDEX IF NOT EXISTS idx_sadakat_seviye
    ON bookings.sadakat_programi (seviye, aktif_mi);

CREATE INDEX IF NOT EXISTS idx_sadakat_ticket
    ON bookings.sadakat_programi (ticket_no);

-- Oluşturulan indeksleri listele
SELECT
    indexname   AS indeks_adi,
    tablename   AS tablo,
    indexdef    AS tanim
FROM pg_indexes
WHERE schemaname = 'bookings'
  AND indexname IN ('idx_flights_gecikme', 'idx_sadakat_seviye', 'idx_sadakat_ticket')
ORDER BY tablename;


-- ─────────────────────────────────────────────────────────────
-- SORGU 8: v2.0.0 sürüm kaydını ekle — tüm geçmişi göster
-- ─────────────────────────────────────────────────────────────
INSERT INTO schema_versiyon (versiyon_no, aciklama, degisiklik_tipi, sql_betigi)
VALUES (
    '2.0.0',
    'flights tablosuna beklenen_gecikme_dk ve iptal_nedeni eklendi; gecikme_istatistikleri view''ı ve 3 yeni indeks oluşturuldu',
    'UPGRADE',
    '02_yukseltme_plani.sql — SORGU 5, 6, 7'
);

-- Tüm sürüm geçmişi
SELECT
    id,
    versiyon_no,
    degisiklik_tipi,
    uygulayan,
    uygulama_tarihi::TIMESTAMP(0) AS tarih,
    aciklama
FROM schema_versiyon
ORDER BY id;
