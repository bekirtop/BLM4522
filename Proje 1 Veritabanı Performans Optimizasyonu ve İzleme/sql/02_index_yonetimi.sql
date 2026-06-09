-- ============================================================
-- PROJE 1 | ADIM 2: İNDEKS YÖNETİMİ
-- İndeks: Kitaptaki "dizin" gibidir. Aranacak değerin tam
-- yerini gösterir, tüm sayfaları taramak gerekmez.
-- ============================================================


-- ----------------------------------------------------------------
-- 1. Mevcut indexleri listele
-- ----------------------------------------------------------------
SELECT
    schemaname  AS sema,
    tablename   AS tablo,
    indexname   AS index_adi,
    indexdef    AS tanim
FROM pg_indexes
WHERE schemaname = 'bookings'
ORDER BY tablename;


-- ----------------------------------------------------------------
-- 2. Index OLMADAN sorgu çalıştır → ÖNCE süreyi ölç
-- EXPLAIN ANALYZE: sorgunun nasıl çalıştığını adım adım gösterir
-- "Seq Scan" = tüm tabloyu taradı (yavaş)
-- "cost"     = tahmini maliyet, "actual time" = gerçek süre (ms)
-- ----------------------------------------------------------------
EXPLAIN ANALYZE
SELECT tf.ticket_no, tf.flight_id, tf.amount
FROM bookings.ticket_flights tf
WHERE tf.amount > 50000;


-- ----------------------------------------------------------------
-- 3. amount kolonuna index EKLE
-- Bu kolonla WHERE filtresi sık yapılıyor, index çok faydalı.
-- ----------------------------------------------------------------
CREATE INDEX idx_ticket_flights_amount
    ON bookings.ticket_flights (amount);


-- ----------------------------------------------------------------
-- 4. Index SONRASI aynı sorguyu çalıştır → SONRA süreyi ölç
-- "Index Scan" veya "Bitmap Heap Scan" görmelisin (hızlı)
-- ----------------------------------------------------------------
EXPLAIN ANALYZE
SELECT tf.ticket_no, tf.flight_id, tf.amount
FROM bookings.ticket_flights tf
WHERE tf.amount > 50000;


-- ----------------------------------------------------------------
-- 5. flights tablosunda departure tarihine göre filtreleme
-- Önce index yok → Seq Scan
-- ----------------------------------------------------------------
EXPLAIN ANALYZE
SELECT flight_id, flight_no, scheduled_departure, status
FROM bookings.flights
WHERE scheduled_departure BETWEEN '2017-01-01' AND '2017-06-01';


-- 5b. Index ekle
CREATE INDEX idx_flights_departure
    ON bookings.flights (scheduled_departure);


-- 5c. Index sonrası → Index Scan (çok daha hızlı)
EXPLAIN ANALYZE
SELECT flight_id, flight_no, scheduled_departure, status
FROM bookings.flights
WHERE scheduled_departure BETWEEN '2017-01-01' AND '2017-06-01';


-- ----------------------------------------------------------------
-- 6. Bileşik (composite) index örneği
-- Hem flight_id hem status ile birlikte sorgulama yapılıyorsa
-- iki kolonlu index daha verimli olur.
-- ----------------------------------------------------------------
CREATE INDEX idx_flights_status_departure
    ON bookings.flights (status, scheduled_departure);

EXPLAIN ANALYZE
SELECT flight_id, flight_no, scheduled_departure
FROM bookings.flights
WHERE status = 'Arrived'
  AND scheduled_departure > '2017-06-01';


-- ----------------------------------------------------------------
-- 7. Kullanılmayan indexleri tespit et ve kaldır
-- idx_scan = 0 olan index hiç kullanılmamış demektir.
-- Kullanılmayan indexler disk kaplar ve yazma işlemlerini yavaşlatır.
-- ----------------------------------------------------------------
SELECT
    schemaname   AS sema,
    relname      AS tablo,
    indexrelname AS index_adi,
    idx_scan     AS kullanim_sayisi,
    pg_size_pretty(pg_relation_size(indexrelid)) AS boyut
FROM pg_stat_user_indexes
WHERE idx_scan = 0
ORDER BY pg_relation_size(indexrelid) DESC;

-- Gereksiz indexi kaldır (örnek):
-- DROP INDEX bookings.idx_gereksiz_index;


-- ----------------------------------------------------------------
-- 8. Index boyutlarını karşılaştır
-- ----------------------------------------------------------------
SELECT
    relname                                        AS nesne,
    pg_size_pretty(pg_total_relation_size(relid))  AS toplam_boyut,
    pg_size_pretty(pg_relation_size(relid))         AS tablo_boyutu,
    pg_size_pretty(pg_indexes_size(relid))          AS index_boyutu
FROM pg_stat_user_tables
ORDER BY pg_total_relation_size(relid) DESC;
