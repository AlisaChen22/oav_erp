/* =========================================================
   02 視圖與報表函數
   ========================================================= */
USE oav37;
GO

/* ---------- SD ---------- */
CREATE VIEW dbo.已訂未出明細 AS
SELECT h.訂單日期, h.銷售組織, h.客戶編號, d.訂單編號, d.訂單項次, d.物料編號, d.工廠代碼,
       d.訂單數量, d.出貨數量, d.退回數量,
       d.訂單數量-d.出貨數量+d.退回數量 AS 未出數量,
       d.預定交期, d.備註說明
FROM dbo.客戶訂單明細 d
JOIN dbo.客戶訂單主檔 h ON h.訂單編號=d.訂單編號
WHERE d.訂單數量-d.出貨數量+d.退回數量>0;
GO

/* 訂單出退分析 = 訂單出貨明細 UNION ALL 出貨退回明細 */
CREATE VIEW dbo.訂單出退分析 AS
SELECT N'出貨' AS 類別, h.出貨日期 AS 單據日期, d.出貨編號 AS 單據編號, d.出貨項次 AS 單據項次,
       h.銷售組織, h.客戶編號, d.訂單編號, d.訂單項次, d.物料編號, d.倉庫代碼,
       d.出貨數量, 0 AS 退回數量, d.備註說明
FROM dbo.訂單出貨明細 d JOIN dbo.訂單出貨主檔 h ON h.出貨編號=d.出貨編號
UNION ALL
SELECT N'退回', h.退回日期, d.退回編號, d.退回項次,
       h.銷售組織, h.客戶編號, d.訂單編號, d.訂單項次, d.物料編號, d.倉庫代碼,
       0, d.退回數量, d.備註說明
FROM dbo.出貨退回明細 d JOIN dbo.出貨退回主檔 h ON h.退回編號=d.退回編號;
GO

/* 樞紐：輸入年度；縱軸客戶編號，橫軸月份；統計 出貨數量、退回數量、出貨+退回 */
CREATE FUNCTION dbo.訂單出退樞紐(@年度 int) RETURNS TABLE AS RETURN
SELECT ISNULL(@年度,YEAR(GETDATE())) AS 年度, p.客戶編號, p.統計項目,
       ISNULL([1],0) AS [01月], ISNULL([2],0) AS [02月], ISNULL([3],0) AS [03月], ISNULL([4],0) AS [04月],
       ISNULL([5],0) AS [05月], ISNULL([6],0) AS [06月], ISNULL([7],0) AS [07月], ISNULL([8],0) AS [08月],
       ISNULL([9],0) AS [09月], ISNULL([10],0) AS [10月], ISNULL([11],0) AS [11月], ISNULL([12],0) AS [12月],
       ISNULL([1],0)+ISNULL([2],0)+ISNULL([3],0)+ISNULL([4],0)+ISNULL([5],0)+ISNULL([6],0)
      +ISNULL([7],0)+ISNULL([8],0)+ISNULL([9],0)+ISNULL([10],0)+ISNULL([11],0)+ISNULL([12],0) AS 全年合計
FROM (SELECT a.客戶編號, v.統計項目, MONTH(a.單據日期) AS 月, v.數量
        FROM dbo.訂單出退分析 a
       CROSS APPLY (VALUES (N'出貨數量',a.出貨數量),(N'退回數量',a.退回數量),(N'出貨+退回',a.出貨數量+a.退回數量)) v(統計項目,數量)
       WHERE YEAR(a.單據日期)=ISNULL(@年度,YEAR(GETDATE()))) s
PIVOT (SUM(數量) FOR 月 IN ([1],[2],[3],[4],[5],[6],[7],[8],[9],[10],[11],[12])) p;
GO

/* ---------- MM ---------- */
CREATE VIEW dbo.已採未交明細 AS
SELECT h.採購日期, h.採購組織, h.廠商編號, d.採購編號, d.採購項次, d.物料編號, d.工廠代碼,
       d.採購數量, d.收貨數量, d.退回數量,
       d.採購數量-d.收貨數量+d.退回數量 AS 未交數量,
       d.預定交期, d.備註說明
FROM dbo.廠商採購明細 d
JOIN dbo.廠商採購主檔 h ON h.採購編號=d.採購編號
WHERE d.採購數量-d.收貨數量+d.退回數量>0;
GO

