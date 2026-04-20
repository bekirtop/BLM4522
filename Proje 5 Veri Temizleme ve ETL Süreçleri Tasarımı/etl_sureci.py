import pandas as pd
import sqlite3
import os

KAYNAK = "../titanic.csv"
HEDEF = "./Titanic_Cleaned.db"
RAPOR = "./Veri_Kalite_Raporu.txt"

def etl_yap():
    rp = ["=== ETL SONUÇ RAPORU ==="]
    
    # 1. extract işlemi (csvden verileri cekiyrz)
    try:
        df = pd.read_csv(KAYNAK)
        rp.append(f"İşleme alınan toplam kayıt sayısı: {len(df)}")
    except:
        return

    # 2. transform (temizleme asamasi)
    
    # yas kisminda bos yerleri medyan ile dolduruyrz
    eksik_yas = df['Age'].isnull().sum()
    df['Age'] = df['Age'].fillna(df['Age'].median()) 

    # kabin kolonunda ck eksik var oyzden tamamen sildik
    df.drop('Cabin', axis=1, inplace=True)

    df['Embarked'] = df['Embarked'].fillna('S') 

    # liman kisatmalarini uzzun isme cevirdik
    limanlar = {'C': 'Cherbourg', 'Q': 'Queenstown', 'S': 'Southampton'}
    df['Embarked'] = df['Embarked'].map(limanlar)

    rp.append(f"Eksik olan {eksik_yas} adet yaş verisi, medyan değeriyle dolduruldu.")
    rp.append(f"Güncel temizlenmiş kayıt sayısı: {len(df)}")

    # 3. load (veritabanine yukluyoruz)
    
    if os.path.exists(HEDEF):
        os.remove(HEDEF) 

    conn = sqlite3.connect(HEDEF)
    
    # panadasla temiz veriyi aktaryruz
    df.to_sql('TitanicData', conn, if_exists='replace', index=False)
    conn.close()

    rp.append(f"Veriler başarıyla temiz bir veritabanına aktarıldı: {HEDEF}")

    # raporu txtye yyazdiriyrz
    with open(RAPOR, "w", encoding="utf-8") as f:
        f.write("\n".join(rp))

if __name__ == "__main__":
    etl_yap()
