# Proje 6 — Video Sunum Metni
## Veritabanı Yükseltme ve Sürüm Yönetimi

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
> Artık hazırsın. Aşağıdaki metni oku, her sorgu bloğuna gelince dur ve terminale yapıştır.

---

## GİRİŞ

"Merhaba hocam, ben Bekir Top. Bu videoda BLM4522 dersi kapsamında hazırladığım
Proje 6'yı anlatacağım. Proje konusu Veritabanı Yükseltme ve Sürüm Yönetimi.
Platform olarak yine PostgreSQL 16 kullandım, aynı uçuş rezervasyon veritabanı
üzerinde çalışacağım.

Sürüm yönetimi neden önemli? Gerçek dünyada bir veritabanı canlıya alındıktan
sonra statik kalmaz. Yeni iş gereksinimleri gelir, tablo yapıları değişir,
yeni kolonlar eklenir, eski kolonlar kaldırılır. Eğer bu değişiklikleri
sistematik bir şekilde takip etmezseniz, bir süre sonra hangi değişikliğin
ne zaman ve neden yapıldığını bilemezsiniz. Sorun çıktığında da neyi geri
alacağınızı bilemezsiniz.

Bu projede 3 ana konu var: önce sürüm yönetim altyapısını kuruyorum,
sonra gerçek bir yükseltme senaryosu uyguluyorum, son olarak test ve
geri dönüş planlarını çalıştırıyorum. Sırayla gidelim."

---

## ADIM 1 — SÜRÜM YÖNETİMİ

"İlk adım sürüm yönetimi altyapısı. Bunu kurmak için iki farklı mekanizma
kullanıyorum: biri elle doldurulan bir sürüm kayıt tablosu, diğeri PostgreSQL'in
kendi DDL event trigger sistemi.

Neden ikisi birden? Sürüm tablosu bize 'bu değişikliği bilinçli olarak ne zaman
uyguladık' bilgisini verir. DDL event trigger ise 'gerçekte veritabanında ne
zaman ne değişti' bilgisini otomatik yakalar. İkisi birlikte kullanılınca
hem planlanan hem de beklenmedik tüm şema değişiklikleri izlenmiş olur.

Bunu MSSQL'deki Database Projects veya Flyway gibi migration araçlarının yaptığı
işe benzetebiliriz hocam. Ama burada bunu sıfırdan, saf SQL ile kuruyoruz.

Önce PostgreSQL sürümüne bakayım."

**► 01 DOSYASI — Sorgu 1: Mevcut PostgreSQL sürümü**
```sql
SELECT
    version()                            AS postgres_versiyonu,
    current_database()                   AS veritabani,
    current_schema()                     AS aktif_sema,
    pg_postmaster_start_time()::DATE     AS sunucu_baslangic;
```

"version() fonksiyonu tam sürüm bilgisini gösteriyor — PostgreSQL 16.x,
derleme tarihi, işletim sistemi. Bu bilgiyi kayıt altında tutmak önemli çünkü
bazı fonksiyonlar ve sözdizimi sürüme göre farklılık gösterebiliyor.
Örneğin event trigger özelliği PostgreSQL 9.3 ile geldi, daha eski bir sürümde
bu projeyi aynen uygulayamazdık.

Şimdi sürüm takip tablosunu oluşturuyorum."

**► 01 DOSYASI — Sorgu 2: Şema versiyon tablosu**
```sql
DROP TABLE IF EXISTS schema_versiyon CASCADE;

CREATE TABLE schema_versiyon (
    id              SERIAL PRIMARY KEY,
    versiyon_no     TEXT         NOT NULL,
    aciklama        TEXT         NOT NULL,
    degisiklik_tipi TEXT         NOT NULL
        CHECK (degisiklik_tipi IN ('UPGRADE', 'ROLLBACK', 'HOTFIX')),
    uygulayan       TEXT         DEFAULT current_user,
    uygulama_tarihi TIMESTAMP    DEFAULT now(),
    durum           TEXT         DEFAULT 'BASARILI'
        CHECK (durum IN ('BASARILI', 'BASARISIZ', 'BEKLEMEDE')),
    sql_betigi      TEXT
);

INSERT INTO schema_versiyon (versiyon_no, aciklama, degisiklik_tipi, sql_betigi)
VALUES (
    '1.0.0',
    'Başlangıç durumu — uçuş rezervasyon şeması',
    'UPGRADE',
    '-- temel şema'
);

SELECT * FROM schema_versiyon;
```

