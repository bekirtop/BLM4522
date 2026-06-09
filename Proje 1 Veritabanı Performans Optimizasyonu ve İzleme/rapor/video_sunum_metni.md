# Proje 1 — Video Sunum Metni
## Veritabanı Performans Optimizasyonu ve İzleme

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
Proje 1'i anlatacağım. Proje konusu Veritabanı Performans Optimizasyonu ve İzleme.
Platform olarak PostgreSQL 16 kullandım, macOS üzerinde çalıştım.

Önce kullandığım veritabanını tanıtayım. postgrespro.com sitesinden indirdiğim
bir uçuş rezervasyon veritabanı bu. İçinde uçaklar, havalimanları, rezervasyonlar,
biletler ve uçuş bilgileri var. Kaç satır olduğuna bakalım."

```sql
SELECT relname AS tablo, n_live_tup AS satir_sayisi
FROM pg_stat_user_tables
ORDER BY n_live_tup DESC;
```

"Görüldüğü gibi ticket_flights tablosunda 2 milyon 360 bin satır var,
bookings tablosunda 593 bin satır var. Yani gerçekten büyük bir veri seti bu.
Bu kadar büyük bir veritabanında yanlış yazılmış tek bir sorgu dakikalarca
sürebilir, sunucuyu kilitleyebilir. Performans optimizasyonunun önemi tam
da buradan geliyor. Şimdi adım adım gidelim."

---

## ADIM 1 — VERİTABANI İZLEME

"İlk adım izleme. Bir şeyi optimize etmeden önce neyin yavaş olduğunu
bilmem lazım. Bunun için pg_stat_statements eklentisini kullanıyorum.

Bunu MSSQL'deki SQL Profiler gibi düşünebilirsiniz hocam. Çalışan her sorguyu
kaydediyor, kaç kez çalıştırıldığını ve ortalama kaç milisaniye sürdüğünü tutuyor.
Ben de postgresql.conf dosyasına bu eklentiyi ekleyip servisi yeniden başlattım,
şu an aktif durumda. Şimdi aktif ediyorum."

**► 01 DOSYASI — Sorgu 1: Eklentiyi aktif et**
```sql
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
```

"Şimdi en yavaş sorguları listeliyorum."

**► 01 DOSYASI — Sorgu 2: En yavaş sorgular**
```sql
SELECT
    LEFT(query, 80)       AS sorgu,
    calls                 AS cagri_sayisi,
    ROUND(mean_exec_time::numeric, 3) AS ort_sure_ms,
    ROUND(total_exec_time::numeric, 3) AS toplam_sure_ms
FROM pg_stat_statements
ORDER BY mean_exec_time DESC
LIMIT 10;
```

"Burada her satır bir sorgu. calls kolonunda kaç kez çalıştırıldığı yazıyor.
ort_sure_ms ise ortalama kaç milisaniye sürdüğü. En üsttekiler en yavaşlar,
bunlar optimizasyon gerektiren sorgular.

Bir de şunu çalıştırayım — tablolardaki tarama istatistiklerine bakacağım."

**► 01 DOSYASI — Sorgu 3: Tablo tarama istatistikleri**
```sql
SELECT
    schemaname        AS sema,
    relname           AS tablo_adi,
    seq_scan          AS tam_tablo_tarama,
    idx_scan          AS index_ile_erisim,
    n_live_tup        AS satir_sayisi
FROM pg_stat_user_tables
ORDER BY seq_scan DESC
LIMIT 10;
```

"seq_scan tam tablo taraması demek hocam. Yani index yoksa veritabanı tablonun
başından sonuna her satırı tek tek okuyor. 2 milyonluk tabloda bu çok pahalı bir işlem.
idx_scan ise index üzerinden gitti demek, çok daha hızlı. seq_scan sayısı yüksek
olan tablolara index eklememiz gerekiyor.

Bir de aktif bağlantılara bakayım. MSSQL'deki Activity Monitor'ün karşılığı bu."

**► 01 DOSYASI — Sorgu 4: Aktif bağlantılar**
```sql
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
```

"Son olarak cache hit oranına bakayım."

**► 01 DOSYASI — Sorgu 5: Cache hit oranı**
```sql
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
```

"Burada cache hit oranını görüyoruz. Oran yüksekse veriye bellekten ulaşılıyor,
diskten değil. Diskten okumak bellekten okumaktan çok daha yavaş.
İdeal hedef yüzde 99'un üstü. Oran düşükse sunucuya RAM eklemek
veya gereksiz sorgu sayısını azaltmak gerekiyor."