/* 採購收退分析 = 採購收貨明細 UNION ALL 收貨退回明細 */
CREATE VIEW dbo.採購收退分析 AS
SELECT N'收貨' AS 類別, h.收貨日期 AS 單據日期, d.收貨編號 AS 單據編號, d.收貨項次 AS 單據項次,
       h.採購組織, h.廠商編號, d.採購編號, d.採購項次, d.物料編號, d.倉庫代碼,
       d.收貨數量, 0 AS 退回數量, d.備註說明
FROM dbo.採購收貨明細 d JOIN dbo.採購收貨主檔 h ON h.收貨編號=d.收貨編號
UNION ALL
SELECT N'退回', h.退回日期, d.退回編號, d.退回項次,
       h.採購組織, h.廠商編號, d.採購編號, d.採購項次, d.物料編號, d.倉庫代碼,
       0, d.退回數量, d.備註說明
FROM dbo.收貨退回明細 d JOIN dbo.收貨退回主檔 h ON h.退回編號=d.退回編號;
GO

/* 樞紐：輸入年度；縱軸廠商編號，橫軸月份；統計 收貨數量、退回數量、收貨+退回 */
CREATE FUNCTION dbo.採購收退樞紐(@年度 int) RETURNS TABLE AS RETURN
SELECT ISNULL(@年度,YEAR(GETDATE())) AS 年度, p.廠商編號, p.統計項目,
       ISNULL([1],0) AS [01月], ISNULL([2],0) AS [02月], ISNULL([3],0) AS [03月], ISNULL([4],0) AS [04月],
       ISNULL([5],0) AS [05月], ISNULL([6],0) AS [06月], ISNULL([7],0) AS [07月], ISNULL([8],0) AS [08月],
       ISNULL([9],0) AS [09月], ISNULL([10],0) AS [10月], ISNULL([11],0) AS [11月], ISNULL([12],0) AS [12月],
       ISNULL([1],0)+ISNULL([2],0)+ISNULL([3],0)+ISNULL([4],0)+ISNULL([5],0)+ISNULL([6],0)
      +ISNULL([7],0)+ISNULL([8],0)+ISNULL([9],0)+ISNULL([10],0)+ISNULL([11],0)+ISNULL([12],0) AS 全年合計
FROM (SELECT a.廠商編號, v.統計項目, MONTH(a.單據日期) AS 月, v.數量
        FROM dbo.採購收退分析 a
       CROSS APPLY (VALUES (N'收貨數量',a.收貨數量),(N'退回數量',a.退回數量),(N'收貨+退回',a.收貨數量+a.退回數量)) v(統計項目,數量)
       WHERE YEAR(a.單據日期)=ISNULL(@年度,YEAR(GETDATE()))) s
PIVOT (SUM(數量) FOR 月 IN ([1],[2],[3],[4],[5],[6],[7],[8],[9],[10],[11],[12])) p;
GO

/* ---------- IM：所有庫存單據應產生的異動（庫存異動明細的唯一來源）
   工廠代碼 = 單據所屬工廠（SD/MM 取訂單/採購項次的工廠，工單類取工單的工廠），用來檢核倉庫是否屬於該工廠 ---------- */
CREATE VIEW dbo.庫存異動來源 AS
SELECT N'採購收貨' AS 單據類別, d.收貨編號 AS 單據編號, d.收貨項次 AS 單據項次, h.收貨日期 AS 異動日期, d.物料編號, d.倉庫代碼,  d.收貨數量 AS 異動數量, o.工廠代碼
  FROM dbo.採購收貨明細 d JOIN dbo.採購收貨主檔 h ON h.收貨編號=d.收貨編號
  JOIN dbo.廠商採購明細 o ON o.採購編號=d.採購編號 AND o.採購項次=d.採購項次
UNION ALL
SELECT N'收貨退回', d.退回編號, d.退回項次, h.退回日期, d.物料編號, d.倉庫代碼, -d.退回數量, o.工廠代碼
  FROM dbo.收貨退回明細 d JOIN dbo.收貨退回主檔 h ON h.退回編號=d.退回編號
  JOIN dbo.廠商採購明細 o ON o.採購編號=d.採購編號 AND o.採購項次=d.採購項次
UNION ALL
SELECT N'訂單出貨', d.出貨編號, d.出貨項次, h.出貨日期, d.物料編號, d.倉庫代碼, -d.出貨數量, o.工廠代碼
  FROM dbo.訂單出貨明細 d JOIN dbo.訂單出貨主檔 h ON h.出貨編號=d.出貨編號
  JOIN dbo.客戶訂單明細 o ON o.訂單編號=d.訂單編號 AND o.訂單項次=d.訂單項次
