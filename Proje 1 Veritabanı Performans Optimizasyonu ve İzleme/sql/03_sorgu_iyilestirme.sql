-- ============================================================
-- PROJE 1 | ADIM 3: SORGU İYİLEŞTİRME
-- Yavaş sorguları analiz edip daha hızlı versiyonlarını yazma.
-- ============================================================


-- ----------------------------------------------------------------
-- 1. KÖTÜ SORGU: SELECT * kullanımı
-- Tüm kolonları çeker, ağ trafiği ve bellek kullanımı artar.
-- ----------------------------------------------------------------
EXPLAIN ANALYZE
SELECT *
FROM bookings.ticket_flights;

-- İYİ SORGU: Sadece gerekli kolonları seç
EXPLAIN ANALYZE
SELECT ticket_no, flight_id, amount
FROM bookings.ticket_flights;


-- ----------------------------------------------------------------
-- 2. KÖTÜ SORGU: Kolon üzerinde fonksiyon kullanımı
-- WHERE içinde fonksiyon kullanılırsa index devre dışı kalır!
-- ----------------------------------------------------------------
EXPLAIN ANALYZE
SELECT flight_id, flight_no, scheduled_departure
FROM bookings.flights
WHERE EXTRACT(MONTH FROM scheduled_departure) = 6;

-- İYİ SORGU: Aralık filtresi kullan → index çalışır
EXPLAIN ANALYZE
SELECT flight_id, flight_no, scheduled_departure
FROM bookings.flights
WHERE scheduled_departure >= '2017-06-01'
  AND scheduled_departure < '2017-07-01';


-- ----------------------------------------------------------------
-- 3. KÖTÜ SORGU: Subquery (iç içe sorgu) ile JOIN
-- Her satır için ayrı sorgu çalışır → çok yavaş
-- ----------------------------------------------------------------
EXPLAIN ANALYZE
SELECT
    b.book_ref,
    b.total_amount,
    (SELECT COUNT(*) FROM bookings.tickets t WHERE t.book_ref = b.book_ref) AS bilet_sayisi
FROM bookings.bookings b
LIMIT 1000;

-- İYİ SORGU: JOIN kullan → tek geçişte hesapla
EXPLAIN ANALYZE
SELECT
    b.book_ref,
    b.total_amount,
    COUNT(t.ticket_no) AS bilet_sayisi
FROM bookings.bookings b
LEFT JOIN bookings.tickets t ON b.book_ref = t.book_ref
GROUP BY b.book_ref, b.total_amount
LIMIT 1000;


-- ----------------------------------------------------------------
-- 4. KÖTÜ SORGU: LIKE ile başı joker wildcard
-- Başta % olunca index kullanılamaz, tüm tablo taranır.
-- ----------------------------------------------------------------
EXPLAIN ANALYZE
SELECT passenger_id, passenger_name
FROM bookings.tickets
WHERE passenger_name LIKE '%IVAN%';

-- İYİ SORGU: Başı sabit olan LIKE index kullanabilir
EXPLAIN ANALYZE
SELECT passenger_id, passenger_name
FROM bookings.tickets
WHERE passenger_name LIKE 'IVAN%';


-- ----------------------------------------------------------------
-- 5. KÖTÜ SORGU: Gereksiz DISTINCT kullanımı
-- DISTINCT pahalıdır; önce tüm veriyi çekip sonra tekilleştirir.
-- ----------------------------------------------------------------
EXPLAIN ANALYZE
SELECT DISTINCT flight_id
FROM bookings.ticket_flights
WHERE amount > 10000;

-- İYİ SORGU: EXISTS ile kontrol et (ilk eşleşmede durur)
EXPLAIN ANALYZE
SELECT flight_id
FROM bookings.flights f
WHERE EXISTS (
    SELECT 1 FROM bookings.ticket_flights tf
    WHERE tf.flight_id = f.flight_id
      AND tf.amount > 10000
);


-- ----------------------------------------------------------------
-- 6. Gerçekçi karmaşık sorgu: Kalkış havalimanına göre
--    toplam gelir raporu (JOIN + GROUP BY + ORDER BY)
-- ----------------------------------------------------------------

-- ÖNCE index ekle (gerekirse):
CREATE INDEX IF NOT EXISTS idx_flights_departure_airport
    ON bookings.flights (departure_airport);

CREATE INDEX IF NOT EXISTS idx_ticket_flights_flight_id
    ON bookings.ticket_flights (flight_id);

-- Sorgu: Her havalimanından kaç uçuş kalktı ve toplam gelir ne kadar?
EXPLAIN ANALYZE
SELECT
    f.departure_airport                     AS kalkis_havalimani,
    COUNT(DISTINCT f.flight_id)             AS ucus_sayisi,
    COUNT(tf.ticket_no)                     AS bilet_sayisi,
    ROUND(SUM(tf.amount))                   AS toplam_gelir,
    ROUND(AVG(tf.amount))                   AS ort_bilet_ucreti
FROM bookings.flights f
JOIN bookings.ticket_flights tf ON f.flight_id = tf.flight_id
WHERE f.status = 'Arrived'
GROUP BY f.departure_airport
ORDER BY toplam_gelir DESC
LIMIT 20;


-- ----------------------------------------------------------------
-- 7. VACUUM ANALYZE: İstatistikleri güncelle
-- Sorgu planlayıcısı güncel istatistiklere göre plan yapar.
-- Uzun süredir güncellenmemiş tablolarda performans düşer.
-- ----------------------------------------------------------------
VACUUM ANALYZE bookings.ticket_flights;
VACUUM ANALYZE bookings.flights;
VACUUM ANALYZE bookings.bookings;

-- İstatistik güncelliğini kontrol et:
SELECT
    relname         AS tablo,
    last_vacuum     AS son_vacuum,
    last_analyze    AS son_analiz,
    last_autoanalyze AS otomatik_analiz
FROM pg_stat_user_tables
ORDER BY last_analyze ASC NULLS FIRST;