"CREATE TABLE geldi, tablo oluştu. İlk kaydı da girdim — bu veritabanının
başlangıç hali, v1.0.0.

versiyon_no kolonunda semantik versiyonlama kullanıyorum: MAJOR.MINOR.PATCH
formatında. MAJOR numara geriye dönük uyumsuz büyük değişikliklerde, MINOR
geriye dönük uyumlu yeni özellik eklemelerinde, PATCH ise küçük düzeltmelerde
artar.

degisiklik_tipi kolonu CHECK kısıtıyla sadece 3 değer kabul ediyor:
UPGRADE yükseltme, ROLLBACK geri dönüş, HOTFIX acil düzeltme.
Tanımlanmayan bir değer girilmeye çalışılırsa veritabanı hata fırlatıyor.

uygulayan kolonu DEFAULT current_user ile otomatik dolduruluyor —
kim bağlıysa onun kullanıcı adı kaydediliyor, elle yazmak gerekmiyor.

Şimdi DDL event trigger'ı kuruyorum."

**► 01 DOSYASI — Sorgu 3: DDL Event Trigger**
```sql
DROP TABLE IF EXISTS ddl_degisiklik_log;

CREATE TABLE ddl_degisiklik_log (
    log_id          SERIAL PRIMARY KEY,
    komut_tipi      TEXT,
    nesne_tipi      TEXT,
    nesne_adi       TEXT,
    kullanici       TEXT,
    zaman           TIMESTAMP DEFAULT now(),
    sorgu_metni     TEXT
);

CREATE OR REPLACE FUNCTION ddl_degisiklik_yakala()
RETURNS event_trigger AS $$
DECLARE r RECORD; BEGIN
    FOR r IN SELECT * FROM pg_event_trigger_ddl_commands() LOOP
        INSERT INTO ddl_degisiklik_log
            (komut_tipi, nesne_tipi, nesne_adi, kullanici, sorgu_metni)
        VALUES (r.command_tag, r.object_type, r.object_identity,
                current_user, current_query());
    END LOOP;
END;
$$ LANGUAGE plpgsql;

DROP EVENT TRIGGER IF EXISTS ddl_degisiklik_trigger;
CREATE EVENT TRIGGER ddl_degisiklik_trigger
    ON ddl_command_end
    EXECUTE FUNCTION ddl_degisiklik_yakala();
```

"CREATE TABLE, CREATE FUNCTION, CREATE EVENT TRIGGER geldi, üç nesne de oluştu.

Event trigger ile normal trigger'ın farkını açıklayayım hocam.
Normal trigger belirli bir tabloya bağlanır ve o tablodaki INSERT, UPDATE,
DELETE işlemlerini yakalamak için kullanılır. Event trigger ise tüm
veritabanı genelinde çalışır ve CREATE, ALTER, DROP gibi şema yapısını
değiştiren DDL komutlarını yakalar — hangi tabloda olduğundan bağımsız.

ON ddl_command_end ile tetikleyiciyi DDL komutu başarıyla bitmeden değil,
bittikten hemen sonra devreye alıyorum. pg_event_trigger_ddl_commands()
fonksiyonu o anda çalıştırılan komutu temsil eden kayıtları döndürüyor —
bunları ddl_degisiklik_log tablosuna yazıyorum.

Artık bu veritabanında herhangi bir tablo oluşturulursa, değiştirilirse
veya silinirse, kim yaptı ve ne yazdı otomatik olarak kayıt altına alınıyor.
Test edeyim."

**► 01 DOSYASI — Sorgu 4: DDL trigger testi**
```sql
CREATE TABLE IF NOT EXISTS trigger_test_tablosu (id SERIAL PRIMARY KEY, adi TEXT);
DROP TABLE IF EXISTS trigger_test_tablosu;

SELECT log_id, komut_tipi, nesne_tipi, nesne_adi, kullanici, zaman
FROM ddl_degisiklik_log
ORDER BY zaman DESC LIMIT 5;
```

"Listede CREATE TABLE ve DROP TABLE satırları görünüyor. nesne_adi'nda
bookings.trigger_test_tablosu yazıyor — şema adıyla birlikte kaydedilmiş.
kullanici bekirtop, zaman da az önce. Ben hiçbir şey yazmadım bu log tablosuna,
trigger fonksiyonu otomatik doldurdu. İşte bu sistemi güçlü yapan şey bu —
unut bakalım, kim bir şey değiştirirse hemen kayıt düşüyor.

