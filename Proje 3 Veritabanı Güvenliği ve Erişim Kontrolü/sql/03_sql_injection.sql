-- ============================================================
-- PROJE 3 | ADIM 3: SQL INJECTION TESTLERİ
-- Saldırı senaryosu ve korunma yöntemleri
-- ============================================================


-- ----------------------------------------------------------------
-- 1. Test tablosu oluştur
-- ----------------------------------------------------------------
DROP TABLE IF EXISTS kullanici_giris;

CREATE TABLE kullanici_giris (
    id       SERIAL PRIMARY KEY,
    kullanici TEXT NOT NULL,
    sifre    TEXT NOT NULL,
    rol      TEXT DEFAULT 'user'
);

INSERT INTO kullanici_giris (kullanici, sifre, rol) VALUES
    ('admin',   'Admin123!',  'admin'),
    ('bekir',   'Bekir456!',  'user'),
    ('ayse',    'Ayse789!',   'user'),
    ('mehmet',  'Mehmet012!', 'user');


-- ----------------------------------------------------------------
-- 2. SAVUNMASIZ SORGU — SQL Injection'a açık
-- Uygulama katmanında böyle bir kod olursa:
-- "SELECT * FROM kullanici_giris WHERE kullanici = '" + input + "'"
-- ----------------------------------------------------------------

-- Normal kullanım — beklenen davranış
SELECT * FROM kullanici_giris
WHERE kullanici = 'bekir';

-- SQL INJECTION SALDIRISI 1: Her zaman true yapan payload
-- Saldırgan input olarak şunu girer: ' OR '1'='1
-- Oluşan sorgu: WHERE kullanici = '' OR '1'='1'
-- TÜM KAYITLARI döndürür — kimlik doğrulamayı atlar!
SELECT * FROM kullanici_giris
WHERE kullanici = '' OR '1'='1';

-- SQL INJECTION SALDIRISI 2: UNION ile başka tablodan veri çal
-- Saldırgan pg_roles tablosundaki tüm kullanıcı adlarını çeker
SELECT id, kullanici, sifre, rol FROM kullanici_giris
WHERE kullanici = '' UNION SELECT 1, rolname, rolname, rolname FROM pg_roles;


-- ----------------------------------------------------------------
-- 3. KORUNMA YÖNTEMİ 1: Parameterized query (psql \set ile)
-- Gerçek uygulamada driver seviyesinde yapılır
-- ----------------------------------------------------------------
\set guvenli_input '''bekir'''
SELECT * FROM kullanici_giris
WHERE kullanici = :guvenli_input;


-- ----------------------------------------------------------------
-- 4. KORUNMA YÖNTEMİ 2: Giriş doğrulama fonksiyonu
-- Kullanıcı adında sadece harf ve rakam olmasını zorunlu kıl
-- ----------------------------------------------------------------
CREATE OR REPLACE FUNCTION guvenli_kullanici_dogrula(giris TEXT)
RETURNS BOOLEAN AS $$
BEGIN
    -- Sadece harf, rakam ve alt çizgiye izin ver
    IF giris ~ '^[a-zA-Z0-9_]+$' THEN
        RETURN TRUE;
    ELSE
        RAISE EXCEPTION 'Geçersiz karakter tespit edildi: %', giris;
        RETURN FALSE;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- Güvenli input → true döner
SELECT guvenli_kullanici_dogrula('bekir');

-- Tehlikeli input → hata fırlatır
SELECT guvenli_kullanici_dogrula(''' OR ''1''=''1');


-- ----------------------------------------------------------------
-- 5. KORUNMA YÖNTEMİ 3: Kullanıcıya minimum yetki ver
-- rapor_kullanici sadece SELECT yapabilir
-- DELETE/DROP gibi tehlikeli komutları çalıştıramaz
-- ----------------------------------------------------------------
SELECT
    grantee,
    table_name,
    privilege_type
FROM information_schema.role_table_grants
WHERE grantee = 'rapor_kullanici'
ORDER BY table_name, privilege_type;


-- ----------------------------------------------------------------
-- 6. Tabloyu temizle
-- ----------------------------------------------------------------
DROP TABLE IF EXISTS kullanici_giris;
DROP FUNCTION IF EXISTS guvenli_kullanici_dogrula(TEXT);