---

## ADIM 2 — İNDEKS YÖNETİMİ

"İkinci adım index yönetimi. Bu adım projenin en kritik kısmı.

Index'i şöyle açıklayayım hocam: elinizde 500 sayfalık bir telefon rehberi var,
Ahmet Yılmaz'ı arıyorsunuz. Index yoksa en baştan son sayfaya kadar her ismi
okursunuz. Ama rehberin sonundaki alfabetik dizine bakarsanız Y harfine direkt
atlarsınız. Veritabanı indexi de tam olarak bu işi yapıyor. 2 milyon satırda
birini bulmak için hepsini okumak yerine direkt o satıra atlıyor.

Önce mevcut indexlere bakayım."

**► 02 DOSYASI — Sorgu 1: Mevcut indexler**
```sql
SELECT
    schemaname  AS sema,
    tablename   AS tablo,
    indexname   AS index_adi,
    indexdef    AS tanim
FROM pg_indexes
WHERE schemaname = 'bookings'
ORDER BY tablename;
```

"Şimdi gerçek farkı göstermek için EXPLAIN ANALYZE kullanacağım.
Bu komut sorgunun nasıl çalıştığını adım adım gösteriyor.
Önce index olmadan çalıştırıyorum."

**► 02 DOSYASI — Sorgu 2: Index YOK — ÖNCE süre**
```sql
EXPLAIN ANALYZE
SELECT tf.ticket_no, tf.flight_id, tf.amount
FROM bookings.ticket_flights tf
WHERE tf.amount > 50000;
```

"Bakın — 'Seq Scan on ticket_flights' yazıyor. Sequential scan yani baştan sona
tüm tabloyu okudu. Execution Time'a bakıyorum — yaklaşık 300-400 milisaniye.
2 milyon satırı tek tek okuyunca bu kadar sürüyor.

Şimdi amount kolonuna index ekliyorum."

**► 02 DOSYASI — Sorgu 3: Index EKLE**
```sql
CREATE INDEX idx_ticket_flights_amount
    ON bookings.ticket_flights (amount);
```

"Aynı sorguyu tekrar çalıştırıyorum."

**► 02 DOSYASI — Sorgu 4: Index VAR — SONRA süre**
```sql
EXPLAIN ANALYZE
SELECT tf.ticket_no, tf.flight_id, tf.amount
FROM bookings.ticket_flights tf
WHERE tf.amount > 50000;
```

"Şimdi 'Bitmap Index Scan' yazıyor — index kullandı. Execution Time'a bakıyorum,
30 milisaniyeye düştü. Hiçbir sorguyu değiştirmedim, sadece index ekledim,
bu kadar fark oluştu.

Bir örnek daha göstereyim, flights tablosunda tarih filtresiyle.
Önce index yok."

**► 02 DOSYASI — Sorgu 5: flights tarih filtresi — index YOK**
```sql
EXPLAIN ANALYZE
SELECT flight_id, flight_no, scheduled_departure, status
FROM bookings.flights
WHERE scheduled_departure BETWEEN '2017-01-01' AND '2017-06-01';
```

**► 02 DOSYASI — Sorgu 5b: flights'a tarih indexi ekle**
```sql
CREATE INDEX idx_flights_departure
    ON bookings.flights (scheduled_departure);
```

**► 02 DOSYASI — Sorgu 5c: flights tarih filtresi — index VAR**
```sql
EXPLAIN ANALYZE
SELECT flight_id, flight_no, scheduled_departure, status
FROM bookings.flights
WHERE scheduled_departure BETWEEN '2017-01-01' AND '2017-06-01';
```

"Index sonrası çok daha hızlı oldu. Seq Scan yerine Bitmap Index Scan görüyoruz.

Şimdi bileşik index örneği — iki kolonla birlikte sorgulama yapıldığında
iki kolonlu index daha verimli olur."

**► 02 DOSYASI — Sorgu 6: Bileşik index**
```sql
CREATE INDEX idx_flights_status_departure
    ON bookings.flights (status, scheduled_departure);

EXPLAIN ANALYZE
SELECT flight_id, flight_no, scheduled_departure
FROM bookings.flights
WHERE status = 'Arrived'
  AND scheduled_departure > '2017-06-01';
```

