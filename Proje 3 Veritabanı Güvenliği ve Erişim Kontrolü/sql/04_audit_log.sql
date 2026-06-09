-- ============================================================
-- PROJE 3 | ADIM 4: AUDİT LOGLARI
-- Kullanıcı aktivitelerini izleme
-- MSSQL'deki SQL Server Audit özelliğinin PostgreSQL karşılığı
-- ============================================================


-- ----------------------------------------------------------------
-- 1. Audit log tablosu oluştur
-- Her veri değişikliği bu tabloya kaydedilir
-- ----------------------------------------------------------------
DROP TABLE IF EXISTS audit_log;

CREATE TABLE audit_log (
    log_id          SERIAL PRIMARY KEY,
    tablo_adi       TEXT,
    islem_tipi      TEXT,           -- INSERT, UPDATE, DELETE
    kullanici       TEXT,
    islem_zamani    TIMESTAMP DEFAULT now(),
    eski_veri       JSONB,          -- değişmeden önceki veri
    yeni_veri       JSONB           -- değişimden sonraki veri
);


-- ----------------------------------------------------------------
-- 2. Audit trigger fonksiyonu
-- Her INSERT/UPDATE/DELETE işleminde otomatik çalışır
-- ----------------------------------------------------------------
CREATE OR REPLACE FUNCTION audit_trigger_fonksiyon()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        INSERT INTO audit_log (tablo_adi, islem_tipi, kullanici, yeni_veri)
        VALUES (TG_TABLE_NAME, 'INSERT', current_user, row_to_json(NEW)::jsonb);
        RETURN NEW;

    ELSIF TG_OP = 'UPDATE' THEN
        INSERT INTO audit_log (tablo_adi, islem_tipi, kullanici, eski_veri, yeni_veri)
        VALUES (TG_TABLE_NAME, 'UPDATE', current_user, row_to_json(OLD)::jsonb, row_to_json(NEW)::jsonb);
        RETURN NEW;

    ELSIF TG_OP = 'DELETE' THEN
        INSERT INTO audit_log (tablo_adi, islem_tipi, kullanici, eski_veri)
        VALUES (TG_TABLE_NAME, 'DELETE', current_user, row_to_json(OLD)::jsonb);
        RETURN OLD;
    END IF;
END;
$$ LANGUAGE plpgsql;


-- ----------------------------------------------------------------
-- 3. Trigger'ları tablolara bağla
-- ----------------------------------------------------------------
DROP TRIGGER IF EXISTS bookings_audit ON bookings.bookings;
CREATE TRIGGER bookings_audit
    AFTER INSERT OR UPDATE OR DELETE ON bookings.bookings
    FOR EACH ROW EXECUTE FUNCTION audit_trigger_fonksiyon();

DROP TRIGGER IF EXISTS tickets_audit ON bookings.tickets;
CREATE TRIGGER tickets_audit
    AFTER INSERT OR UPDATE OR DELETE ON bookings.tickets
    FOR EACH ROW EXECUTE FUNCTION audit_trigger_fonksiyon();


-- ----------------------------------------------------------------
-- 4. Test — işlem yap, log'a düştüğünü göster
-- ----------------------------------------------------------------

-- Test kaydı ekle
INSERT INTO bookings.bookings (book_ref, book_date, total_amount)
VALUES ('TEST01', now(), 5000.00);

-- Güncelle
UPDATE bookings.bookings
SET total_amount = 7500.00
WHERE book_ref = 'TEST01';

-- Sil
DELETE FROM bookings.bookings
WHERE book_ref = 'TEST01';


-- ----------------------------------------------------------------
-- 5. Audit loglarını görüntüle
-- ----------------------------------------------------------------
SELECT
    log_id,
    tablo_adi,
    islem_tipi,
    kullanici,
    islem_zamani,
    eski_veri,
    yeni_veri
FROM audit_log
ORDER BY islem_zamani DESC;


-- ----------------------------------------------------------------
-- 6. Şüpheli aktivite tespiti
-- Aynı kullanıcı kısa sürede çok fazla silme yaptıysa uyar
-- ----------------------------------------------------------------
SELECT
    kullanici,
    islem_tipi,
    COUNT(*) AS islem_sayisi,
    MIN(islem_zamani) AS ilk_islem,
    MAX(islem_zamani) AS son_islem
FROM audit_log
WHERE islem_tipi = 'DELETE'
  AND islem_zamani > now() - INTERVAL '1 hour'
GROUP BY kullanici, islem_tipi
HAVING COUNT(*) > 0
ORDER BY islem_sayisi DESC;


