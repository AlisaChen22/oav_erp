/* =========================================================
   03 觸發程序（過帳機制）
   - 出貨/退回/收貨/入庫/領料 → 回寫來源單據數量
   - 庫存單據 → 庫存異動明細 → 每日庫存餘額（禁止負庫存）
   - 訂單/採購/工單/預留/庫存變動 → 庫存在途明細 → 每日供需餘額
   ========================================================= */
USE oav37;
GO

/* 依「庫存在途來源」重算指定物料的 庫存在途明細 與 每日供需餘額 */
CREATE PROC dbo.重算供需 @料 dbo.物料鍵 READONLY AS
BEGIN
  SET NOCOUNT ON;
  IF NOT EXISTS(SELECT 1 FROM @料) RETURN;

  WITH t AS (SELECT * FROM dbo.庫存在途明細 m WHERE m.物料編號 IN (SELECT 物料編號 FROM @料)),
       s AS (SELECT * FROM dbo.庫存在途來源 v WHERE v.物料編號 IN (SELECT 物料編號 FROM @料))
  MERGE t USING s ON t.來源=s.來源 AND t.單據編號=s.單據編號 AND t.單據項次=s.單據項次
  WHEN MATCHED AND (t.工廠代碼<>s.工廠代碼 OR t.物料編號<>s.物料編號 OR t.預計日期<>s.預計日期
                    OR t.供給數量<>s.供給數量 OR t.需求數量<>s.需求數量) THEN
       UPDATE SET 工廠代碼=s.工廠代碼, 物料編號=s.物料編號, 預計日期=s.預計日期, 供給數量=s.供給數量, 需求數量=s.需求數量
  WHEN NOT MATCHED BY TARGET THEN
       INSERT(來源,單據編號,單據項次,工廠代碼,物料編號,預計日期,供給數量,需求數量)
       VALUES(s.來源,s.單據編號,s.單據項次,s.工廠代碼,s.物料編號,s.預計日期,s.供給數量,s.需求數量)
  WHEN NOT MATCHED BY SOURCE THEN DELETE;

  DELETE dbo.每日供需餘額 WHERE 物料編號 IN (SELECT 物料編號 FROM @料);

  WITH 在手 AS (
         SELECT w.工廠代碼, m.物料編號, SUM(m.異動數量) AS 數量
           FROM dbo.庫存異動明細 m JOIN dbo.工廠倉庫維護 w ON w.倉庫代碼=m.倉庫代碼
          WHERE m.物料編號 IN (SELECT 物料編號 FROM @料)
          GROUP BY w.工廠代碼, m.物料編號),
       每日 AS (
         SELECT 工廠代碼, 物料編號, 預計日期 AS 日期, SUM(供給數量) AS 供給, SUM(需求數量) AS 需求
           FROM dbo.庫存在途明細 WHERE 物料編號 IN (SELECT 物料編號 FROM @料)
          GROUP BY 工廠代碼, 物料編號, 預計日期
         UNION ALL   -- 只有庫存、沒有在途的物料，也給一列（今天）
         SELECT k.工廠代碼, k.物料編號, CAST(GETDATE() AS date), 0, 0 FROM 在手 k
          WHERE NOT EXISTS(SELECT 1 FROM dbo.庫存在途明細 t WHERE t.工廠代碼=k.工廠代碼 AND t.物料編號=k.物料編號)),
       累計 AS (
         SELECT d.*, ISNULL(k.數量,0)
                + SUM(d.供給-d.需求) OVER (PARTITION BY d.工廠代碼,d.物料編號 ORDER BY d.日期 ROWS UNBOUNDED PRECEDING) AS 可用
           FROM 每日 d LEFT JOIN 在手 k ON k.工廠代碼=d.工廠代碼 AND k.物料編號=d.物料編號)
  INSERT dbo.每日供需餘額(物料編號,工廠代碼,日期,在手數量,供給入庫,需求入庫,可用數量)
  SELECT 物料編號, 工廠代碼, 日期, 可用-供給+需求, 供給, 需求, 可用 FROM 累計;
END
GO