"Şimdi de kullanılmayan indexleri bulayım. Index eklemek her zaman iyi değil hocam.
Her index disk kaplar ve tabloya veri yazıldığında bu indexlerin de güncellenmesi
gerekir — bu yazma işlemlerini yavaşlatır."

**► 02 DOSYASI — Sorgu 7: Kullanılmayan indexler**
```sql
SELECT
    schemaname   AS sema,
    relname      AS tablo,
    indexrelname AS index_adi,
    idx_scan     AS kullanim_sayisi,
    pg_size_pretty(pg_relation_size(indexrelid)) AS boyut
FROM pg_stat_user_indexes
WHERE idx_scan = 0
ORDER BY pg_relation_size(indexrelid) DESC;
```

"idx_scan sıfır olan indexler hiç kullanılmamış demek. Bunları kaldırmak hem disk
alanı kazandırır hem de yazma hızını artırır.

Son olarak tablo ve index boyutlarına bakayım."

**► 02 DOSYASI — Sorgu 8: Tablo ve index boyutları**
```sql
SELECT
    relname                                        AS nesne,
    pg_size_pretty(pg_total_relation_size(relid))  AS toplam_boyut,
    pg_size_pretty(pg_relation_size(relid))         AS tablo_boyutu,
    pg_size_pretty(pg_indexes_size(relid))          AS index_boyutu
FROM pg_stat_user_tables
ORDER BY pg_total_relation_size(relid) DESC;
```

"ticket_flights tablosu en büyük tablo. İndex boyutuna bakıyorum —
tablo boyutunun makul bir oranında olması gerekiyor.
Eğer index boyutu tablo boyutunu çok aştıysa gereksiz indexler var demektir."

---

## ADIM 3 — SORGU İYİLEŞTİRME

"Üçüncü adım sorgu iyileştirme. Index eklemek tek başına yeterli değil,
sorgunun kendisi de doğru yazılmış olmalı. Şimdi kötü yazılmış sorgularla
iyi yazılmış versiyonlarını karşılaştıracağım."

**► 03 DOSYASI — Sorgu 1: SELECT yıldız — KÖTÜ**
```sql
EXPLAIN ANALYZE
SELECT *
FROM bookings.ticket_flights;
```

**► 03 DOSYASI — Sorgu 1: Sadece gerekli kolonlar — İYİ**
```sql
EXPLAIN ANALYZE
SELECT ticket_no, flight_id, amount
FROM bookings.ticket_flights;
```

"SELECT yıldız tüm kolonları çekiyor, ihtiyacım olmayan kolonlar da dahil.
Sadece ihtiyacım olan kolonları belirtirsem hem ağ trafiği azalır
hem de bellek kullanımı düşer.

Şimdi ikinci örnek — WHERE içinde fonksiyon kullanımı."

**► 03 DOSYASI — Sorgu 2: EXTRACT — KÖTÜ (index çalışmaz)**
```sql
EXPLAIN ANALYZE
SELECT flight_id, flight_no, scheduled_departure
FROM bookings.flights
WHERE EXTRACT(MONTH FROM scheduled_departure) = 6;
```

**► 03 DOSYASI — Sorgu 2: Aralık filtresi — İYİ (index çalışır)**
```sql
EXPLAIN ANALYZE
SELECT flight_id, flight_no, scheduled_departure
FROM bookings.flights
WHERE scheduled_departure >= '2017-06-01'
  AND scheduled_departure < '2017-07-01';
```

"EXTRACT(MONTH FROM tarih) = 6 yazdığımda index kullanılamıyor.
Çünkü index ham tarihlere göre oluşturulmuş, fonksiyon uygulanmış
değerlere göre değil. 'Seq Scan' görüyoruz, 26 milisaniye sürdü.
Aynı sonucu aralık filtresiyle yazınca index devreye giriyor,
'Bitmap Index Scan' görüyoruz ve 5 milisaniyeye düştü.

Şimdi en çarpıcı örneği göstereyim hocam — subquery ile JOIN farkı."

**► 03 DOSYASI — Sorgu 3: Subquery — KÖTÜ (çok yavaş, ~50 saniye sürer)**
```sql
EXPLAIN ANALYZE
SELECT
    b.book_ref,
    b.total_amount,
    (SELECT COUNT(*) FROM bookings.tickets t WHERE t.book_ref = b.book_ref) AS bilet_sayisi
FROM bookings.bookings b
LIMIT 1000;
```

