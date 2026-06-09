-- ============================================================
-- PROJE 3 | ADIM 1: ERİŞİM YÖNETİMİ
-- Kullanıcı rolleri, yetkiler ve bağlantı güvenliği
-- ============================================================


-- ----------------------------------------------------------------
-- 1. Mevcut rolleri listele
-- ----------------------------------------------------------------
SELECT rolname, rolsuper, rolcreatedb, rolcanlogin, rolconnlimit
FROM pg_roles
WHERE rolname NOT LIKE 'pg_%'
ORDER BY rolname;


-- ----------------------------------------------------------------
-- 2. Güvenlik rolleri oluştur
-- Senaryo: bir havayolu sisteminde 3 farklı kullanıcı tipi var
-- ----------------------------------------------------------------
DO $$ BEGIN
  CREATE ROLE rapor_kullanici LOGIN PASSWORD 'Rapor2024!';
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE ROLE bilet_operatoru LOGIN PASSWORD 'Bilet2024!';
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE ROLE guvenlik_admin LOGIN PASSWORD 'GAdmin2024!';
EXCEPTION WHEN duplicate_object THEN NULL; END $$;


-- ----------------------------------------------------------------
-- 3. Yetkileri ver — en az yetki prensibi (least privilege)
-- Kullanıcıya sadece işi için gereken yetkiyi ver, fazlasını değil
-- ----------------------------------------------------------------

-- rapor_kullanici: sadece okuyabilir
GRANT CONNECT ON DATABASE demo TO rapor_kullanici;
GRANT USAGE ON SCHEMA bookings TO rapor_kullanici;
GRANT SELECT ON bookings.flights TO rapor_kullanici;
GRANT SELECT ON bookings.bookings TO rapor_kullanici;
GRANT SELECT ON bookings.airports_data TO rapor_kullanici;
GRANT SELECT ON bookings.aircrafts_data TO rapor_kullanici;

-- bilet_operatoru: bilet işlemleri yapabilir
GRANT CONNECT ON DATABASE demo TO bilet_operatoru;
GRANT USAGE ON SCHEMA bookings TO bilet_operatoru;
GRANT SELECT, INSERT, UPDATE ON bookings.tickets TO bilet_operatoru;
GRANT SELECT, INSERT, UPDATE ON bookings.ticket_flights TO bilet_operatoru;
GRANT SELECT, INSERT, UPDATE ON bookings.bookings TO bilet_operatoru;
GRANT SELECT ON bookings.flights TO bilet_operatoru;
GRANT SELECT ON bookings.seats TO bilet_operatoru;

-- guvenlik_admin: her şeyi yapabilir
GRANT CONNECT ON DATABASE demo TO guvenlik_admin;
GRANT USAGE ON SCHEMA bookings TO guvenlik_admin;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA bookings TO guvenlik_admin;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA bookings TO guvenlik_admin;


-- ----------------------------------------------------------------
-- 4. Bağlantı limiti — kaynak tüketimini engelle
-- ----------------------------------------------------------------
ALTER ROLE rapor_kullanici  CONNECTION LIMIT 3;
ALTER ROLE bilet_operatoru  CONNECTION LIMIT 10;
ALTER ROLE guvenlik_admin   CONNECTION LIMIT -1;

-- Şifre geçerlilik süresi belirle
ALTER ROLE rapor_kullanici  VALID UNTIL '2027-06-10';
ALTER ROLE bilet_operatoru  VALID UNTIL '2027-06-10';


-- ----------------------------------------------------------------
-- 5. Yetkileri doğrula
-- ----------------------------------------------------------------
SELECT
    grantee        AS kullanici,
    table_name     AS tablo,
    privilege_type AS yetki
FROM information_schema.role_table_grants
WHERE grantee IN ('rapor_kullanici', 'bilet_operatoru', 'guvenlik_admin')
ORDER BY grantee, table_name;


-- ----------------------------------------------------------------
-- 6. Yetkiyi geri al — REVOKE
-- bilet_operatoru artık bookings tablosunu silemez
-- ----------------------------------------------------------------
REVOKE DELETE ON bookings.bookings FROM bilet_operatoru;

-- Doğrula: DELETE yetkisi olmadığını göster
SELECT grantee, table_name, privilege_type
FROM information_schema.role_table_grants
WHERE grantee = 'bilet_operatoru'
  AND table_name = 'bookings';
