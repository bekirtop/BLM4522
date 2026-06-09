-- =============================================================
-- PROJE 6 — Veritabanı Yükseltme ve Sürüm Yönetimi
-- Adım 1: Sürüm Yönetimi — Şema Versiyon Takip Sistemi
-- Platform: PostgreSQL 16
-- Veritabanı: demo (bookings şeması)
-- =============================================================

SET search_path TO bookings;

-- Önceki çalıştırmadan kalan trigger varsa temizle (tekrar çalıştırma güvenliği)
DROP EVENT TRIGGER IF EXISTS ddl_degisiklik_trigger;

-- ─────────────────────────────────────────────────────────────
-- SORGU 1: Mevcut PostgreSQL sürümünü göster
-- ─────────────────────────────────────────────────────────────
SELECT
    version()                            AS postgres_versiyonu,
    current_database()                   AS veritabani,
    current_schema()                     AS aktif_sema,
    pg_postmaster_start_time()::DATE     AS sunucu_baslangic;


-- ─────────────────────────────────────────────────────────────
-- SORGU 2: Şema versiyon takip tablosu oluştur
-- ─────────────────────────────────────────────────────────────
DROP TABLE IF EXISTS schema_versiyon CASCADE;

CREATE TABLE schema_versiyon (
    id              SERIAL PRIMARY KEY,
    versiyon_no     TEXT         NOT NULL,   -- örn: '1.0.0', '1.1.0', '2.0.0'
    aciklama        TEXT         NOT NULL,
    degisiklik_tipi TEXT         NOT NULL    -- 'UPGRADE', 'ROLLBACK', 'HOTFIX'
        CHECK (degisiklik_tipi IN ('UPGRADE', 'ROLLBACK', 'HOTFIX')),
    uygulayan       TEXT         DEFAULT current_user,
    uygulama_tarihi TIMESTAMP    DEFAULT now(),
    durum           TEXT         DEFAULT 'BASARILI'
        CHECK (durum IN ('BASARILI', 'BASARISIZ', 'BEKLEMEDE')),
    sql_betigi      TEXT         -- hangi betik çalıştırıldı
);

-- Tabloya başlangıç kaydını ekle (v1.0.0 — mevcut durum)
INSERT INTO schema_versiyon (versiyon_no, aciklama, degisiklik_tipi, sql_betigi)
VALUES (
    '1.0.0',
    'Başlangıç durumu — uçuş rezervasyon şeması (flights, bookings, tickets, ticket_flights, seats, airports_data, aircrafts_data)',
    'UPGRADE',
    '-- temel şema, postgrespro örnek veritabanından'
);

SELECT * FROM schema_versiyon;


-- ─────────────────────────────────────────────────────────────
-- SORGU 3: DDL Event Trigger — şema değişikliklerini otomatik yakala
-- ─────────────────────────────────────────────────────────────
DROP TABLE IF EXISTS ddl_degisiklik_log;

CREATE TABLE ddl_degisiklik_log (
    log_id          SERIAL PRIMARY KEY,
    komut_tipi      TEXT,        -- CREATE TABLE, ALTER TABLE, DROP ...
    nesne_tipi      TEXT,        -- TABLE, INDEX, FUNCTION ...
    nesne_adi       TEXT,
    kullanici       TEXT,
    zaman           TIMESTAMP DEFAULT now(),
    sorgu_metni     TEXT
);

-- DDL event trigger fonksiyonu
CREATE OR REPLACE FUNCTION ddl_degisiklik_yakala()
RETURNS event_trigger AS $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN SELECT * FROM pg_event_trigger_ddl_commands()
    LOOP
        INSERT INTO ddl_degisiklik_log
            (komut_tipi, nesne_tipi, nesne_adi, kullanici, sorgu_metni)
        VALUES (
            r.command_tag,
            r.object_type,
            r.object_identity,
            current_user,
            current_query()
        );
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- Event trigger'ı kaydet
DROP EVENT TRIGGER IF EXISTS ddl_degisiklik_trigger;

CREATE EVENT TRIGGER ddl_degisiklik_trigger
    ON ddl_command_end
    EXECUTE FUNCTION ddl_degisiklik_yakala();


-- ─────────────────────────────────────────────────────────────
-- SORGU 4: DDL trigger'ın çalıştığını test et — örnek tablo oluştur
-- ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS trigger_test_tablosu (
    id   SERIAL PRIMARY KEY,
    adi  TEXT
);

DROP TABLE IF EXISTS trigger_test_tablosu;

-- DDL log'una düştü mü?
SELECT
    log_id,
    komut_tipi,
    nesne_tipi,
    nesne_adi,
    kullanici,
    zaman
FROM ddl_degisiklik_log
ORDER BY zaman DESC
LIMIT 5;


-- ─────────────────────────────────────────────────────────────
-- SORGU 5: Mevcut şema yapısının anlık görüntüsü (v1.0.0 baseline)
-- ─────────────────────────────────────────────────────────────
SELECT
    table_name                          AS tablo_adi,
    (SELECT COUNT(*)
     FROM information_schema.columns c
     WHERE c.table_schema = t.table_schema
       AND c.table_name   = t.table_name) AS kolon_sayisi,
    pg_size_pretty(
        pg_total_relation_size(
            quote_ident(t.table_schema) || '.' || quote_ident(t.table_name)
        )
    )                                   AS toplam_boyut
FROM information_schema.tables t
WHERE table_schema = 'bookings'
  AND table_type   = 'BASE TABLE'
ORDER BY table_name;


-- ─────────────────────────────────────────────────────────────
-- SORGU 6: Mevcut indekslerin listesi (v1.0.0 baseline)
-- ─────────────────────────────────────────────────────────────
SELECT
    indexname   AS indeks_adi,
    tablename   AS tablo,
    indexdef    AS tanim
FROM pg_indexes
WHERE schemaname = 'bookings'
ORDER BY tablename, indexname;