"Bu sorgu çalışıyor... biraz bekleyelim... Bakın Execution Time —
50 bin milisaniye, yani 50 saniye sürdü. Neden bu kadar yavaş?
Çünkü bookings tablosunda 593 bin rezervasyon var.
Bu subquery her rezervasyon için tickets tablosuna ayrı ayrı
gidip sorgu çalıştırıyor. 593 bin kez ayrı sorgu — doğal olarak yavaş.

Şimdi aynı sonucu veren JOIN versiyonunu çalıştırıyorum."

**► 03 DOSYASI — Sorgu 3: JOIN — İYİ (~1 saniye)**
```sql
EXPLAIN ANALYZE
SELECT
    b.book_ref,
    b.total_amount,
    COUNT(t.ticket_no) AS bilet_sayisi
FROM bookings.bookings b
LEFT JOIN bookings.tickets t ON b.book_ref = t.book_ref
GROUP BY b.book_ref, b.total_amount
LIMIT 1000;
```

"Bakın — 1 saniyenin altında. Aynı sonucu veriyor ama çok farklı çalışıyor.
JOIN iki tabloyu tek seferde birleştiriyor, 593 bin kez ayrı sorgu yerine
bir kez geçiyor. İşte bu yüzden subquery yerine JOIN tercih etmek gerekiyor.

Bir örnek daha — LIKE başı joker kullanımı."

**► 03 DOSYASI — Sorgu 4: LIKE başı joker — KÖTÜ**
```sql
EXPLAIN ANALYZE
SELECT passenger_id, passenger_name
FROM bookings.tickets
WHERE passenger_name LIKE '%IVAN%';
```

**► 03 DOSYASI — Sorgu 4: LIKE başı sabit — İYİ**
```sql
EXPLAIN ANALYZE
SELECT passenger_id, passenger_name
FROM bookings.tickets
WHERE passenger_name LIKE 'IVAN%';
```

"LIKE ile başında yüzde işareti varsa index kullanılamıyor.
Çünkü neyle başladığı bilinmiyor. Başı sabit bırakırsak index çalışıyor.

Son olarak VACUUM ANALYZE çalıştırıyorum."

**► 03 DOSYASI — Sorgu 7: VACUUM ANALYZE**
```sql
VACUUM ANALYZE bookings.ticket_flights;
VACUUM ANALYZE bookings.flights;
VACUUM ANALYZE bookings.bookings;
```

**► 03 DOSYASI — Sorgu 7: İstatistik kontrolü**
```sql
SELECT
    relname         AS tablo,
    last_vacuum     AS son_vacuum,
    last_analyze    AS son_analiz,
    last_autoanalyze AS otomatik_analiz
FROM pg_stat_user_tables
ORDER BY last_analyze ASC NULLS FIRST;
```

"Bu komut iki iş yapıyor: silinmiş veya güncellenmiş satırların bıraktığı
ölü veriyi temizliyor, disk alanı kazanıyoruz. Bir de istatistikleri güncelliyor.
Sorgu planlayıcısı bu istatistiklere bakarak en iyi planı seçiyor.
İstatistikler eskirse planlayıcı yanlış kararlar verebilir,
bu da performansı düşürür."

---

## ADIM 4 — ROL VE ERİŞİM YÖNETİMİ

"Son adım rol ve erişim yönetimi. Performans yönetiminin bir parçası da bu hocam.
Yanlış kişi yanlış bir DELETE ya da DROP çalıştırırsa performans değil, veri
bütünlüğü sorunu yaşanır. Bu yüzden 3 farklı seviyede rol tanımladım.

Önce mevcut rollere bakayım."

**► 04 DOSYASI — Sorgu 1: Mevcut roller**
```sql
SELECT rolname, rolsuper, rolcreatedb, rolcreaterole, rolcanlogin
FROM pg_roles
ORDER BY rolname;
```

"Şimdi 3 farklı rol oluşturuyorum."

**► 04 DOSYASI — Sorgu 2: Rolleri oluştur**
```sql
DO $$ BEGIN
  CREATE ROLE analist LOGIN PASSWORD 'Analist2024!';
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE ROLE operatör LOGIN PASSWORD 'Operator2024!';
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE ROLE db_yoneticisi LOGIN PASSWORD 'Admin2024!';
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
```

"Şimdi yetkileri veriyorum."