UNION ALL
SELECT N'出貨退回', d.退回編號, d.退回項次, h.退回日期, d.物料編號, d.倉庫代碼,  d.退回數量, o.工廠代碼
  FROM dbo.出貨退回明細 d JOIN dbo.出貨退回主檔 h ON h.退回編號=d.退回編號
  JOIN dbo.客戶訂單明細 o ON o.訂單編號=d.訂單編號 AND o.訂單項次=d.訂單項次
UNION ALL
SELECT N'庫存領用', d.領用編號, d.領用項次, h.領用日期, d.物料編號, d.倉庫代碼, -d.領用數量, h.工廠代碼
  FROM dbo.庫存領用明細 d JOIN dbo.庫存領用主檔 h ON h.領用編號=d.領用編號
UNION ALL
SELECT N'庫存繳庫', d.繳庫編號, d.繳庫項次, h.繳庫日期, d.物料編號, d.倉庫代碼,  d.繳庫數量, h.工廠代碼
  FROM dbo.庫存繳庫明細 d JOIN dbo.庫存繳庫主檔 h ON h.繳庫編號=d.繳庫編號
UNION ALL
SELECT N'工單領料', d.領料編號, d.領料項次, h.領料日期, d.物料編號, d.倉庫代碼, -d.領料數量, w.工廠代碼
  FROM dbo.工單領料明細 d JOIN dbo.工單領料主檔 h ON h.領料編號=d.領料編號
  JOIN dbo.生產工單主檔 w ON w.工單編號=d.工單編號
UNION ALL
SELECT N'工單入庫', d.入庫編號, d.入庫項次, h.入庫日期, d.物料編號, d.倉庫代碼,  d.入庫數量, w.工廠代碼
  FROM dbo.工單入庫明細 d JOIN dbo.工單入庫主檔 h ON h.入庫編號=d.入庫編號
  JOIN dbo.生產工單主檔 w ON w.工單編號=d.工單編號;
GO

CREATE VIEW dbo.現有庫存 AS
SELECT m.物料編號, w.工廠代碼, m.倉庫代碼, SUM(m.異動數量) AS 庫存數量, MAX(m.異動日期) AS 最後異動
FROM dbo.庫存異動明細 m
JOIN dbo.工廠倉庫維護 w ON w.倉庫代碼=m.倉庫代碼
GROUP BY m.物料編號, w.工廠代碼, m.倉庫代碼;
GO

/* ---------- PP：未結供給(+) / 需求(-)，庫存在途明細資料表的唯一來源 ---------- */
CREATE VIEW dbo.庫存在途來源 AS
SELECT N'採購未交' AS 來源, d.採購編號 AS 單據編號, d.採購項次 AS 單據項次, d.工廠代碼, d.物料編號,
       ISNULL(d.預定交期,h.採購日期) AS 預計日期,
       d.採購數量-d.收貨數量+d.退回數量 AS 供給數量, 0 AS 需求數量
  FROM dbo.廠商採購明細 d JOIN dbo.廠商採購主檔 h ON h.採購編號=d.採購編號
 WHERE d.採購數量-d.收貨數量+d.退回數量>0
UNION ALL
SELECT N'工單未入', h.工單編號, N'', h.工廠代碼, h.物料編號, ISNULL(h.預定完工,h.工單日期),
       h.生產數量-h.入庫數量, 0
  FROM dbo.生產工單主檔 h
 WHERE h.生產數量-h.入庫數量>0
UNION ALL
SELECT N'訂單未出', d.訂單編號, d.訂單項次, d.工廠代碼, d.物料編號, ISNULL(d.預定交期,h.訂單日期),
       0, d.訂單數量-d.出貨數量+d.退回數量
  FROM dbo.客戶訂單明細 d JOIN dbo.客戶訂單主檔 h ON h.訂單編號=d.訂單編號
 WHERE d.訂單數量-d.出貨數量+d.退回數量>0
UNION ALL
SELECT N'工單未領', d.工單編號, d.工單項次, h.工廠代碼, d.物料編號, ISNULL(d.預定領料,h.工單日期),
       0, d.應領用量-d.已領用量
  FROM dbo.生產工單明細 d JOIN dbo.生產工單主檔 h ON h.工單編號=d.工單編號
 WHERE d.應領用量-d.已領用量>0
UNION ALL
SELECT N'物料預留', d.預留編號, d.預留項次, h.工廠代碼, d.物料編號, ISNULL(d.預定交期,h.預留日期),
       0, d.預留數量
  FROM dbo.物料預留明細 d JOIN dbo.物料預留主檔 h ON h.預留編號=d.預留編號;
GO