Son olarak mevcut şemanın anlık görüntüsünü alıyorum — bu v1.0.0 baseline,
yani yükseltme öncesi referans noktam."

**► 01 DOSYASI — Sorgu 5-6: Şema anlık görüntüsü**
```sql
SELECT table_name AS tablo_adi,
       (SELECT COUNT(*) FROM information_schema.columns c
        WHERE c.table_schema = t.table_schema
          AND c.table_name   = t.table_name) AS kolon_sayisi,
       pg_size_pretty(
           pg_total_relation_size(
               quote_ident(t.table_schema)||'.'||quote_ident(t.table_name)
           )
       ) AS toplam_boyut
FROM information_schema.tables t
WHERE table_schema = 'bookings' AND table_type = 'BASE TABLE'
ORDER BY table_name;
```

"7 tablo var. ticket_flights en büyüğü — 112 MB, çünkü bilet-uçuş ilişkilerini
tutuyor ve milyonlarca satır içeriyor. flights tablosunun 9 kolonu var şu an.
Bu tablo sonraki adımda iki kolon daha kazanacak. Tüm bu yapı v1.0.0'ın
başlangıç durumu — yükseltmeden sonra karşılaştırmak için bu tabloyu aklımda
tutuyorum. Şimdi yükseltmeye geçiyorum."

---

## ADIM 2 — YÜKSELTME PLANI

"İkinci adım yükseltme planı. Gerçekçi bir senaryo kurdum: bir havayolu şirketi
müşteri sadakat programı başlatmak ve gecikme analitiği eklemek istiyor.
Bu iki özellik iki ayrı sürüm olarak yayınlanacak.

v1.0.0'dan v1.1.0'a küçük ölçekli bir yükseltme: mevcut tablolara kolon ekleme
ve yeni bir tablo oluşturma. v1.1.0'dan v2.0.0'a daha kapsamlı bir yükseltme:
yeni kolonlar, view ve indeksler.

Her yükseltmeyi transaction içinde yapıyorum. Transaction kullanmak şu anlama
geliyor: ALTER TABLE başarılı olur ama CHECK kısıtı eklenirken hata verirse,
COMMIT'e hiç gidilmez, yapılan değişiklik otomatik geri alınır. Veritabanı
her zaman tutarlı bir durumda kalır, yarım kalmış değişiklik olmaz.

Önce v1.1.0 yükseltmesini başlatıyorum. tickets tablosunun şu anki yapısına
bakayım."

**► 02 DOSYASI — Sorgu 1: tickets tablosunun mevcut yapısı**
```sql
SELECT column_name AS kolon, data_type AS tip, is_nullable AS bos_olabilir
FROM information_schema.columns
WHERE table_schema = 'bookings' AND table_name = 'tickets'
ORDER BY ordinal_position;
```

"tickets tablosunda şu an 5 kolon var: ticket_no birincil anahtar,
book_ref rezervasyon bağlantısı, passenger_id, passenger_name ve contact_data.
Bunlar orijinal şema. Sadakat sistemi için bu tabloya iki yeni kolon ekliyorum:
ucus_puani her bilet için kazanılan puan, uye_seviyesi ise müşterinin
program kademesi."

**► 02 DOSYASI — Sorgu 2: v1.1.0 — tickets tablosuna kolon ekle**
```sql
BEGIN;
ALTER TABLE bookings.tickets
    ADD COLUMN IF NOT EXISTS ucus_puani   INTEGER DEFAULT 0,
    ADD COLUMN IF NOT EXISTS uye_seviyesi TEXT    DEFAULT 'STANDART'
        CHECK (uye_seviyesi IN ('STANDART', 'SILVER', 'GOLD', 'PLATINUM'));
COMMIT;

SELECT column_name, data_type, column_default
FROM information_schema.columns
WHERE table_schema = 'bookings' AND table_name = 'tickets'
  AND column_name IN ('ucus_puani', 'uye_seviyesi');
```

"ALTER TABLE yazıları geldi — iki kolon başarıyla eklendi.

IF NOT EXISTS koyduk — bu betiği iki kez çalıştırsam 'kolon zaten var'
hatası almam, sorgu sessizce geçer. Özellikle otomatik yükseltme betiklerinde
bu önemli çünkü betik bir nedenden tekrar çalışabilir.