**► 04 DOSYASI — Sorgu 3: Yetkileri ver**
```sql
GRANT CONNECT ON DATABASE demo TO analist;
GRANT USAGE ON SCHEMA bookings TO analist;
GRANT SELECT ON ALL TABLES IN SCHEMA bookings TO analist;

GRANT CONNECT ON DATABASE demo TO operatör;
GRANT USAGE ON SCHEMA bookings TO operatör;
GRANT SELECT, INSERT, UPDATE ON bookings.bookings TO operatör;
GRANT SELECT, INSERT, UPDATE ON bookings.tickets TO operatör;
GRANT SELECT, INSERT, UPDATE ON bookings.ticket_flights TO operatör;
GRANT SELECT ON bookings.flights TO operatör;
GRANT SELECT ON bookings.seats TO operatör;

GRANT CONNECT ON DATABASE demo TO db_yoneticisi;
GRANT USAGE ON SCHEMA bookings TO db_yoneticisi;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA bookings TO db_yoneticisi;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA bookings TO db_yoneticisi;
```

"Şimdi yetkileri doğruluyorum — kimin hangi tabloya ne yetkisi var?"

**► 04 DOSYASI — Sorgu 4: Yetkileri doğrula**
```sql
SELECT
    grantee          AS kullanici,
    table_schema     AS sema,
    table_name       AS tablo,
    privilege_type   AS yetki
FROM information_schema.role_table_grants
WHERE grantee IN ('analist', 'operatör', 'db_yoneticisi')
ORDER BY grantee, table_name, privilege_type;
```

"analist sadece SELECT yapabiliyor. Raporları çekebilir ama veri silemez,
değiştiremez. operatör INSERT ve UPDATE yapabiliyor ama DROP veya DELETE
yetkisi yok. db_yoneticisi her şeyi yapabiliyor.

Bir de Row Level Security ekledim — satır bazında güvenlik."

**► 04 DOSYASI — Sorgu 6: Row Level Security**
```sql
ALTER TABLE bookings.flights ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS yönetici_politikasi ON bookings.flights;
CREATE POLICY yönetici_politikasi
    ON bookings.flights
    FOR ALL
    TO db_yoneticisi
    USING (true);

DROP POLICY IF EXISTS analist_politikasi ON bookings.flights;
CREATE POLICY analist_politikasi
    ON bookings.flights
    FOR SELECT
    TO analist
    USING (status = 'Arrived');

ALTER TABLE bookings.flights FORCE ROW LEVEL SECURITY;

SELECT polname, polcmd, polroles, polqual
FROM pg_policy
WHERE polrelid = 'bookings.flights'::regclass;
```

"Bunu şöyle açıklayayım hocam: tablo seviyesinde değil, satır seviyesinde güvenlik bu.
analist rolü flights tablosunu sorguladığında sadece 'Arrived' yani inmiş
uçuşları görebiliyor. Diğer uçuşlar hiç gözükmüyor, sanki yokmuş gibi.

Son olarak bağlantı limitlerini ayarlıyorum."

**► 04 DOSYASI — Sorgu 8: Bağlantı limitleri**
```sql
ALTER ROLE analist CONNECTION LIMIT 5;
ALTER ROLE operatör CONNECTION LIMIT 10;
ALTER ROLE db_yoneticisi CONNECTION LIMIT -1;

SELECT rolname, rolconnlimit AS baglanti_limiti
FROM pg_roles
WHERE rolname IN ('analist', 'operatör', 'db_yoneticisi');
```

"analist için bağlantı limiti 5 koydum. Yani aynı anda 5'ten fazla
analist bağlantısı açılamaz. Sunucu kaynaklarını aşırı tüketmesin diye.
db_yoneticisi için -1 yazdım, bu sınırsız demek."

---

## KAPANIŞ

"Projeyi özetleyeyim hocam.

İlk adımda pg_stat_statements ile hangi sorguların yavaş olduğunu tespit ettim,
tablo tarama istatistiklerine ve cache hit oranına baktım.

İkinci adımda EXPLAIN ANALYZE komutuyla sorguların nasıl çalıştığını inceledim,
doğru indexleri ekledim ve kullanılmayan indexleri tespit ettim.

Üçüncü adımda kötü yazılmış sorguları iyi versiyonlarıyla karşılaştırdım.
Özellikle subquery yerine JOIN kullanarak sorgu süresini 50 saniyeden
1 saniyenin altına indirdim.

Son adımda rol tabanlı erişim yönetimi ve satır seviyesi güvenlik ile
veritabanının hem performanslı hem de güvenli çalışmasını sağladım.

Proje 1 bu kadar, teşekkür ederim hocam."