/* 依「庫存異動來源」將指定單據同步到 庫存異動明細（單一 MERGE），並檢核倉庫屬於單據工廠 */
CREATE PROC dbo.同步庫存異動 @類別 nvarchar(10), @鍵 dbo.單據鍵 READONLY AS
BEGIN
  SET NOCOUNT ON;
  IF NOT EXISTS(SELECT 1 FROM @鍵) RETURN;
  DECLARE @msg nvarchar(400);
  SELECT TOP 1 @msg = CONCAT(N'倉庫 ',v.倉庫代碼,N' 屬於工廠 ',w.工廠代碼,N'，與單據 ',v.單據編號,N' 的工廠 ',v.工廠代碼,N' 不符')
    FROM dbo.庫存異動來源 v JOIN dbo.工廠倉庫維護 w ON w.倉庫代碼=v.倉庫代碼
   WHERE v.單據類別=@類別 AND w.工廠代碼<>v.工廠代碼
     AND EXISTS(SELECT 1 FROM @鍵 k WHERE k.單據編號=v.單據編號 AND k.單據項次=v.單據項次);
  IF @msg IS NOT NULL THROW 50002, @msg, 1;

  WITH t AS (SELECT * FROM dbo.庫存異動明細 m
              WHERE m.單據類別=@類別 AND EXISTS(SELECT 1 FROM @鍵 k WHERE k.單據編號=m.單據編號 AND k.單據項次=m.單據項次)),
       s AS (SELECT v.* FROM dbo.庫存異動來源 v
              WHERE v.單據類別=@類別 AND EXISTS(SELECT 1 FROM @鍵 k WHERE k.單據編號=v.單據編號 AND k.單據項次=v.單據項次))
  MERGE t USING s ON t.單據編號=s.單據編號 AND t.單據項次=s.單據項次
  WHEN MATCHED AND (t.異動日期<>s.異動日期 OR t.物料編號<>s.物料編號 OR t.倉庫代碼<>s.倉庫代碼 OR t.異動數量<>s.異動數量) THEN
       UPDATE SET 異動日期=s.異動日期, 物料編號=s.物料編號, 倉庫代碼=s.倉庫代碼, 異動數量=s.異動數量
  WHEN NOT MATCHED BY TARGET THEN
       INSERT(異動日期,單據類別,單據編號,單據項次,物料編號,倉庫代碼,異動數量)
       VALUES(s.異動日期,s.單據類別,s.單據編號,s.單據項次,s.物料編號,s.倉庫代碼,s.異動數量)
  WHEN NOT MATCHED BY SOURCE THEN DELETE
  OPTION (RECOMPILE);
END
GO

/* 庫存異動明細 → 重算受影響 (物料,倉庫) 的每日庫存餘額、禁止負庫存，並重算供需 */
CREATE TRIGGER dbo.tr_庫存異動明細 ON dbo.庫存異動明細 AFTER INSERT,UPDATE,DELETE AS
BEGIN
  SET NOCOUNT ON;
  IF NOT EXISTS(SELECT 1 FROM inserted) AND NOT EXISTS(SELECT 1 FROM deleted) RETURN;
  DECLARE @k TABLE(物料編號 nvarchar(20), 倉庫代碼 nvarchar(20), PRIMARY KEY(物料編號,倉庫代碼));
  INSERT @k SELECT 物料編號,倉庫代碼 FROM inserted UNION SELECT 物料編號,倉庫代碼 FROM deleted;

  DELETE b FROM dbo.每日庫存餘額 b JOIN @k k ON k.物料編號=b.物料編號 AND k.倉庫代碼=b.倉庫代碼;

  WITH 日 AS (
         SELECT m.物料編號, m.倉庫代碼, m.異動日期,
                SUM(CASE WHEN m.異動數量>0 THEN  m.異動數量 ELSE 0 END) AS 入庫,
                SUM(CASE WHEN m.異動數量<0 THEN -m.異動數量 ELSE 0 END) AS 出庫
           FROM dbo.庫存異動明細 m JOIN @k k ON k.物料編號=m.物料編號 AND k.倉庫代碼=m.倉庫代碼
          GROUP BY m.物料編號, m.倉庫代碼, m.異動日期),
       累計 AS (
         SELECT *, SUM(入庫-出庫) OVER (PARTITION BY 物料編號,倉庫代碼 ORDER BY 異動日期 ROWS UNBOUNDED PRECEDING) AS 期末 FROM 日)
  INSERT dbo.每日庫存餘額(物料編號,倉庫代碼,日期,期初數量,本期入庫,本期出庫,期末數量)
  SELECT 物料編號, 倉庫代碼, 異動日期, 期末-入庫+出庫, 入庫, 出庫, 期末 FROM 累計;

  DECLARE @msg nvarchar(400);
  SELECT TOP 1 @msg = CONCAT(N'庫存不足：倉庫 ',b.倉庫代碼,N' 物料 ',b.物料編號,N' 於 ',CONVERT(char(10),b.日期,23),N' 期末數量將為 ',b.期末數量)
    FROM dbo.每日庫存餘額 b JOIN @k k ON k.物料編號=b.物料編號 AND k.倉庫代碼=b.倉庫代碼
   WHERE b.期末數量<0 ORDER BY b.日期;
  IF @msg IS NOT NULL THROW 50001, @msg, 1;

  DECLARE @料 dbo.物料鍵;
  INSERT @料 SELECT DISTINCT 物料編號 FROM @k;
  EXEC dbo.重算供需 @料;
