-- ============================================================
-- PROJE 1 | ADIM 4: VERİ YÖNETİCİSİ ROLLERİ VE ERİŞİM YÖNETİMİ
-- Farklı kullanıcılara farklı yetkiler verilir.
-- Bu, veritabanı güvenliğinin ve yönetiminin temelidir.
-- ============================================================


-- ----------------------------------------------------------------
-- 1. Mevcut rolleri listele
-- ----------------------------------------------------------------
SELECT rolname, rolsuper, rolcreatedb, rolcreaterole, rolcanlogin
FROM pg_roles
ORDER BY rolname;


-- ----------------------------------------------------------------
-- 2. ROL OLUŞTURMA
-- 3 farklı seviye: salt okuma, veri girişi, tam yönetici
-- ----------------------------------------------------------------

-- Sadece rapor çeken analist (SELECT yetkisi)
DO $$ BEGIN
  CREATE ROLE analist LOGIN PASSWORD 'Analist2024!';
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- Veri giren operatör (INSERT + UPDATE yetkisi)
DO $$ BEGIN
  CREATE ROLE operatör LOGIN PASSWORD 'Operator2024!';
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- Tüm yetkilere sahip yönetici
DO $$ BEGIN
  CREATE ROLE db_yoneticisi LOGIN PASSWORD 'Admin2024!';
EXCEPTION WHEN duplicate_object THEN NULL; END $$;


-- ----------------------------------------------------------------
-- 3. YETKİ VERME (GRANT)
-- ----------------------------------------------------------------

-- Analist: sadece okuyabilir
GRANT CONNECT ON DATABASE demo TO analist;
GRANT USAGE ON SCHEMA bookings TO analist;
GRANT SELECT ON ALL TABLES IN SCHEMA bookings TO analist;

-- Operatör: okuyabilir + veri girebilir/güncelleyebilir
GRANT CONNECT ON DATABASE demo TO operatör;
GRANT USAGE ON SCHEMA bookings TO operatör;
GRANT SELECT, INSERT, UPDATE ON bookings.bookings TO operatör;
GRANT SELECT, INSERT, UPDATE ON bookings.tickets TO operatör;
GRANT SELECT, INSERT, UPDATE ON bookings.ticket_flights TO operatör;
GRANT SELECT ON bookings.flights TO operatör;
GRANT SELECT ON bookings.seats TO operatör;

-- Yönetici: tüm yetkiler
GRANT CONNECT ON DATABASE demo TO db_yoneticisi;
GRANT USAGE ON SCHEMA bookings TO db_yoneticisi;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA bookings TO db_yoneticisi;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA bookings TO db_yoneticisi;


-- ----------------------------------------------------------------
-- 4. YETKİLERİ DOĞRULA
-- Kimin hangi tabloya ne yetkisi var?
-- ----------------------------------------------------------------
SELECT
    grantee          AS kullanici,
    table_schema     AS sema,
    table_name       AS tablo,
    privilege_type   AS yetki
FROM information_schema.role_table_grants
WHERE grantee IN ('analist', 'operatör', 'db_yoneticisi')
ORDER BY grantee, table_name, privilege_type;


-- ----------------------------------------------------------------
-- 5. YETKİ TESTİ
-- Analist olarak bağlanıp DELETE denediğimizde hata almalıyız.
-- ----------------------------------------------------------------

-- Analist bağlantısıyla test (terminal'de çalıştır):
-- psql -U analist -d demo
-- SET search_path TO bookings;
-- SELECT COUNT(*) FROM bookings;        -- ÇALIŞIR
-- DELETE FROM bookings WHERE 1=1;       -- HATA: permission denied


-- ----------------------------------------------------------------
-- 6. ROW LEVEL SECURITY (Satır Bazında Güvenlik)
-- Her kullanıcı sadece kendi verilerini görsün örneği.
-- Operatör yalnızca belirli statüdeki uçuşları görebilsin.
-- ----------------------------------------------------------------
ALTER TABLE bookings.flights ENABLE ROW LEVEL SECURITY;

-- Yöneticiler her şeyi görsün
DROP POLICY IF EXISTS yönetici_politikasi ON bookings.flights;
CREATE POLICY yönetici_politikasi
    ON bookings.flights
    FOR ALL
    TO db_yoneticisi
    USING (true);

-- Analistler sadece 'Arrived' uçuşları görsün
DROP POLICY IF EXISTS analist_politikasi ON bookings.flights;
CREATE POLICY analist_politikasi
    ON bookings.flights
    FOR SELECT
    TO analist
    USING (status = 'Arrived');

-- Tabloyu owner bypass etsin (test için gerekli)
ALTER TABLE bookings.flights FORCE ROW LEVEL SECURITY;

-- RLS politikalarını görüntüle:
SELECT polname, polcmd, polroles, polqual
FROM pg_policy
WHERE polrelid = 'bookings.flights'::regclass;


-- ----------------------------------------------------------------
-- 7. YETKİ KALDIR (REVOKE) - Temizlik adımı
-- Proje bittikten sonra test rollerini kaldırabilirsin.
-- ----------------------------------------------------------------
-- REVOKE ALL ON ALL TABLES IN SCHEMA bookings FROM analist;
-- REVOKE ALL ON ALL TABLES IN SCHEMA bookings FROM operatör;
-- DROP ROLE analist;
-- DROP ROLE operatör;
-- DROP ROLE db_yoneticisi;


-- ----------------------------------------------------------------
-- 8. Bağlantı limiti belirle (aşırı bağlantıyı önle)
-- ----------------------------------------------------------------
ALTER ROLE analist CONNECTION LIMIT 5;
ALTER ROLE operatör CONNECTION LIMIT 10;
ALTER ROLE db_yoneticisi CONNECTION LIMIT -1;  -- sınırsız

-- Kontrol et:
SELECT rolname, rolconnlimit AS baglanti_limiti
FROM pg_roles
WHERE rolname IN ('analist', 'operatör', 'db_yoneticisi');
