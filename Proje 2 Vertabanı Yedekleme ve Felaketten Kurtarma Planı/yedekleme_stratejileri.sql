-- proje 2 yedekleme ve kurtarma sql komutlari

-- full backup (tum db)
BACKUP DATABASE TitanicDB
TO DISK = 'C:\Backups\TitanicDB_Full.bak'
WITH FORMAT, 
     MEDIANAME = 'SQLServerBackups', 
     NAME = 'Full Backup of TitanicDB';
GO

-- diff backup (sadece farkli olan kisimlari aliyor)
BACKUP DATABASE TitanicDB
TO DISK = 'C:\Backups\TitanicDB_Diff.bak'
WITH DIFFERENTIAL,
     NAME = 'Differential Backup of TitanicDB';
GO

-- transaction log (nokyya atisi icin saniyelik yedek)
BACKUP LOG TitanicDB
TO DISK = 'C:\Backups\TitanicDB_Log.trn'
WITH NAME = 'Transaction Log Backup of TitanicDB';
GO


-- point in time restore senaryosu
-- ornegin 14:30 da sorun oldu 14:29 a dondurecez

-- onc tam log aliyoruz
BACKUP LOG TitanicDB
TO DISK = 'C:\Backups\TitanicDB_TailLog.trn'
WITH NORECOVERY;
GO

-- en son alinmis full backpu cagiriyoz (norecovery dıkkat)
RESTORE DATABASE TitanicDB
FROM DISK = 'C:\Backups\TitanicDB_Full.bak'
WITH NORECOVERY;
GO

-- son alinin diff paketni de ekliyoz
RESTORE DATABASE TitanicDB
FROM DISK = 'C:\Backups\TitanicDB_Diff.bak'
WITH NORECOVERY;
GO

-- loglari taratip istediiğmiz saniyedr durdurtuyrz
RESTORE LOG TitanicDB
FROM DISK = 'C:\Backups\TitanicDB_Log.trn'
WITH STOPAT = '2023-11-15 14:29:59', RECOVERY;
GO


-- veritabni mirroring kismi 
ALTER DATABASE TitanicDB 
SET PARTNER = 'TCP://MirrorServer.domain.local:5022';
GO

ALTER DATABASE TitanicDB 
SET PARTNER SAFETY FULL;
GO