END
GO

/* =================== SD =================== */
CREATE TRIGGER dbo.tr_客戶訂單主檔 ON dbo.客戶訂單主檔 AFTER UPDATE AS
BEGIN
  SET NOCOUNT ON;
  DECLARE @料 dbo.物料鍵;
  INSERT @料 SELECT DISTINCT d.物料編號 FROM dbo.客戶訂單明細 d JOIN inserted i ON i.訂單編號=d.訂單編號;
  EXEC dbo.重算供需 @料;
END
GO

CREATE TRIGGER dbo.tr_客戶訂單明細 ON dbo.客戶訂單明細 AFTER INSERT,UPDATE,DELETE AS
BEGIN
  SET NOCOUNT ON;
  IF NOT EXISTS(SELECT 1 FROM inserted) AND NOT EXISTS(SELECT 1 FROM deleted) RETURN;
  DECLARE @msg nvarchar(400);
  SELECT TOP 1 @msg = CONCAT(N'訂單 ',訂單編號,N'-',訂單項次,N'：已出貨淨額 ',出貨數量-退回數量,N' 超過訂單數量 ',訂單數量)
    FROM inserted WHERE 出貨數量-退回數量>訂單數量;
  IF @msg IS NOT NULL THROW 50021, @msg, 1;
  SELECT TOP 1 @msg = CONCAT(N'訂單 ',訂單編號,N'-',訂單項次,N'：退回數量 ',退回數量,N' 超過已出貨數量 ',出貨數量)
    FROM inserted WHERE 退回數量>出貨數量;
  IF @msg IS NOT NULL THROW 50022, @msg, 1;
  IF EXISTS(SELECT 1 FROM inserted i JOIN deleted d ON d.訂單編號=i.訂單編號 AND d.訂單項次=i.訂單項次
             WHERE (i.物料編號<>d.物料編號 OR i.工廠代碼<>d.工廠代碼) AND i.出貨數量>0)
    THROW 50023, N'訂單項次已有出貨，不可變更物料或工廠', 1;
  DECLARE @料 dbo.物料鍵;
  INSERT @料 SELECT 物料編號 FROM inserted UNION SELECT 物料編號 FROM deleted;
  EXEC dbo.重算供需 @料;
END
GO

CREATE TRIGGER dbo.tr_訂單出貨主檔 ON dbo.訂單出貨主檔 AFTER UPDATE AS
BEGIN
  SET NOCOUNT ON;
  IF EXISTS(SELECT 1 FROM inserted h JOIN dbo.訂單出貨明細 d ON d.出貨編號=h.出貨編號
             JOIN dbo.客戶訂單主檔 o ON o.訂單編號=d.訂單編號 WHERE o.客戶編號<>h.客戶編號)
    THROW 50012, N'出貨客戶與訂單客戶不符', 1;
  DECLARE @k dbo.單據鍵;
  INSERT @k SELECT d.出貨編號,d.出貨項次 FROM dbo.訂單出貨明細 d JOIN inserted i ON i.出貨編號=d.出貨編號;
  EXEC dbo.同步庫存異動 N'訂單出貨', @k;
END
GO

/* 過帳：客戶訂單明細.出貨數量 = SUM(訂單出貨明細.出貨數量) BY 訂單編號+訂單項次 */
CREATE TRIGGER dbo.tr_訂單出貨明細 ON dbo.訂單出貨明細 AFTER INSERT,UPDATE,DELETE AS
BEGIN
  SET NOCOUNT ON;
  IF NOT EXISTS(SELECT 1 FROM inserted) AND NOT EXISTS(SELECT 1 FROM deleted) RETURN;
  UPDATE s SET 物料編號=o.物料編號     -- 物料空白 → 由訂單帶入
    FROM dbo.訂單出貨明細 s JOIN inserted i ON i.出貨編號=s.出貨編號 AND i.出貨項次=s.出貨項次
    JOIN dbo.客戶訂單明細 o ON o.訂單編號=s.訂單編號 AND o.訂單項次=s.訂單項次
   WHERE s.物料編號 IS NULL;
  IF EXISTS(SELECT 1 FROM dbo.訂單出貨明細 s JOIN inserted i ON i.出貨編號=s.出貨編號 AND i.出貨項次=s.出貨項次
             JOIN dbo.客戶訂單明細 o ON o.訂單編號=s.訂單編號 AND o.訂單項次=s.訂單項次 WHERE o.物料編號<>s.物料編號)
    THROW 50011, N'出貨物料與訂單物料不符', 1;
  IF EXISTS(SELECT 1 FROM inserted i JOIN dbo.訂單出貨主檔 h ON h.出貨編號=i.出貨編號
             JOIN dbo.客戶訂單主檔 o ON o.訂單編號=i.訂單編號 WHERE o.客戶編號<>h.客戶編號)
    THROW 50012, N'出貨客戶與訂單客戶不符', 1;
  UPDATE o SET 出貨數量=ISNULL(x.數量,0)
    FROM dbo.客戶訂單明細 o
    JOIN (SELECT 訂單編號,訂單項次 FROM inserted UNION SELECT 訂單編號,訂單項次 FROM deleted) k
      ON k.訂單編號=o.訂單編號 AND k.訂單項次=o.訂單項次
    OUTER APPLY (SELECT SUM(s.出貨數量) AS 數量 FROM dbo.訂單出貨明細 s WHERE s.訂單編號=o.訂單編號 AND s.訂單項次=o.訂單項次) x;
  DECLARE @k dbo.單據鍵;
  INSERT @k SELECT 出貨編號,出貨項次 FROM inserted UNION SELECT 出貨編號,出貨項次 FROM deleted;
  EXEC dbo.同步庫存異動 N'訂單出貨', @k;
