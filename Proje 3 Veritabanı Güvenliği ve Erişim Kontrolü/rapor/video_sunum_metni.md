# Proje 3 — Video Sunum Metni
## Veritabanı Güvenliği ve Erişim Kontrolü

---

> **VİDEOYA BAŞLAMADAN ÖNCE terminalde şunu çalıştır:**
> ```
> export PATH="/opt/homebrew/opt/postgresql@16/bin:$PATH"
> psql -U bekirtop -d demo
> ```
> Bağlandıktan sonra:
> ```sql
> SET search_path TO bookings;
> ```

---

## GİRİŞ

"Merhaba hocam, ben Bekir Top. Bu videoda BLM4522 dersi kapsamında hazırladığım
Proje 3'ü anlatacağım. Proje konusu Veritabanı Güvenliği ve Erişim Kontrolü.
Platform olarak PostgreSQL 16 kullandım, aynı uçuş rezervasyon veritabanı
üzerinde çalışacağım.

Bu projede 4 ana konu var: erişim yönetimi, veri şifreleme, SQL injection
testleri ve audit logları. Sırayla gidelim."

---

## ADIM 1 — ERİŞİM YÖNETİMİ

"İlk adım erişim yönetimi. Temel prensip şu: her kullanıcıya sadece işi için
gereken yetkiyi ver, fazlasını değil. Buna 'least privilege' yani en az yetki
prensibi deniyor. Önce mevcut rollere bakayım."

**► 01 DOSYASI — Sorgu 1: Mevcut roller**
```sql
SELECT rolname, rolsuper, rolcreatedb, rolcanlogin, rolconnlimit
FROM pg_roles
WHERE rolname NOT LIKE 'pg_%'
ORDER BY rolname;
```

"Burada sistemdeki tüm roller listelendi. rolsuper kolonu süper kullanıcı
olup olmadığını, rolcanlogin ise o role giriş yapılıp yapılamayacağını gösteriyor.
Şu an sadece varsayılan roller var, biz yenilerini ekleyeceğiz.

Bir havayolu sistemini düşünelim hocam. 3 farklı kullanıcı tipi var:
rapor çeken analistler, bilet işlemleri yapan operatörler ve her şeye erişebilen
sistem yöneticisi. Her biri için ayrı rol oluşturuyorum."

**► 01 DOSYASI — Sorgu 2: Güvenlik rollerini oluştur**
```sql
DO $$ BEGIN
  CREATE ROLE rapor_kullanici LOGIN PASSWORD 'Rapor2024!';
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE ROLE bilet_operatoru LOGIN PASSWORD 'Bilet2024!';
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE ROLE guvenlik_admin LOGIN PASSWORD 'GAdmin2024!';
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
```

"DO EXCEPTION bloğunu şu yüzden kullandım: sorguyu ikinci kez çalıştırdığımda
rol zaten varsa hata fırlatmasın diye. DO $$ ... $$ PostgreSQL'de anonim kod
bloğu çalıştırmanın yolu — MSSQL'deki BEGIN...END bloğunun karşılığı.

Şimdi yetkileri veriyorum."

**► 01 DOSYASI — Sorgu 3: Yetkileri ver**
```sql
GRANT CONNECT ON DATABASE demo TO rapor_kullanici;
GRANT USAGE ON SCHEMA bookings TO rapor_kullanici;
GRANT SELECT ON bookings.flights TO rapor_kullanici;
GRANT SELECT ON bookings.bookings TO rapor_kullanici;
GRANT SELECT ON bookings.airports_data TO rapor_kullanici;
GRANT SELECT ON bookings.aircrafts_data TO rapor_kullanici;

GRANT CONNECT ON DATABASE demo TO bilet_operatoru;
GRANT USAGE ON SCHEMA bookings TO bilet_operatoru;
GRANT SELECT, INSERT, UPDATE ON bookings.tickets TO bilet_operatoru;
GRANT SELECT, INSERT, UPDATE ON bookings.ticket_flights TO bilet_operatoru;
GRANT SELECT, INSERT, UPDATE ON bookings.bookings TO bilet_operatoru;
GRANT SELECT ON bookings.flights TO bilet_operatoru;
GRANT SELECT ON bookings.seats TO bilet_operatoru;

GRANT CONNECT ON DATABASE demo TO guvenlik_admin;
GRANT USAGE ON SCHEMA bookings TO guvenlik_admin;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA bookings TO guvenlik_admin;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA bookings TO guvenlik_admin;
```

