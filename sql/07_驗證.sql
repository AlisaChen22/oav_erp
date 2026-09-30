/* =========================================================
   07 驗證準則：每條規則一列，顯示檢查筆數 / 不符筆數 / 結果
   SELECT * FROM dbo.驗證結果 ORDER BY 序   -- 全部「通過」才算過帳正確
   ========================================================= */
USE oav37;
GO
CREATE OR ALTER VIEW dbo.驗證結果 AS
WITH 工廠在手 AS (
       SELECT w.工廠代碼, m.物料編號, SUM(m.異動數量) AS 數量
         FROM dbo.庫存異動明細 m JOIN dbo.工廠倉庫維護 w ON w.倉庫代碼=m.倉庫代碼
        GROUP BY w.工廠代碼, m.物料編號),
r AS (
  SELECT 1 AS 序, N'訂單出貨明細.出貨數量 以 訂單編號+訂單項次 累加到 客戶訂單明細.出貨數量' AS 驗證項目,
         COUNT(*) AS 檢查筆數, SUM(IIF(o.出貨數量<>ISNULL(x.數量,0),1,0)) AS 不符筆數
    FROM dbo.客戶訂單明細 o
   OUTER APPLY (SELECT SUM(s.出貨數量) AS 數量 FROM dbo.訂單出貨明細 s WHERE s.訂單編號=o.訂單編號 AND s.訂單項次=o.訂單項次) x
  UNION ALL
  SELECT 2, N'出貨退回明細.退回數量 以 訂單編號+訂單項次 累加到 客戶訂單明細.退回數量',
         COUNT(*), SUM(IIF(o.退回數量<>ISNULL(x.數量,0),1,0))
    FROM dbo.客戶訂單明細 o
   OUTER APPLY (SELECT SUM(s.退回數量) AS 數量 FROM dbo.出貨退回明細 s WHERE s.訂單編號=o.訂單編號 AND s.訂單項次=o.訂單項次) x
  UNION ALL
  SELECT 3, N'採購收貨明細.收貨數量 以 採購編號+採購項次 累加到 廠商採購明細.收貨數量',
         COUNT(*), SUM(IIF(o.收貨數量<>ISNULL(x.數量,0),1,0))
    FROM dbo.廠商採購明細 o
   OUTER APPLY (SELECT SUM(s.收貨數量) AS 數量 FROM dbo.採購收貨明細 s WHERE s.採購編號=o.採購編號 AND s.採購項次=o.採購項次) x
  UNION ALL
  SELECT 4, N'收貨退回明細.退回數量 以 採購編號+採購項次 累加到 廠商採購明細.退回數量',
         COUNT(*), SUM(IIF(o.退回數量<>ISNULL(x.數量,0),1,0))
    FROM dbo.廠商採購明細 o
   OUTER APPLY (SELECT SUM(s.退回數量) AS 數量 FROM dbo.收貨退回明細 s WHERE s.採購編號=o.採購編號 AND s.採購項次=o.採購項次) x
  UNION ALL
  SELECT 5, N'工單入庫明細.入庫數量 以 工單編號 累加到 生產工單主檔.入庫數量',
         COUNT(*), SUM(IIF(w.入庫數量<>ISNULL(x.數量,0),1,0))
    FROM dbo.生產工單主檔 w
   OUTER APPLY (SELECT SUM(s.入庫數量) AS 數量 FROM dbo.工單入庫明細 s WHERE s.工單編號=w.工單編號) x
  UNION ALL
  SELECT 6, N'工單領料明細.領料數量 以 工單編號+物料編號 累加到 生產工單明細.已領用量',
         COUNT(*), SUM(IIF(d.已領用量<>ISNULL(x.數量,0),1,0))
    FROM dbo.生產工單明細 d
   OUTER APPLY (SELECT SUM(s.領料數量) AS 數量 FROM dbo.工單領料明細 s WHERE s.工單編號=d.工單編號 AND s.物料編號=d.物料編號) x
  UNION ALL
  SELECT 7, N'每日庫存餘額 逐列：期初數量 + 本期入庫 - 本期出庫 = 期末數量（且期初 = 前一日期末）',
         COUNT(*), SUM(IIF(期初數量+本期入庫-本期出庫<>期末數量 OR 期初數量<>ISNULL(前期末,0),1,0))
    FROM (SELECT *, LAG(期末數量) OVER (PARTITION BY 物料編號,倉庫代碼 ORDER BY 日期) AS 前期末 FROM dbo.每日庫存餘額) b
  UNION ALL
  SELECT 8, N'每日庫存餘額 最後期末數量 = 庫存異動明細 合計（依物料+倉庫）',
         COUNT(*), SUM(IIF(ISNULL(b.期末數量,0)<>ISNULL(m.數量,0),1,0))
    FROM (SELECT 物料編號, 倉庫代碼, SUM(異動數量) AS 數量 FROM dbo.庫存異動明細 GROUP BY 物料編號, 倉庫代碼) m
    FULL JOIN (SELECT 物料編號, 倉庫代碼, 期末數量, ROW_NUMBER() OVER (PARTITION BY 物料編號,倉庫代碼 ORDER BY 日期 DESC) AS rn
                 FROM dbo.每日庫存餘額) b ON b.物料編號=m.物料編號 AND b.倉庫代碼=m.倉庫代碼 AND b.rn=1
   WHERE b.rn=1 OR b.rn IS NULL
  UNION ALL
  SELECT 9, N'每日供需餘額 逐列：在手數量 + 供給入庫 - 需求入庫 = 可用數量（且在手 = 前一日可用，首日 = 工廠現有庫存）',
         COUNT(*), SUM(IIF(在手數量+供給入庫-需求入庫<>可用數量 OR 在手數量<>ISNULL(前可用,ISNULL(現有,0)),1,0))
    FROM (SELECT b.*, k.數量 AS 現有,
                 LAG(b.可用數量) OVER (PARTITION BY b.物料編號,b.工廠代碼 ORDER BY b.日期) AS 前可用
            FROM dbo.每日供需餘額 b LEFT JOIN 工廠在手 k ON k.工廠代碼=b.工廠代碼 AND k.物料編號=b.物料編號) s
  UNION ALL
  SELECT 10, N'庫存異動明細 = 所有庫存單據（每張單據皆已過帳、數量一致、無多餘異動）',
         COUNT(*), SUM(IIF(m.異動序號 IS NULL OR v.單據編號 IS NULL OR m.異動數量<>v.異動數量 OR m.倉庫代碼<>v.倉庫代碼
                           OR m.物料編號<>v.物料編號 OR m.異動日期<>v.異動日期,1,0))
    FROM dbo.庫存異動明細 m
    FULL JOIN dbo.庫存異動來源 v ON v.單據類別=m.單據類別 AND v.單據編號=m.單據編號 AND v.單據項次=m.單據項次
  UNION ALL
  SELECT 11, N'庫存在途明細 = 所有未結的採購、工單、訂單、預留',
         COUNT(*), SUM(IIF(t.單據編號 IS NULL OR v.單據編號 IS NULL OR t.供給數量<>v.供給數量 OR t.需求數量<>v.需求數量
                           OR t.工廠代碼<>v.工廠代碼 OR t.物料編號<>v.物料編號 OR t.預計日期<>v.預計日期,1,0))
    FROM dbo.庫存在途明細 t
    FULL JOIN dbo.庫存在途來源 v ON v.來源=t.來源 AND v.單據編號=t.單據編號 AND v.單據項次=t.單據項次)
SELECT 序, IIF(ISNULL(不符筆數,0)=0, N'通過', N'不符') AS 結果, 檢查筆數, ISNULL(不符筆數,0) AS 不符筆數, 驗證項目
FROM r;
GO