END
GO

CREATE TRIGGER dbo.tr_出貨退回主檔 ON dbo.出貨退回主檔 AFTER UPDATE AS
BEGIN
  SET NOCOUNT ON;
  IF EXISTS(SELECT 1 FROM inserted h JOIN dbo.出貨退回明細 d ON d.退回編號=h.退回編號
             JOIN dbo.客戶訂單主檔 o ON o.訂單編號=d.訂單編號 WHERE o.客戶編號<>h.客戶編號)
    THROW 50014, N'退回客戶與訂單客戶不符', 1;
  DECLARE @k dbo.單據鍵;
  INSERT @k SELECT d.退回編號,d.退回項次 FROM dbo.出貨退回明細 d JOIN inserted i ON i.退回編號=d.退回編號;
  EXEC dbo.同步庫存異動 N'出貨退回', @k;
END
GO

/* 過帳：客戶訂單明細.退回數量 = SUM(出貨退回明細.退回數量) BY 訂單編號+訂單項次 */
CREATE TRIGGER dbo.tr_出貨退回明細 ON dbo.出貨退回明細 AFTER INSERT,UPDATE,DELETE AS
BEGIN
  SET NOCOUNT ON;
  IF NOT EXISTS(SELECT 1 FROM inserted) AND NOT EXISTS(SELECT 1 FROM deleted) RETURN;
  UPDATE s SET 物料編號=o.物料編號
    FROM dbo.出貨退回明細 s JOIN inserted i ON i.退回編號=s.退回編號 AND i.退回項次=s.退回項次
    JOIN dbo.客戶訂單明細 o ON o.訂單編號=s.訂單編號 AND o.訂單項次=s.訂單項次
   WHERE s.物料編號 IS NULL;
  IF EXISTS(SELECT 1 FROM dbo.出貨退回明細 s JOIN inserted i ON i.退回編號=s.退回編號 AND i.退回項次=s.退回項次
             JOIN dbo.客戶訂單明細 o ON o.訂單編號=s.訂單編號 AND o.訂單項次=s.訂單項次 WHERE o.物料編號<>s.物料編號)
    THROW 50013, N'退回物料與訂單物料不符', 1;
  IF EXISTS(SELECT 1 FROM inserted i JOIN dbo.出貨退回主檔 h ON h.退回編號=i.退回編號
             JOIN dbo.客戶訂單主檔 o ON o.訂單編號=i.訂單編號 WHERE o.客戶編號<>h.客戶編號)
    THROW 50014, N'退回客戶與訂單客戶不符', 1;
  UPDATE o SET 退回數量=ISNULL(x.數量,0)
    FROM dbo.客戶訂單明細 o
    JOIN (SELECT 訂單編號,訂單項次 FROM inserted UNION SELECT 訂單編號,訂單項次 FROM deleted) k
      ON k.訂單編號=o.訂單編號 AND k.訂單項次=o.訂單項次
    OUTER APPLY (SELECT SUM(s.退回數量) AS 數量 FROM dbo.出貨退回明細 s WHERE s.訂單編號=o.訂單編號 AND s.訂單項次=o.訂單項次) x;
  DECLARE @k dbo.單據鍵;
  INSERT @k SELECT 退回編號,退回項次 FROM inserted UNION SELECT 退回編號,退回項次 FROM deleted;
  EXEC dbo.同步庫存異動 N'出貨退回', @k;
END
GO

/* =================== MM =================== */
CREATE TRIGGER dbo.tr_廠商採購主檔 ON dbo.廠商採購主檔 AFTER UPDATE AS
BEGIN
  SET NOCOUNT ON;
  DECLARE @料 dbo.物料鍵;
  INSERT @料 SELECT DISTINCT d.物料編號 FROM dbo.廠商採購明細 d JOIN inserted i ON i.採購編號=d.採購編號;
  EXEC dbo.重算供需 @料;