"Her satırda GRANT yazıyor — yetki başarıyla verildi demek. rapor_kullanici'ya
sadece SELECT verdim, bilet_operatoru'na SELECT, INSERT, UPDATE verdim ama
DELETE vermedim. guvenlik_admin'e ALL PRIVILEGES yani her şeyi verdim.

Şimdi bağlantı limitleri ve şifre geçerlilik tarihlerini ayarlıyorum."

**► 01 DOSYASI — Sorgu 4: Bağlantı limiti ve geçerlilik tarihi**
```sql
ALTER ROLE rapor_kullanici  CONNECTION LIMIT 3;
ALTER ROLE bilet_operatoru  CONNECTION LIMIT 10;
ALTER ROLE guvenlik_admin   CONNECTION LIMIT -1;

ALTER ROLE rapor_kullanici  VALID UNTIL '2025-12-31';
ALTER ROLE bilet_operatoru  VALID UNTIL '2025-12-31';
```

"ALTER ROLE yazıları geldi — değişiklikler uygulandı. rapor_kullanici aynı anda
en fazla 3 bağlantı açabilir, yani 3 kişi aynı anda bu kullanıcıyla bağlanamaz.
-1 sınırsız demek. Şifre geçerliliği yıl sonunda dolunca bu kullanıcılar
otomatik olarak bağlanamaz hale gelecek.

Şimdi yetkileri doğrulayalım."

**► 01 DOSYASI — Sorgu 5: Yetkileri doğrula**
```sql
SELECT
    grantee        AS kullanici,
    table_name     AS tablo,
    privilege_type AS yetki
FROM information_schema.role_table_grants
WHERE grantee IN ('rapor_kullanici', 'bilet_operatoru', 'guvenlik_admin')
ORDER BY grantee, table_name;
```

"Bakın — rapor_kullanici'nın tüm tablolarda sadece SELECT yetkisi var,
başka hiçbir şey yok. bilet_operatoru'nda tickets, ticket_flights ve
bookings tablolarında SELECT, INSERT, UPDATE var ama DELETE görmüyoruz.
guvenlik_admin'de her şey var. Tam istediğimiz gibi.

Son olarak REVOKE ile yetki geri alıyorum."

**► 01 DOSYASI — Sorgu 6: Yetki geri al**
```sql
REVOKE DELETE ON bookings.bookings FROM bilet_operatoru;

SELECT grantee, table_name, privilege_type
FROM information_schema.role_table_grants
WHERE grantee = 'bilet_operatoru'
  AND table_name = 'bookings';
```

"Listeye bakıyorum — bilet_operatoru için bookings tablosunda sadece
SELECT, INSERT, UPDATE görüyorum. DELETE yok. REVOKE ile silme yetkisi
başarıyla geri alındı."

---

## ADIM 2 — VERİ ŞİFRELEME

"İkinci adım veri şifreleme. MSSQL'de TDE yani Transparent Data Encryption
denen özellik var. PostgreSQL'de bunun karşılığı pgcrypto eklentisi.

Senaryo şu: yolcu TC kimlik numaraları ve telefon bilgileri veritabanında
düz metin olarak saklanmamalı. Biri veritabanına yetkisiz erişse bile
bu verileri okuyamamalı. Önce eklentiyi aktif ediyorum."

**► 02 DOSYASI — Sorgu 1: pgcrypto eklentisini aktif et**
```sql
CREATE EXTENSION IF NOT EXISTS pgcrypto;
```

"CREATE EXTENSION yazdı — eklenti aktif. IF NOT EXISTS koydum çünkü zaten
varsa hata vermesin diye.

