-- ============================================================
-- PROJE 1 | ADIM 1: VERİTABANI İZLEME
-- Araç: pg_stat_statements (SQL Profiler muadili)
-- ============================================================
-- Bu adımda PostgreSQL'in yerleşik istatistik görünümlerini
-- (Dynamic Management Views karşılığı) kullanarak hangi
-- sorguların ne kadar sürdüğünü ve kaç kez çalıştığını izleriz.
-- ============================================================


-- ----------------------------------------------------------------
-- 1. pg_stat_statements eklentisini aktif et
-- Bu eklenti, çalışan her sorgunun istatistiğini tutar.
-- MSSQL'deki SQL Profiler'ın PostgreSQL karşılığıdır.
-- ----------------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;


-- ----------------------------------------------------------------
-- 2. En yavaş 10 sorguyu listele (ortalama süreye göre)
-- mean_exec_time : milisaniye cinsinden ortalama çalışma süresi
-- calls          : sorgunun kaç kez çalıştırıldığı
-- total_exec_time: toplam harcanan süre (ms)
-- ----------------------------------------------------------------
SELECT
    LEFT(query, 80)       AS sorgu,
    calls                 AS cagri_sayisi,
    ROUND(mean_exec_time::numeric, 3) AS ort_sure_ms,
    ROUND(total_exec_time::numeric, 3) AS toplam_sure_ms
FROM pg_stat_statements
ORDER BY mean_exec_time DESC
LIMIT 10;


-- ----------------------------------------------------------------
-- 3. Tablo başına satır sayısını ve erişim istatistiklerini gör
-- seq_scan    : tam tablo taraması (yavaş, index yok demek)
-- idx_scan    : index üzerinden erişim (hızlı)
-- n_live_tup  : tablodaki aktif satır sayısı
-- ----------------------------------------------------------------
SELECT
    schemaname        AS sema,
    relname           AS tablo_adi,
    seq_scan          AS tam_tablo_tarama,
    idx_scan          AS index_ile_erisim,
    n_live_tup        AS satir_sayisi
FROM pg_stat_user_tables
ORDER BY seq_scan DESC
LIMIT 10;


-- ----------------------------------------------------------------
-- 4. Aktif bağlantıları ve çalışan sorguları izle
-- MSSQL'deki sp_who2 / Activity Monitor karşılığı
-- ----------------------------------------------------------------
SELECT
    pid               AS islem_id,
    usename           AS kullanici,
    application_name  AS uygulama,
    state             AS durum,
    LEFT(query, 60)   AS sorgu,
    query_start       AS baslangic_zamani
FROM pg_stat_activity
WHERE state != 'idle'
  AND pid != pg_backend_pid();


-- ----------------------------------------------------------------
-- 5. Veritabanı genel istatistikleri
-- blks_hit  : bellekten okunan blok (önbellekte bulundu)
-- blks_read : diskten okunan blok (yavaş)
-- Cache hit oranı yüksekse (> %99) veritabanı sağlıklı demektir.
-- ----------------------------------------------------------------
SELECT
    datname                          AS veritabani,
    blks_hit                         AS onbellekten_okunan,
    blks_read                        AS diskten_okunan,
    ROUND(
        100.0 * blks_hit / NULLIF(blks_hit + blks_read, 0), 2
    )                                AS cache_hit_orani_yuzde,
    tup_returned                     AS döndürülen_satir,
    tup_fetched                      AS getirilen_satir
FROM pg_stat_database
WHERE datname = 'demo';