END
GO

CREATE TRIGGER dbo.tr_廠商採購明細 ON dbo.廠商採購明細 AFTER INSERT,UPDATE,DELETE AS
BEGIN
  SET NOCOUNT ON;
  IF NOT EXISTS(SELECT 1 FROM inserted) AND NOT EXISTS(SELECT 1 FROM deleted) RETURN;
  DECLARE @msg nvarchar(400);
  SELECT TOP 1 @msg = CONCAT(N'採購 ',採購編號,N'-',採購項次,N'：已收貨淨額 ',收貨數量-退回數量,N' 超過採購數量 ',採購數量)
    FROM inserted WHERE 收貨數量-退回數量>採購數量;
  IF @msg IS NOT NULL THROW 50041, @msg, 1;
  SELECT TOP 1 @msg = CONCAT(N'採購 ',採購編號,N'-',採購項次,N'：退回數量 ',退回數量,N' 超過已收貨數量 ',收貨數量)
    FROM inserted WHERE 退回數量>收貨數量;
  IF @msg IS NOT NULL THROW 50042, @msg, 1;
  IF EXISTS(SELECT 1 FROM inserted i JOIN deleted d ON d.採購編號=i.採購編號 AND d.採購項次=i.採購項次
             WHERE (i.物料編號<>d.物料編號 OR i.工廠代碼<>d.工廠代碼) AND i.收貨數量>0)
    THROW 50043, N'採購項次已有收貨，不可變更物料或工廠', 1;
  DECLARE @料 dbo.物料鍵;
  INSERT @料 SELECT 物料編號 FROM inserted UNION SELECT 物料編號 FROM deleted;
  EXEC dbo.重算供需 @料;
END
GO

CREATE TRIGGER dbo.tr_採購收貨主檔 ON dbo.採購收貨主檔 AFTER UPDATE AS
BEGIN
  SET NOCOUNT ON;
  IF EXISTS(SELECT 1 FROM inserted h JOIN dbo.採購收貨明細 d ON d.收貨編號=h.收貨編號
             JOIN dbo.廠商採購主檔 o ON o.採購編號=d.採購編號 WHERE o.廠商編號<>h.廠商編號)
    THROW 50032, N'收貨廠商與採購廠商不符', 1;
  DECLARE @k dbo.單據鍵;
  INSERT @k SELECT d.收貨編號,d.收貨項次 FROM dbo.採購收貨明細 d JOIN inserted i ON i.收貨編號=d.收貨編號;
  EXEC dbo.同步庫存異動 N'採購收貨', @k;
END
GO

/* 過帳：廠商採購明細.收貨數量 = SUM(採購收貨明細.收貨數量) BY 採購編號+採購項次 */
CREATE TRIGGER dbo.tr_採購收貨明細 ON dbo.採購收貨明細 AFTER INSERT,UPDATE,DELETE AS
BEGIN
  SET NOCOUNT ON;
  IF NOT EXISTS(SELECT 1 FROM inserted) AND NOT EXISTS(SELECT 1 FROM deleted) RETURN;
  UPDATE s SET 物料編號=o.物料編號
    FROM dbo.採購收貨明細 s JOIN inserted i ON i.收貨編號=s.收貨編號 AND i.收貨項次=s.收貨項次
    JOIN dbo.廠商採購明細 o ON o.採購編號=s.採購編號 AND o.採購項次=s.採購項次
   WHERE s.物料編號 IS NULL;
  IF EXISTS(SELECT 1 FROM dbo.採購收貨明細 s JOIN inserted i ON i.收貨編號=s.收貨編號 AND i.收貨項次=s.收貨項次
             JOIN dbo.廠商採購明細 o ON o.採購編號=s.採購編號 AND o.採購項次=s.採購項次 WHERE o.物料編號<>s.物料編號)
    THROW 50031, N'收貨物料與採購物料不符', 1;
  IF EXISTS(SELECT 1 FROM inserted i JOIN dbo.採購收貨主檔 h ON h.收貨編號=i.收貨編號
             JOIN dbo.廠商採購主檔 o ON o.採購編號=i.採購編號 WHERE o.廠商編號<>h.廠商編號)
    THROW 50032, N'收貨廠商與採購廠商不符', 1;
  UPDATE o SET 收貨數量=ISNULL(x.數量,0)
    FROM dbo.廠商採購明細 o
    JOIN (SELECT 採購編號,採購項次 FROM inserted UNION SELECT 採購編號,採購項次 FROM deleted) k
      ON k.採購編號=o.採購編號 AND k.採購項次=o.採購項次
    OUTER APPLY (SELECT SUM(s.收貨數量) AS 數量 FROM dbo.採購收貨明細 s WHERE s.採購編號=o.採購編號 AND s.採購項次=o.採購項次) x;
  DECLARE @k dbo.單據鍵;
  INSERT @k SELECT 收貨編號,收貨項次 FROM inserted UNION SELECT 收貨編號,收貨項次 FROM deleted;
  EXEC dbo.同步庫存異動 N'採購收貨', @k;