Şimdi hassas veri tablosu oluşturuyorum."

**► 02 DOSYASI — Sorgu 2: Tablo oluştur**
```sql
DROP TABLE IF EXISTS guvenli_yolcu;

CREATE TABLE guvenli_yolcu (
    id              SERIAL PRIMARY KEY,
    ad_soyad        TEXT NOT NULL,
    tc_kimlik       BYTEA,
    telefon         BYTEA,
    email           TEXT,
    sifre_hash      TEXT,
    kayit_tarihi    TIMESTAMP DEFAULT now()
);
```

"CREATE TABLE yazdı — tablo oluştu. tc_kimlik ve telefon kolonlarının tipi
BYTEA — yani ham bayt dizisi. Normal TEXT değil. Buraya şifreli veri
yazacağız, düz metin değil.

Şimdi veri ekliyorum."

**► 02 DOSYASI — Sorgu 3: Şifreli veri ekle**
```sql
INSERT INTO guvenli_yolcu (ad_soyad, tc_kimlik, telefon, email, sifre_hash)
VALUES (
    'Ahmet Yılmaz',
    pgp_sym_encrypt('12345678901', 'gizli_anahtar_2024'),
    pgp_sym_encrypt('05551234567', 'gizli_anahtar_2024'),
    'ahmet@email.com',
    crypt('sifre123', gen_salt('bf'))
);

INSERT INTO guvenli_yolcu (ad_soyad, tc_kimlik, telefon, email, sifre_hash)
VALUES (
    'Ayşe Kaya',
    pgp_sym_encrypt('98765432100', 'gizli_anahtar_2024'),
    pgp_sym_encrypt('05559876543', 'gizli_anahtar_2024'),
    'ayse@email.com',
    crypt('parola456', gen_salt('bf'))
);

INSERT INTO guvenli_yolcu (ad_soyad, tc_kimlik, telefon, email, sifre_hash)
VALUES (
    'Mehmet Demir',
    pgp_sym_encrypt('11122233344', 'gizli_anahtar_2024'),
    pgp_sym_encrypt('05341112233', 'gizli_anahtar_2024'),
    'mehmet@email.com',
    crypt('gizli789', gen_salt('bf'))
);
```

"3 kez INSERT 0 1 yazdı — 3 kayıt eklendi. pgp_sym_encrypt TC ve telefonu
şifreliyor. crypt fonksiyonu ise şifreyi bcrypt ile hash'liyor.
bcrypt her seferinde farklı sonuç üretir, bu yüzden aynı şifre bile
farklı hash'e dönüşür.

Şimdi tabloya bakalım — veritabanında nasıl görünüyor?"

**► 02 DOSYASI — Sorgu 4: Ham veriyi göster**
```sql
SELECT id, ad_soyad, tc_kimlik, telefon, email, sifre_hash
FROM guvenli_yolcu;
```

"Bakın hocam — ad_soyad ve email düz metin olarak görünüyor ama
tc_kimlik ve telefon kolonlarında anlamsız karakterler var. Bunlar
şifrelenmiş ham baytlar. Biri bu veritabanını ele geçirse bile TC numaralarını
ve telefonları okuyamaz. sifre_hash kolonunda da bcrypt hash'i görüyoruz —
şifreler hiçbir zaman düz metin olarak saklanmıyor.

Şimdi doğru anahtarla şifreyi çözelim."

**► 02 DOSYASI — Sorgu 5: Şifreyi çöz**
```sql
SELECT
    id,
    ad_soyad,
    pgp_sym_decrypt(tc_kimlik, 'gizli_anahtar_2024') AS tc_kimlik_acik,
    pgp_sym_decrypt(telefon,   'gizli_anahtar_2024') AS telefon_acik,
    email
FROM guvenli_yolcu;
```

"Şimdi gerçek TC numaraları ve telefon numaraları görünüyor. Doğru anahtar
olunca pgp_sym_decrypt şifreyi çözüyor. Bu işlemi sadece anahtara sahip olan
yapabilir — veritabanı yöneticisi bile anahtarı bilmeden okuyamaz.