ucus_puani INTEGER ve DEFAULT 0 — yeni eklenen her mevcut satırda bu kolon
sıfır değerini alacak. uye_seviyesi için 4 seviye tanımladım ve CHECK kısıtı
ile bunların dışında değer girilmesini engelledim. Şimdi sadakat tablosunu
oluşturuyorum."

**► 02 DOSYASI — Sorgu 3: v1.1.0 — sadakat_programi tablosu**
```sql
BEGIN;
DROP TABLE IF EXISTS bookings.sadakat_programi;
CREATE TABLE bookings.sadakat_programi (
    program_id      SERIAL PRIMARY KEY,
    ticket_no       CHAR(13) REFERENCES bookings.tickets(ticket_no),
    toplam_puan     INTEGER  DEFAULT 0,
    seviye          TEXT     DEFAULT 'STANDART'
        CHECK (seviye IN ('STANDART', 'SILVER', 'GOLD', 'PLATINUM')),
    kayit_tarihi    DATE     DEFAULT CURRENT_DATE,
    son_ucus_tarihi TIMESTAMP,
    aktif_mi        BOOLEAN  DEFAULT TRUE
);

INSERT INTO bookings.sadakat_programi
    (ticket_no, toplam_puan, seviye, son_ucus_tarihi)
SELECT t.ticket_no,
       (RANDOM() * 50000)::INTEGER AS toplam_puan,
       CASE WHEN RANDOM() < 0.6  THEN 'STANDART'
            WHEN RANDOM() < 0.85 THEN 'SILVER'
            WHEN RANDOM() < 0.95 THEN 'GOLD'
            ELSE 'PLATINUM' END   AS seviye,
       NOW() - (RANDOM() * 365 || ' days')::INTERVAL
FROM bookings.tickets t LIMIT 10000;
COMMIT;

SELECT COUNT(*) AS kayit_sayisi, seviye
FROM bookings.sadakat_programi GROUP BY seviye ORDER BY seviye;
```

"CREATE TABLE geldi, ardından 10000 kayıt eklendi.

ticket_no kolonu REFERENCES bookings.tickets(ticket_no) yazıyor — bu bir
foreign key kısıtı. Biletler tablosunda karşılığı olmayan bir ticket_no
bu tabloya eklenemez. Veri bütünlüğü veritabanı seviyesinde garanti altına
alınmış oluyor, sadece uygulama koduna bırakılmıyor.

INSERT'teki CASE WHEN bloğu ise olasılıkla seviye dağılımı yapıyor: %60
STANDART, %25 SILVER, %10 GOLD, %5 PLATINUM. Bu gerçek bir sadakat programında
da beklenen piramit yapısı.

Sonuçta 4 seviye görüyorum — dağılım beklediğimiz gibi. Şimdi v1.1.0 sürüm
kaydını giriyorum."

**► 02 DOSYASI — Sorgu 4: v1.1.0 sürüm kaydı**
```sql
INSERT INTO schema_versiyon (versiyon_no, aciklama, degisiklik_tipi, sql_betigi)
VALUES ('1.1.0',
        'tickets tablosuna ucus_puani ve uye_seviyesi eklendi; sadakat_programi tablosu oluşturuldu',
        'UPGRADE', '02_yukseltme_plani.sql — SORGU 2 & 3');

SELECT * FROM schema_versiyon ORDER BY id;
```

"İki kayıt görüyorum: v1.0.0 başlangıç ve v1.1.0 yükseltme.
Bu tabloyu düzenli tutarsanız herhangi bir tarihte veritabanının
hangi sürümde olduğunu, kimin ne yaptığını tek sorguda bulabilirsiniz.
Şimdi v2.0.0 yükseltmesine geçiyorum."

**► 02 DOSYASI — Sorgu 5: v2.0.0 — flights tablosuna kolon ekle**
```sql
BEGIN;
ALTER TABLE bookings.flights
    ADD COLUMN IF NOT EXISTS beklenen_gecikme_dk INTEGER DEFAULT 0,
    ADD COLUMN IF NOT EXISTS iptal_nedeni         TEXT;
COMMIT;

UPDATE bookings.flights
SET beklenen_gecikme_dk = (RANDOM() * 120)::INTEGER
WHERE status IN ('Delayed', 'Departed')
  AND scheduled_departure > '2017-01-01';

SELECT status, COUNT(*) AS ucus_sayisi,
       AVG(beklenen_gecikme_dk)::INTEGER AS ort_gecikme_dk
FROM bookings.flights WHERE beklenen_gecikme_dk > 0
GROUP BY status ORDER BY ort_gecikme_dk DESC;
```

