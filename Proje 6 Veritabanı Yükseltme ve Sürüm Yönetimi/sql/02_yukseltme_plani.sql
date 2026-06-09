-- =============================================================
-- PROJE 6 — Veritabanı Yükseltme ve Sürüm Yönetimi
-- Adım 2: Yükseltme Planı — v1.0.0 → v2.0.0
-- Platform: PostgreSQL 16
-- Veritabanı: demo (bookings şeması)
-- =============================================================

SET search_path TO bookings;

-- ─────────────────────────────────────────────────────────────
-- SORGU 1: Yükseltme öncesi baseline — tickets tablosu yapısı
-- ─────────────────────────────────────────────────────────────
SELECT
    column_name  AS kolon,
    data_type    AS tip,
    is_nullable  AS bos_olabilir,
    column_default AS varsayilan
FROM information_schema.columns
WHERE table_schema = 'bookings'
  AND table_name   = 'tickets'
ORDER BY ordinal_position;


-- ─────────────────────────────────────────────────────────────
-- SORGU 2: v2.0.0 — tickets tablosuna yeni kolonlar ekle
-- ─────────────────────────────────────────────────────────────
BEGIN;

ALTER TABLE bookings.tickets
    ADD COLUMN ucus_puani   INTEGER DEFAULT 0,
    ADD COLUMN uye_seviyesi TEXT    DEFAULT 'STANDART'
        CHECK (uye_seviyesi IN ('STANDART', 'SILVER', 'GOLD', 'PLATINUM'));

COMMIT;

-- Değişikliği doğrula
SELECT column_name, data_type, column_default
FROM information_schema.columns
WHERE table_schema = 'bookings'
  AND table_name   = 'tickets'
  AND column_name IN ('ucus_puani', 'uye_seviyesi');


-- ─────────────────────────────────────────────────────────────
-- SORGU 3: v2.0.0 — sadakat_programi tablosunu oluştur
-- ─────────────────────────────────────────────────────────────
BEGIN;

CREATE TABLE bookings.sadakat_programi (
    program_id      SERIAL PRIMARY KEY,
    ticket_no       CHAR(13)  REFERENCES bookings.tickets(ticket_no),
    toplam_puan     INTEGER   DEFAULT 0,
    seviye          TEXT      DEFAULT 'STANDART'
        CHECK (seviye IN ('STANDART', 'SILVER', 'GOLD', 'PLATINUM')),
    kayit_tarihi    DATE      DEFAULT CURRENT_DATE,
    son_ucus_tarihi TIMESTAMP,
    aktif_mi        BOOLEAN   DEFAULT TRUE
);

COMMIT;


-- ─────────────────────────────────────────────────────────────
-- SORGU 4: Örnek veri ekle — seviye dağılımını göster
-- ─────────────────────────────────────────────────────────────
INSERT INTO bookings.sadakat_programi
    (ticket_no, toplam_puan, seviye, son_ucus_tarihi)
SELECT
    t.ticket_no,
    (RANDOM() * 50000)::INTEGER AS toplam_puan,
    CASE
        WHEN RANDOM() < 0.60 THEN 'STANDART'
        WHEN RANDOM() < 0.85 THEN 'SILVER'
        WHEN RANDOM() < 0.95 THEN 'GOLD'
        ELSE                      'PLATINUM'
    END AS seviye,
    NOW() - (RANDOM() * 365 || ' days')::INTERVAL AS son_ucus_tarihi
FROM bookings.tickets t
LIMIT 10000;

-- İstatistikleri güncelle (EXPLAIN'de indeks görünsün diye)
ANALYZE bookings.sadakat_programi;

SELECT COUNT(*) AS kayit_sayisi, seviye
FROM bookings.sadakat_programi
GROUP BY seviye
ORDER BY seviye;


-- ─────────────────────────────────────────────────────────────
-- SORGU 5: v2.0.0 — flights tablosuna gecikme kolonları ekle
-- ─────────────────────────────────────────────────────────────
BEGIN;

ALTER TABLE bookings.flights
    ADD COLUMN beklenen_gecikme_dk INTEGER DEFAULT 0,
    ADD COLUMN iptal_nedeni        TEXT;

COMMIT;

-- Gecikmiş ve kalkmış uçuşlara örnek gecikme süresi ekle
UPDATE bookings.flights
SET beklenen_gecikme_dk = (RANDOM() * 120)::INTEGER
WHERE status IN ('Delayed', 'Departed')
  AND scheduled_departure > '2017-01-01';

SELECT
    status,
    COUNT(*)                           AS ucus_sayisi,
    AVG(beklenen_gecikme_dk)::INTEGER  AS ort_gecikme_dk
FROM bookings.flights
WHERE beklenen_gecikme_dk > 0
GROUP BY status
ORDER BY ort_gecikme_dk DESC;


-- ─────────────────────────────────────────────────────────────
-- SORGU 6: v2.0.0 — gecikme_istatistikleri view'ı oluştur
-- ─────────────────────────────────────────────────────────────
CREATE VIEW bookings.gecikme_istatistikleri AS
SELECT
    f.departure_airport                                                AS kalkis,
    f.arrival_airport                                                  AS varis,
    COUNT(*)                                                           AS toplam_ucus,
    SUM(CASE WHEN f.status = 'Delayed' THEN 1 ELSE 0 END)             AS geciken,
    ROUND(
        100.0 * SUM(CASE WHEN f.status = 'Delayed' THEN 1 ELSE 0 END)
        / COUNT(*), 2
    )                                                                  AS gecikme_orani_yuzde,
    AVG(f.beklenen_gecikme_dk)::INTEGER                                AS ort_gecikme_dk
FROM bookings.flights f
GROUP BY f.departure_airport, f.arrival_airport
HAVING COUNT(*) > 5
ORDER BY gecikme_orani_yuzde DESC;

SELECT * FROM bookings.gecikme_istatistikleri LIMIT 10;


-- ─────────────────────────────────────────────────────────────
-- SORGU 7: v2.0.0 — performans indeksleri ekle
-- ─────────────────────────────────────────────────────────────
CREATE INDEX idx_sadakat_seviye
    ON bookings.sadakat_programi (seviye, aktif_mi);

CREATE INDEX idx_sadakat_ticket
    ON bookings.sadakat_programi (ticket_no);

CREATE INDEX idx_flights_gecikme
    ON bookings.flights (beklenen_gecikme_dk)
    WHERE beklenen_gecikme_dk > 0;

-- Oluşturulan yeni indeksleri listele
SELECT indexname AS indeks_adi, tablename AS tablo, indexdef AS tanim
FROM pg_indexes
WHERE schemaname = 'bookings'
  AND indexname IN ('idx_sadakat_seviye', 'idx_sadakat_ticket', 'idx_flights_gecikme')
ORDER BY tablename;


-- ─────────────────────────────────────────────────────────────
-- SORGU 8: v2.0.0 sürüm kaydını ekle — geçmişi göster
-- ─────────────────────────────────────────────────────────────
INSERT INTO schema_versiyon (versiyon_no, aciklama, degisiklik_tipi, sql_betigi)
VALUES (
    '2.0.0',
    'tickets: ucus_puani + uye_seviyesi; sadakat_programi tablosu; flights: beklenen_gecikme_dk + iptal_nedeni; gecikme_istatistikleri view; 3 indeks',
    'UPGRADE',
    '02_yukseltme_plani.sql'
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