END
GO

CREATE TRIGGER dbo.tr_收貨退回主檔 ON dbo.收貨退回主檔 AFTER UPDATE AS
BEGIN
  SET NOCOUNT ON;
  IF EXISTS(SELECT 1 FROM inserted h JOIN dbo.收貨退回明細 d ON d.退回編號=h.退回編號
             JOIN dbo.廠商採購主檔 o ON o.採購編號=d.採購編號 WHERE o.廠商編號<>h.廠商編號)
    THROW 50034, N'退回廠商與採購廠商不符', 1;
  DECLARE @k dbo.單據鍵;
  INSERT @k SELECT d.退回編號,d.退回項次 FROM dbo.收貨退回明細 d JOIN inserted i ON i.退回編號=d.退回編號;
  EXEC dbo.同步庫存異動 N'收貨退回', @k;
END
GO

/* 過帳：廠商採購明細.退回數量 = SUM(收貨退回明細.退回數量) BY 採購編號+採購項次 */
CREATE TRIGGER dbo.tr_收貨退回明細 ON dbo.收貨退回明細 AFTER INSERT,UPDATE,DELETE AS
BEGIN
  SET NOCOUNT ON;
  IF NOT EXISTS(SELECT 1 FROM inserted) AND NOT EXISTS(SELECT 1 FROM deleted) RETURN;
  UPDATE s SET 物料編號=o.物料編號
    FROM dbo.收貨退回明細 s JOIN inserted i ON i.退回編號=s.退回編號 AND i.退回項次=s.退回項次
    JOIN dbo.廠商採購明細 o ON o.採購編號=s.採購編號 AND o.採購項次=s.採購項次
   WHERE s.物料編號 IS NULL;
  IF EXISTS(SELECT 1 FROM dbo.收貨退回明細 s JOIN inserted i ON i.退回編號=s.退回編號 AND i.退回項次=s.退回項次
             JOIN dbo.廠商採購明細 o ON o.採購編號=s.採購編號 AND o.採購項次=s.採購項次 WHERE o.物料編號<>s.物料編號)
    THROW 50033, N'退回物料與採購物料不符', 1;
  IF EXISTS(SELECT 1 FROM inserted i JOIN dbo.收貨退回主檔 h ON h.退回編號=i.退回編號
             JOIN dbo.廠商採購主檔 o ON o.採購編號=i.採購編號 WHERE o.廠商編號<>h.廠商編號)
    THROW 50034, N'退回廠商與採購廠商不符', 1;
  UPDATE o SET 退回數量=ISNULL(x.數量,0)
    FROM dbo.廠商採購明細 o
    JOIN (SELECT 採購編號,採購項次 FROM inserted UNION SELECT 採購編號,採購項次 FROM deleted) k
      ON k.採購編號=o.採購編號 AND k.採購項次=o.採購項次
    OUTER APPLY (SELECT SUM(s.退回數量) AS 數量 FROM dbo.收貨退回明細 s WHERE s.採購編號=o.採購編號 AND s.採購項次=o.採購項次) x;
  DECLARE @k dbo.單據鍵;
  INSERT @k SELECT 退回編號,退回項次 FROM inserted UNION SELECT 退回編號,退回項次 FROM deleted;
  EXEC dbo.同步庫存異動 N'收貨退回', @k;
END
GO

/* =================== IM =================== */
CREATE TRIGGER dbo.tr_物料預留主檔 ON dbo.物料預留主檔 AFTER UPDATE AS
BEGIN
  SET NOCOUNT ON;
  DECLARE @料 dbo.物料鍵;
  INSERT @料 SELECT DISTINCT d.物料編號 FROM dbo.物料預留明細 d JOIN inserted i ON i.預留編號=d.預留編號;
  EXEC dbo.重算供需 @料;
END
GO

CREATE TRIGGER dbo.tr_物料預留明細 ON dbo.物料預留明細 AFTER INSERT,UPDATE,DELETE AS
BEGIN
  SET NOCOUNT ON;
  DECLARE @料 dbo.物料鍵;
  INSERT @料 SELECT 物料編號 FROM inserted UNION SELECT 物料編號 FROM deleted;
  EXEC dbo.重算供需 @料;
END
GO