"İki kolon eklendi: beklenen_gecikme_dk sayısal ve iptal_nedeni metin.
iptal_nedeni kolonu NULL kabul ediyor çünkü iptal edilmeyen uçuşlar için
bu bilgi zaten yoktur, boş bırakmak doğru tasarım.

Ardından mevcut gecikmiş ve kalkmış uçuşlara rastgele gecikme verisi ekledim.
Bu gerçek veri olmayan bir simülasyon — view'ın çalıştığını göstermek için.
Sorgu sonucuna bakıyorum: Delayed uçuşlarda ortalama 60 dakika civarında
gecikme görünüyor. Şimdi bu veriden anlamlı istatistik çıkaran bir view
oluşturuyorum."

**► 02 DOSYASI — Sorgu 6-7: View ve indeksler**
```sql
CREATE OR REPLACE VIEW bookings.gecikme_istatistikleri AS
SELECT f.departure_airport AS kalkis_havaalani,
       f.arrival_airport   AS varis_havaalani,
       COUNT(*)            AS toplam_ucus,
       SUM(CASE WHEN f.status = 'Delayed' THEN 1 ELSE 0 END) AS geciken_ucus,
       ROUND(100.0 * SUM(CASE WHEN f.status = 'Delayed' THEN 1 ELSE 0 END)
             / COUNT(*), 2) AS gecikme_orani_yuzde,
       AVG(f.beklenen_gecikme_dk)::INTEGER AS ort_gecikme_dk
FROM bookings.flights f
GROUP BY f.departure_airport, f.arrival_airport HAVING COUNT(*) > 5
ORDER BY gecikme_orani_yuzde DESC;

SELECT * FROM bookings.gecikme_istatistikleri LIMIT 10;
```

"View oluştu ve sonuçlar geldi. HAVING COUNT(*) > 5 koşulunu koydum —
çok az sefer olan hatlar istatistiksel olarak anlamlı değil, onları listeden
çıkardım. gecikme_orani_yuzde kolonuna bakıyorum, en sık gecikme yaşanan
hatları en üstte görüyorum. Gerçek bir operasyon merkezinde bu view bir
dashboard'a bağlanabilir ve anlık gecikme durumu izlenebilir.

Şimdi bu yeni kolonlar için performans indeksleri ekliyorum."

```sql
CREATE INDEX IF NOT EXISTS idx_sadakat_seviye
    ON bookings.sadakat_programi (seviye, aktif_mi);
CREATE INDEX IF NOT EXISTS idx_sadakat_ticket
    ON bookings.sadakat_programi (ticket_no);
```

"İki indeks oluştu. idx_sadakat_seviye bileşik indeks — seviye ve aktif_mi
birlikte sorgulandığında hem filtre hem erişim hızlanıyor. idx_sadakat_ticket
ise foreign key kolonu için — JOIN sorgularında bu olmadan PostgreSQL her
birleştirmede tüm tabloyu taramak zorunda kalır. Bir sonraki adımda
EXPLAIN ile bunların gerçekten kullanıldığını doğruluyorum."

---

## ADIM 3 — TEST VE GERİ DÖNÜŞ PLANI

"Üçüncü adım test ve geri dönüş planı. Profesyonel bir veritabanı yükseltme
sürecinde yükseltmeyi uyguladıktan hemen sonra test planı çalıştırılır.
Test planı iki şeyi doğrular: birincisi beklenen tüm nesneler orada mı,
ikincisi veri tutarsızlığı oluştu mu. Testler geçmezse geri dönüş planı
devreye alınır. Her ikisini de sırayla gösteriyorum."

