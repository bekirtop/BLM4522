import sqlite3
import shutil
import time
import os
from datetime import datetime

KAYNAK = "../Titanic.db"
YEDEK = "./yedekler"

# yedek klasöru yoksa olusturuyrz
if not os.path.exists(YEDEK):
    os.makedirs(YEDEK)

def tam_yedek_al():
    # tam backup simulasyonu
    zaman = datetime.now().strftime("%Y%m%d_%H%M%S")
    yedeklendi = f"{YEDEK}/Titanic_Full_{zaman}.db"
    
    try:
        shutil.copy2(KAYNAK, yedeklendi)
        print(f"Yedekleme başarılı: {yedeklendi}")
    except Exception as e:
        print(f"Yedekleme hatası: {e}")

def test_yedek():
    # veriyabani bozulursa en son yedekten donme testi
    yedekler = sorted([d for d in os.listdir(YEDEK) if d.endswith(".db")], reverse=True)
    
    if not yedekler:
        print("Geri yüklenecek yedek bulunamadı.")
        return

    son = os.path.join(YEDEK, yedekler[0])
    kurtarilan = "./Kurtarilan_TitanicDB.db"

    print(f"Felaket senaryosu testi başlatıldı. En son yedek kullanılıyor: {son}")
    
    # yedegi alip ana db gibi koyuyoz
    shutil.copy2(son, kurtarilan)
    print(f"Veritabanı başarıyla kurtarıldı: {kurtarilan}")
    
    # icine girp tablolari gormek test ediyrz
    try:
        conn = sqlite3.connect(kurtarilan)
        crs = conn.cursor()
        crs.execute("SELECT name FROM sqlite_master WHERE type='table';")
        print(f"Bağlantı testi başarılı. İçerideki tablolar: {crs.fetchall()}")
        conn.close()
    except sqlite3.Error as e:
        print(f"Kurtarma bağlantı testi başarısız: {e}")

if __name__ == "__main__":
    # ormek amacli 1 kere calistiryirz
    tam_yedek_al()
    test_yedek()