CREATE TRIGGER dbo.tr_庫存領用主檔 ON dbo.庫存領用主檔 AFTER UPDATE AS
BEGIN
  SET NOCOUNT ON;
  DECLARE @k dbo.單據鍵;
  INSERT @k SELECT d.領用編號,d.領用項次 FROM dbo.庫存領用明細 d JOIN inserted i ON i.領用編號=d.領用編號;
  EXEC dbo.同步庫存異動 N'庫存領用', @k;
END
GO

CREATE TRIGGER dbo.tr_庫存領用明細 ON dbo.庫存領用明細 AFTER INSERT,UPDATE,DELETE AS
BEGIN
  SET NOCOUNT ON;
  DECLARE @k dbo.單據鍵;
  INSERT @k SELECT 領用編號,領用項次 FROM inserted UNION SELECT 領用編號,領用項次 FROM deleted;
  EXEC dbo.同步庫存異動 N'庫存領用', @k;
END
GO

CREATE TRIGGER dbo.tr_庫存繳庫主檔 ON dbo.庫存繳庫主檔 AFTER UPDATE AS
BEGIN
  SET NOCOUNT ON;
  DECLARE @k dbo.單據鍵;
  INSERT @k SELECT d.繳庫編號,d.繳庫項次 FROM dbo.庫存繳庫明細 d JOIN inserted i ON i.繳庫編號=d.繳庫編號;
  EXEC dbo.同步庫存異動 N'庫存繳庫', @k;
END
GO

CREATE TRIGGER dbo.tr_庫存繳庫明細 ON dbo.庫存繳庫明細 AFTER INSERT,UPDATE,DELETE AS
BEGIN
  SET NOCOUNT ON;
  DECLARE @k dbo.單據鍵;
  INSERT @k SELECT 繳庫編號,繳庫項次 FROM inserted UNION SELECT 繳庫編號,繳庫項次 FROM deleted;
  EXEC dbo.同步庫存異動 N'庫存繳庫', @k;
END
GO

/* =================== PP =================== */
CREATE TRIGGER dbo.tr_生產工單主檔 ON dbo.生產工單主檔 AFTER INSERT,UPDATE,DELETE AS
BEGIN
  SET NOCOUNT ON;
  IF NOT EXISTS(SELECT 1 FROM inserted) AND NOT EXISTS(SELECT 1 FROM deleted) RETURN;
  DECLARE @msg nvarchar(400);
  SELECT TOP 1 @msg = CONCAT(N'工單 ',工單編號,N'：入庫數量 ',入庫數量,N' 超過生產數量 ',生產數量)
    FROM inserted WHERE 入庫數量>生產數量;
  IF @msg IS NOT NULL THROW 50051, @msg, 1;
  IF EXISTS(SELECT 1 FROM inserted i JOIN deleted d ON d.工單編號=i.工單編號
             WHERE (i.物料編號<>d.物料編號 OR i.工廠代碼<>d.工廠代碼)
               AND (i.入庫數量>0 OR EXISTS(SELECT 1 FROM dbo.生產工單明細 x WHERE x.工單編號=i.工單編號 AND x.已領用量>0)))
    THROW 50052, N'工單已有領料或入庫，不可變更生產料號或工廠', 1;
  -- 新工單：依用量清單展開用料
  INSERT dbo.生產工單明細(工單編號,工單項次,物料編號,應領用量,已領用量,預定領料)
  SELECT i.工單編號,
         RIGHT(N'000'+CAST(10*ROW_NUMBER() OVER (PARTITION BY i.工單編號 ORDER BY b.子階編號) AS nvarchar(10)),4),
         b.子階編號, b.標準用量*i.生產數量, 0, i.工單日期
    FROM inserted i JOIN dbo.用量清單維護 b ON b.主階編號=i.物料編號
   WHERE NOT EXISTS(SELECT 1 FROM deleted d WHERE d.工單編號=i.工單編號)
     AND NOT EXISTS(SELECT 1 FROM dbo.生產工單明細 d WHERE d.工單編號=i.工單編號);
  -- 供需：成品（工單未入）與用料（工單未領，日期/工廠可能隨主檔變動）
  DECLARE @料 dbo.物料鍵;
  INSERT @料 SELECT 物料編號 FROM inserted UNION SELECT 物料編號 FROM deleted
       UNION SELECT d.物料編號 FROM dbo.生產工單明細 d JOIN inserted i ON i.工單編號=d.工單編號;
  EXEC dbo.重算供需 @料;
END
GO