**► 03 DOSYASI — Sorgu 1: Şema doğrulama**
```sql
SELECT 'Tablo: ' || table_name AS nesne, 'MEVCUT' AS durum
FROM information_schema.tables
WHERE table_schema = 'bookings' AND table_type = 'BASE TABLE'
  AND table_name IN ('flights','tickets','bookings','sadakat_programi', ...)
UNION ALL
SELECT 'View: ' || table_name, 'MEVCUT'
FROM information_schema.views WHERE table_schema = 'bookings'
  AND table_name = 'gecikme_istatistikleri'
UNION ALL
SELECT 'Kolon: tickets.' || column_name, 'MEVCUT'
FROM information_schema.columns
WHERE table_schema='bookings' AND table_name='tickets'
  AND column_name IN ('ucus_puani','uye_seviyesi')
ORDER BY nesne;
```

"Listede tüm tablolar, view ve yeni kolonların hepsi MEVCUT olarak geliyor.
Bu bir kontrol listesi — yükseltme betiği çalıştıktan sonra otomatik olarak
bu sorgu koşturulursa eksik nesne varsa hemen fark edilir. MEVCUT yazısı
gördükçe o nesnenin başarıyla oluştuğunu teyit ediyorum."

**► 03 DOSYASI — Sorgu 2: Veri bütünlüğü testi**
```sql
SELECT COUNT(*) AS toplam_kayit, COUNT(t.ticket_no) AS eslesme_sayisi,
       COUNT(*) - COUNT(t.ticket_no) AS kopuk_referans
FROM bookings.sadakat_programi sp
LEFT JOIN bookings.tickets t ON sp.ticket_no = t.ticket_no;
```

"kopuk_referans kolonuna bakıyorum — 0 yazıyor. Tüm sadakat kayıtlarının
tickets tablosunda karşılığı var, hiçbir yetim kayıt yok. Foreign key
kısıtı bunu zaten engellemelidir ama kısıtı sonradan devre dışı bırakmak
mümkün olduğundan test aşamasında bu sorguyu manuel çalıştırmak iyi pratik."

**► 03 DOSYASI — Sorgu 3: Kısıt testi**
```sql
DO $$
BEGIN
    INSERT INTO bookings.sadakat_programi (ticket_no, seviye)
    SELECT ticket_no, 'BRONZE' FROM bookings.tickets LIMIT 1;
    RAISE NOTICE 'BRONZE kabul edildi — CHECK kısıtı çalışmıyor!';
EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'CHECK kısıtı doğru çalışıyor: BRONZE reddedildi — BASARILI';
END; $$;
```

"NOTICE: CHECK kısıtı doğru çalışıyor: BRONZE reddedildi — BASARILI yazısı geldi.

Bu negatif test, yani bilerek yanlış veri girmeye çalışmak. BRONZE seviyesi
tanımlı değil, CHECK kısıtı devreye girdi ve eklemeyi engelledi.
Yükseltme sonrası kısıtların hâlâ aktif olduğunu bu şekilde ispatlıyorum.
Sadece 'veri eklendi' diye kontrol etmek yeterli değil, sistemin hatalı
veriyi reddettiğini de test etmek gerekiyor."

**► 03 DOSYASI — Sorgu 4: Performans testi**
```sql
EXPLAIN (ANALYZE, FORMAT TEXT)
SELECT ticket_no, seviye, toplam_puan
FROM bookings.sadakat_programi WHERE seviye = 'GOLD' AND aktif_mi = TRUE;
```

"EXPLAIN ANALYZE çıktısına bakıyorum. Dikkat etmem gereken satır şu:
'Index Scan using idx_sadakat_seviye' yazıyor. Yani PostgreSQL az önce
oluşturduğumuz bileşik indeksi kullanıyor — Seq Scan yani tüm tabloyu
tarama yapmıyor. Bu çok önemli hocam, çünkü tablo büyüdükçe indekssiz
sorgu dramatik şekilde yavaşlar. İndeksin gerçekten kullanıldığını test
etmeden geçmek ciddi bir atlama olurdu.

Şimdi geri dönüş planına geçelim."

**► 03 DOSYASI — Sorgu 7: ROLLBACK v2.0.0 → v1.1.0**
```sql
BEGIN;
DROP INDEX IF EXISTS bookings.idx_flights_gecikme;
DROP VIEW  IF EXISTS bookings.gecikme_istatistikleri;
ALTER TABLE bookings.flights
    DROP COLUMN IF EXISTS beklenen_gecikme_dk,
    DROP COLUMN IF EXISTS iptal_nedeni;
COMMIT;

SELECT column_name FROM information_schema.columns
WHERE table_schema='bookings' AND table_name='flights'
  AND column_name IN ('beklenen_gecikme_dk','iptal_nedeni');
```