Şimdi yanlış anahtarla deneyeyim."

**► 02 DOSYASI — Sorgu 6: Yanlış anahtarla dene**
```sql
SELECT pgp_sym_decrypt(tc_kimlik, 'yanlis_anahtar')
FROM guvenli_yolcu
WHERE id = 1;
```

"'Wrong key or corrupt data' hatası verdi. Yanlış anahtarla veri açılamıyor.
Bu kasıtlı bir hata — şifrelemenin doğru çalıştığını ispatlıyor.

Şimdi şifre doğrulamayı göstereyim."

**► 02 DOSYASI — Sorgu 7: Şifre doğrulama**
```sql
SELECT
    ad_soyad,
    'sifre123'                                        AS girilen_sifre,
    (sifre_hash = crypt('sifre123', sifre_hash))      AS dogru_sifre,
    (sifre_hash = crypt('yanlis_sifre', sifre_hash))  AS yanlis_sifre
FROM guvenli_yolcu
WHERE ad_soyad = 'Ahmet Yılmaz';
```

"Tek satırda her iki sonucu da görüyoruz. dogru_sifre kolonu true,
yanlis_sifre kolonu false döndü. Şifre veritabanında hiçbir zaman
düz metin olarak bulunmuyor, sadece hash'i var. Kullanıcı giriş yaparken
sistem girilen şifreyi hash'leyip sakladığıyla karşılaştırıyor."

---

## ADIM 3 — SQL INJECTION TESTLERİ

"Üçüncü adım SQL injection. Bu en yaygın veritabanı saldırı türlerinden biri.
OWASP'ın yani web güvenliği organizasyonunun yayımladığı en tehlikeli 10
açıktan biri.

Saldırı mantığı şu: kullanıcı girdi alanına SQL kodu yazıyor, uygulama
bunu direkt sorguya ekliyor, veritabanı bu kodu çalıştırıyor.
Test için küçük bir kullanıcı tablosu oluşturuyorum."

**► 03 DOSYASI — Sorgu 1: Test tablosu**
```sql
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
```

"CREATE TABLE ve INSERT satırları geldi, tablo oluştu ve 4 kayıt eklendi.
Normal bir kullanıcı girişini çalıştırayım önce."

**► 03 DOSYASI — Sorgu 2: Normal kullanım**
```sql
SELECT * FROM kullanici_giris
WHERE kullanici = 'bekir';
```

"Sadece bekir'in satırı geldi — normal ve beklenen davranış bu.
Şimdi saldırıya geçeyim."

**► 03 DOSYASI — Sorgu 3: Saldırı 1 — OR injection**
```sql
SELECT * FROM kullanici_giris
WHERE kullanici = '' OR '1'='1';
```

"Bakın hocam — 4 kaydın hepsi geldi! Saldırgan kullanıcı adı olarak
tek tırnak, OR, 1 eşittir 1 yazdı. Bu ifade her zaman true ürettiğinden
WHERE koşulu her satır için true oluyor ve tüm kayıtlar dönüyor.
Yani saldırgan şifre bilmeden sisteme admin dahil herkesi görebildi.

Saldırı 2: UNION ile başka tablodan veri çalma."

**► 03 DOSYASI — Sorgu 4: Saldırı 2 — UNION injection**
```sql
SELECT id, kullanici, sifre, rol FROM kullanici_giris
WHERE kullanici = '' UNION SELECT 1, rolname, rolname, rolname FROM pg_roles;
```

"Bakın hocam — listenin altında kullanici_giris tablosunun kayıtlarının yanı sıra
pg_roles tablosundaki tüm sistem kullanıcı adları da geldi. Saldırgan
veritabanındaki tüm rolleri, kullanıcıları görebildi. Bu bilgilerle sistemi
çok daha kolay ele geçirebilir.

Şimdi korunma yöntemlerine geçelim."

**► 03 DOSYASI — Sorgu 5: Korunma 1 — parameterized**
```sql
\set guvenli_input '''bekir'''
SELECT * FROM kullanici_giris
WHERE kullanici = :guvenli_input;
```