CREATE TRIGGER dbo.tr_生產工單明細 ON dbo.生產工單明細 AFTER INSERT,UPDATE,DELETE AS
BEGIN
  SET NOCOUNT ON;
  IF NOT EXISTS(SELECT 1 FROM inserted) AND NOT EXISTS(SELECT 1 FROM deleted) RETURN;
  DECLARE @msg nvarchar(400);
  SELECT TOP 1 @msg = CONCAT(N'工單 ',工單編號,N' 物料 ',物料編號,N'：已領用量 ',已領用量,N' 超過應領用量 ',應領用量)
    FROM inserted WHERE 已領用量>應領用量;
  IF @msg IS NOT NULL THROW 50053, @msg, 1;
  DECLARE @料 dbo.物料鍵;
  INSERT @料 SELECT 物料編號 FROM inserted UNION SELECT 物料編號 FROM deleted;
  EXEC dbo.重算供需 @料;
END
GO

CREATE TRIGGER dbo.tr_工單領料主檔 ON dbo.工單領料主檔 AFTER UPDATE AS
BEGIN
  SET NOCOUNT ON;
  DECLARE @k dbo.單據鍵;
  INSERT @k SELECT d.領料編號,d.領料項次 FROM dbo.工單領料明細 d JOIN inserted i ON i.領料編號=d.領料編號;
  EXEC dbo.同步庫存異動 N'工單領料', @k;
END
GO

/* 過帳：生產工單明細.已領用量 = SUM(工單領料明細.領料數量) BY 工單編號+物料編號 */
CREATE TRIGGER dbo.tr_工單領料明細 ON dbo.工單領料明細 AFTER INSERT,UPDATE,DELETE AS
BEGIN
  SET NOCOUNT ON;
  IF NOT EXISTS(SELECT 1 FROM inserted) AND NOT EXISTS(SELECT 1 FROM deleted) RETURN;
  UPDATE o SET 已領用量=ISNULL(x.數量,0)
    FROM dbo.生產工單明細 o
    JOIN (SELECT 工單編號,物料編號 FROM inserted UNION SELECT 工單編號,物料編號 FROM deleted) k
      ON k.工單編號=o.工單編號 AND k.物料編號=o.物料編號
    OUTER APPLY (SELECT SUM(s.領料數量) AS 數量 FROM dbo.工單領料明細 s WHERE s.工單編號=o.工單編號 AND s.物料編號=o.物料編號) x;
  DECLARE @k dbo.單據鍵;
  INSERT @k SELECT 領料編號,領料項次 FROM inserted UNION SELECT 領料編號,領料項次 FROM deleted;
  EXEC dbo.同步庫存異動 N'工單領料', @k;
END
GO

CREATE TRIGGER dbo.tr_工單入庫主檔 ON dbo.工單入庫主檔 AFTER UPDATE AS
BEGIN
  SET NOCOUNT ON;
  DECLARE @k dbo.單據鍵;
  INSERT @k SELECT d.入庫編號,d.入庫項次 FROM dbo.工單入庫明細 d JOIN inserted i ON i.入庫編號=d.入庫編號;
  EXEC dbo.同步庫存異動 N'工單入庫', @k;
END
GO

/* 過帳：生產工單主檔.入庫數量 = SUM(工單入庫明細.入庫數量) BY 工單編號 */
CREATE TRIGGER dbo.tr_工單入庫明細 ON dbo.工單入庫明細 AFTER INSERT,UPDATE,DELETE AS
BEGIN
  SET NOCOUNT ON;
  IF NOT EXISTS(SELECT 1 FROM inserted) AND NOT EXISTS(SELECT 1 FROM deleted) RETURN;
  UPDATE s SET 物料編號=w.物料編號
    FROM dbo.工單入庫明細 s JOIN inserted i ON i.入庫編號=s.入庫編號 AND i.入庫項次=s.入庫項次
    JOIN dbo.生產工單主檔 w ON w.工單編號=s.工單編號
   WHERE s.物料編號 IS NULL;
  IF EXISTS(SELECT 1 FROM dbo.工單入庫明細 s JOIN inserted i ON i.入庫編號=s.入庫編號 AND i.入庫項次=s.入庫項次
             JOIN dbo.生產工單主檔 w ON w.工單編號=s.工單編號 WHERE w.物料編號<>s.物料編號)
    THROW 50054, N'入庫物料與工單生產料號不符', 1;
  UPDATE w SET 入庫數量=ISNULL(x.數量,0)
    FROM dbo.生產工單主檔 w
    JOIN (SELECT 工單編號 FROM inserted UNION SELECT 工單編號 FROM deleted) k ON k.工單編號=w.工單編號
    OUTER APPLY (SELECT SUM(s.入庫數量) AS 數量 FROM dbo.工單入庫明細 s WHERE s.工單編號=w.工單編號) x;
  DECLARE @k dbo.單據鍵;
  INSERT @k SELECT 入庫編號,入庫項次 FROM inserted UNION SELECT 入庫編號,入庫項次 FROM deleted;
  EXEC dbo.同步庫存異動 N'工單入庫', @k;
END
GO
