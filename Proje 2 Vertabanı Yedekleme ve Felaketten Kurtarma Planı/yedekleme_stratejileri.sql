-- proje 2 yedekleme ve kurtarma sql komutlari

-- full backup (tum db)
BACKUP DATABASE SirketYonetimDB
TO DISK = 'C:\Backups\SirketYonetimDB_Full.bak'
WITH FORMAT, 
     MEDIANAME = 'SQLServerBackups', 
     NAME = 'Full Backup of SirketYonetimDB';
GO

-- diff backup (sadece farkli olan kisimlari aliyor)
BACKUP DATABASE SirketYonetimDB
TO DISK = 'C:\Backups\SirketYonetimDB_Diff.bak'
WITH DIFFERENTIAL,
     NAME = 'Differential Backup of SirketYonetimDB';
GO

-- transaction log (nokyya atisi icin saniyelik yedek)
BACKUP LOG SirketYonetimDB
TO DISK = 'C:\Backups\SirketYonetimDB_Log.trn'
WITH NAME = 'Transaction Log Backup of SirketYonetimDB';
GO


-- point in time restore senaryosu
-- ornegin 14:30 da sorun oldu 14:29 a dondurecez

-- onc tam log aliyoruz
BACKUP LOG SirketYonetimDB
TO DISK = 'C:\Backups\SirketYonetimDB_TailLog.trn'
WITH NORECOVERY;
GO

-- en son alinmis full backpu cagiriyoz (norecovery dıkkat)
RESTORE DATABASE SirketYonetimDB
FROM DISK = 'C:\Backups\SirketYonetimDB_Full.bak'
WITH NORECOVERY;
GO

-- son alinin diff paketni de ekliyoz
RESTORE DATABASE SirketYonetimDB
FROM DISK = 'C:\Backups\SirketYonetimDB_Diff.bak'
WITH NORECOVERY;
GO

-- loglari taratip istediiğmiz saniyedr durdurtuyrz
RESTORE LOG SirketYonetimDB
FROM DISK = 'C:\Backups\SirketYonetimDB_Log.trn'
WITH STOPAT = '2023-11-15 14:29:59', RECOVERY;
GO


-- veritabni mirroring kismi 
ALTER DATABASE SirketYonetimDB 
SET PARTNER = 'TCP://MirrorServer.domain.local:5022';
GO

ALTER DATABASE SirketYonetimDB 
SET PARTNER SAFETY FULL;
GO