"Sadece bekir'in kaydı geldi, normal çalıştı. Parameterized query'de
kullanıcı girdisi sorgunun içine gömülmüyor, ayrı parametre olarak gönderiliyor.
Ne yazılırsa yazılsın SQL kodu olarak yorumlanamaz."

**► 03 DOSYASI — Sorgu 6: Korunma 2 — doğrulama fonksiyonu**
```sql
CREATE OR REPLACE FUNCTION guvenli_kullanici_dogrula(giris TEXT)
RETURNS BOOLEAN AS $$
BEGIN
    IF giris ~ '^[a-zA-Z0-9_]+$' THEN
        RETURN TRUE;
    ELSE
        RAISE EXCEPTION 'Geçersiz karakter tespit edildi: %', giris;
        RETURN FALSE;
    END IF;
END;
$$ LANGUAGE plpgsql;

SELECT guvenli_kullanici_dogrula('bekir');

SELECT guvenli_kullanici_dogrula(''' OR ''1''=''1');
```

"İlk sorguda true döndü — bekir güvenli bir girdi.
İkinci sorguda 'Geçersiz karakter tespit edildi' hatası fırladı —
saldırı girişimi engellendi, veritabanına ulaşamadı.
Bu fonksiyon her kullanıcı girdisini veritabanına göndermeden önce
filtreler.

Üçüncü korunma: en az yetki prensibi. rapor_kullanici rolünün sadece
SELECT yetkisi olduğunu doğruluyorum."

**► 03 DOSYASI — Sorgu 7: Korunma 3 — minimum yetki**
```sql
SELECT
    grantee,
    table_name,
    privilege_type
FROM information_schema.role_table_grants
WHERE grantee = 'rapor_kullanici'
ORDER BY table_name, privilege_type;
```

"Tabloya bakıyorum — rapor_kullanici için sadece SELECT görünüyor.
INSERT, UPDATE, DELETE yok. Bu kullanıcı SQL injection saldırısıyla
veri silemez, değiştiremez; sadece okuyabilir. Yetki kısıtlaması
saldırının etkisini sınırlar."

**► 03 DOSYASI — Sorgu 8: Temizlik**
```sql
DROP TABLE IF EXISTS kullanici_giris;
DROP FUNCTION IF EXISTS guvenli_kullanici_dogrula(TEXT);
```

"Tablo ve fonksiyonu temizledim — DROP TABLE ve DROP FUNCTION çalıştı."

---

## ADIM 4 — AUDİT LOGLARI

"Son adım audit logları. MSSQL'de SQL Server Audit özelliği var.
PostgreSQL'de bunu trigger mekanizmasıyla kendim kuruyorum.

Trigger nedir: bir tabloda INSERT, UPDATE veya DELETE yapıldığında
otomatik olarak çalışan fonksiyon. Biz bunu kullanarak her değişikliği
ayrı bir log tablosuna kaydedeceğiz.

Önce log tablosunu oluşturuyorum."

**► 04 DOSYASI — Sorgu 1: Audit log tablosu**
```sql
DROP TABLE IF EXISTS audit_log;

CREATE TABLE audit_log (
    log_id          SERIAL PRIMARY KEY,
    tablo_adi       TEXT,
    islem_tipi      TEXT,
    kullanici       TEXT,
    islem_zamani    TIMESTAMP DEFAULT now(),
    eski_veri       JSONB,
    yeni_veri       JSONB
);
```

"CREATE TABLE geldi, tablo hazır. eski_veri ve yeni_veri kolonları JSONB tipinde —
UPDATE işleminde verinin değişmeden önceki ve sonraki halini saklayacak.
Kim ne zaman ne değiştirdi hepsi burada olacak.

Şimdi trigger fonksiyonunu yazıyorum."

**► 04 DOSYASI — Sorgu 2: Trigger fonksiyonu**
```sql
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
```