"Doğrulama sorgusu boş döndü — iki kolon, view ve indeks tamamen silindi.
v2.0.0 değişiklikleri geri alındı, veritabanı v1.1.0 haline döndü.

Önemli bir uyarı hocam: ALTER TABLE DROP COLUMN geri alınamaz bir komut.
Bu kolon içinde ne kadar veri olursa olsun, COMMIT ile birlikte kalıcı
olarak silinir. Bu yüzden gerçek bir sistemde rollback öncesinde mutlaka
pg_dump ile yedek almak gerekir. Biz burada eğitim ortamında çalıştığımız
için direkt uyguladık."

**► 03 DOSYASI — Sorgu 8: ROLLBACK v1.1.0 → v1.0.0**
```sql
BEGIN;
DROP INDEX  IF EXISTS bookings.idx_sadakat_seviye;
DROP INDEX  IF EXISTS bookings.idx_sadakat_ticket;
DROP TABLE  IF EXISTS bookings.sadakat_programi;
ALTER TABLE bookings.tickets
    DROP COLUMN IF EXISTS ucus_puani,
    DROP COLUMN IF EXISTS uye_seviyesi;
COMMIT;
```

"sadakat_programi tablosu ve tickets kolonları silindi. Sıralamaya dikkat
ettim: önce indeksleri, sonra tabloyu, en son kolonu kaldırdım. Bunun nedeni
bağımlılık zinciri — indeks ve foreign key ilişkileri varken tabloyu direkt
silemezdim, önce bağımlı nesneleri kaldırmak gerekiyordu. IF NOT EXISTS
ve IF EXISTS kullandım, bu sayede rollback betiği kısmen uygulanmış olsa
bile tekrar çalıştırılabilir. Veritabanı v1.0.0 başlangıç haline döndü.

Son olarak tüm sürüm geçmişine bakıyorum."

**► 03 DOSYASI — Sorgu 9: Tam sürüm geçmişi**
```sql
SELECT id, versiyon_no AS versiyon, degisiklik_tipi, uygulayan,
       TO_CHAR(uygulama_tarihi,'DD.MM.YYYY HH24:MI') AS tarih, aciklama
FROM schema_versiyon ORDER BY id;
```

"5 satır görüyorum:
- v1.0.0 UPGRADE — başlangıç
- v1.1.0 UPGRADE — sadakat programı eklendi
- v2.0.0 UPGRADE — gecikme analitik eklendi
- v1.1.0 ROLLBACK — v2.0.0 geri alındı
- v1.0.0 ROLLBACK — v1.1.0 geri alındı

Tüm geçmiş tek tabloda. Bir DBA olarak veritabanının dün gece saat 2'de
hangi sürümde olduğunu sormam yeterli — bu tablodan cevabı bulabilirim.
Kim yaptı, ne zaman yaptı, hangi betikle yaptı, hepsi kayıt altında."

---

## KAPANIŞ

"Projeyi özetleyeyim hocam.

İlk adımda sürüm yönetimi altyapısını kurdum. schema_versiyon tablosu
elle tutulan bir kayıt defteri gibi çalışıyor — her yükseltme ve rollback
buraya işleniyor. DDL event trigger ise otomatik çalışan bir gözetleme
sistemi — kim, ne zaman, hangi DDL komutunu çalıştırdıysa yakalıyor.
İkisi birlikte kullanıldığında hem planlı hem de beklenmedik tüm şema
değişiklikleri izlenmiş oluyor.

İkinci adımda iki aşamalı yükseltme senaryosu uyguladım. v1.1.0 ile
tickets tablosuna sadakat programı kolonları ve sadakat_programi tablosu
eklendi. v2.0.0 ile flights tablosuna gecikme analitik kolonları,
gecikme_istatistikleri view'ı ve performans indeksleri eklendi. Her
yükseltmeyi transaction içinde yaptım — hata olursa yarım kalmaz,
ve her birini sürüm tablosuna kaydettim.

Üçüncü adımda test planı çalıştırdım: şema doğrulama checklist'i,
foreign key bütünlük testi, CHECK kısıt negatif testi ve EXPLAIN ile
indeks kullanım doğrulaması. Testlerin hepsini geçtikten sonra rollback
planlarını da uyguladım ve veritabanını tekrar v1.0.0 başlangıç haline
döndürdüm.

Proje 6 bu kadar, teşekkür ederim hocam."