"CREATE FUNCTION geldi. TG_OP işlemin tipini tutuyor — INSERT mi, UPDATE mi,
DELETE mi. current_user o anki kullanıcıyı, TG_TABLE_NAME tablo adını otomatik
alıyor. row_to_json ise satırı JSON formatına çeviriyor ki eski ve yeni değerleri
saklayabilelim.

Şimdi bu fonksiyonu tablolara trigger olarak bağlıyorum."

**► 04 DOSYASI — Sorgu 3: Trigger'ları bağla**
```sql
DROP TRIGGER IF EXISTS bookings_audit ON bookings.bookings;
CREATE TRIGGER bookings_audit
    AFTER INSERT OR UPDATE OR DELETE ON bookings.bookings
    FOR EACH ROW EXECUTE FUNCTION audit_trigger_fonksiyon();

DROP TRIGGER IF EXISTS tickets_audit ON bookings.tickets;
CREATE TRIGGER tickets_audit
    AFTER INSERT OR UPDATE OR DELETE ON bookings.tickets
    FOR EACH ROW EXECUTE FUNCTION audit_trigger_fonksiyon();
```

"CREATE TRIGGER geldi — artık bookings ve tickets tablolarında her değişiklik
otomatik olarak loglanacak. Şimdi test edeyim — kayıt ekleyeceğim, güncelleyeceğim,
sileceğim."

**► 04 DOSYASI — Sorgu 4: Test işlemleri**
```sql
INSERT INTO bookings.bookings (book_ref, book_date, total_amount)
VALUES ('TEST01', now(), 5000.00);

UPDATE bookings.bookings
SET total_amount = 7500.00
WHERE book_ref = 'TEST01';

DELETE FROM bookings.bookings
WHERE book_ref = 'TEST01';
```

"INSERT 0 1, UPDATE 1, DELETE 1 geldi. Üç farklı işlem yaptım.
Şimdi bunların log'a düşüp düşmediğine bakayım."

**► 04 DOSYASI — Sorgu 5: Audit loglarını görüntüle**
```sql
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
```

"3 satır geldi. En üstte DELETE, ortada UPDATE, altta INSERT görüyorum.
Bakın UPDATE satırında eski_veri kolonunda total_amount 5000, yeni_veri'de 7500
yazıyor — kim, ne zaman, kaçtan kaça değiştirdi hepsi kayıtta.
kullanici kolonu bekirtop yazıyor — ben yaptım.

Şimdi şüpheli aktivite tespitini göstereyim."

**► 04 DOSYASI — Sorgu 6: Şüpheli aktivite tespiti**
```sql
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
```

"Son 1 saat içinde silme işlemi yapan kullanıcılar listelendi.
bekirtop 1 silme yaptı görünüyor. Gerçek bir sistemde bu sorgu otomatik
alarm mekanizmasına bağlanabilir — mesela 10'dan fazla silme yapılırsa
yöneticiye e-posta gönder gibi."

---

## KAPANIŞ

"Projeyi özetleyeyim hocam.

İlk adımda en az yetki prensibini uygulayarak 3 farklı kullanıcı rolü
oluşturdum. Her kullanıcıya sadece işi için gereken yetkiyi verdim,
bağlantı limiti ve şifre geçerlilik süresi tanımladım.

İkinci adımda pgcrypto eklentisi ile TC kimlik ve telefon bilgilerini
şifreleyerek sakladım. Yanlış anahtarla veri okunamadığını gösterdim.
Şifreler için bcrypt hash kullandım.

Üçüncü adımda 2 farklı SQL injection saldırısını canlı olarak gösterdim —
OR injection ve UNION saldırısı. Ardından parameterized query, giriş
doğrulama fonksiyonu ve en az yetki prensibi ile bu saldırıları
nasıl engellediğimi gösterdim.

Son adımda trigger mekanizmasıyla otomatik audit log sistemi kurdum.
Her INSERT, UPDATE ve DELETE işlemi kimin ne zaman ne değiştirdiğiyle
birlikte kayıt altına alınıyor. Şüpheli aktivite tespiti de ekledi.

Proje 3 bu kadar, teşekkür ederim hocam."
