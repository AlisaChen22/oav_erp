/* =========================================================
   05 功能表與唯讀欄位設定
   ========================================================= */
USE oav37;
GO
DELETE api.功能表;
INSERT api.功能表(功能代碼,上層代碼,名稱,類型,物件,明細,前綴,排序) VALUES
 (N'SD'  ,NULL  ,N'SD 訂單模組' ,N'模組',NULL,NULL,NULL,1000),
 (N'SD1' ,N'SD' ,N'組織架構'    ,N'群組',NULL,NULL,NULL,1100),
 (N'SD11',N'SD1',N'銷售組織維護',N'主檔',N'銷售組織維護',NULL,NULL,1110),
 (N'SD2' ,N'SD' ,N'主數據'      ,N'群組',NULL,NULL,NULL,1200),
 (N'SD21',N'SD2',N'客戶資料維護',N'主檔',N'客戶資料維護',NULL,NULL,1210),
 (N'SD3' ,N'SD' ,N'交易數據'    ,N'群組',NULL,NULL,NULL,1300),
 (N'SD31',N'SD3',N'客戶訂單維護',N'單據',N'客戶訂單主檔',N'客戶訂單明細',N'SO',1310),
 (N'SD32',N'SD3',N'訂單出貨維護',N'單據',N'訂單出貨主檔',N'訂單出貨明細',N'DN',1320),
 (N'SD33',N'SD3',N'出貨退回維護',N'單據',N'出貨退回主檔',N'出貨退回明細',N'SR',1330),
 (N'SD4' ,N'SD' ,N'報表輸出'    ,N'群組',NULL,NULL,NULL,1400),
 (N'SD41',N'SD4',N'已訂未出明細',N'報表',N'已訂未出明細',NULL,NULL,1410),
 (N'SD42',N'SD4',N'訂單出退分析',N'報表',N'訂單出退樞紐',NULL,NULL,1420),

 (N'MM'  ,NULL  ,N'MM 採購模組' ,N'模組',NULL,NULL,NULL,2000),
 (N'MM1' ,N'MM' ,N'組織架構'    ,N'群組',NULL,NULL,NULL,2100),
 (N'MM11',N'MM1',N'採購組織維護',N'主檔',N'採購組織維護',NULL,NULL,2110),
 (N'MM2' ,N'MM' ,N'主數據'      ,N'群組',NULL,NULL,NULL,2200),
 (N'MM21',N'MM2',N'廠商資料維護',N'主檔',N'廠商資料維護',NULL,NULL,2210),
 (N'MM3' ,N'MM' ,N'交易數據'    ,N'群組',NULL,NULL,NULL,2300),
 (N'MM31',N'MM3',N'廠商採購維護',N'單據',N'廠商採購主檔',N'廠商採購明細',N'PO',2310),
 (N'MM32',N'MM3',N'採購收貨維護',N'單據',N'採購收貨主檔',N'採購收貨明細',N'GR',2320),
 (N'MM33',N'MM3',N'收貨退回維護',N'單據',N'收貨退回主檔',N'收貨退回明細',N'RT',2330),
 (N'MM4' ,N'MM' ,N'報表輸出'    ,N'群組',NULL,NULL,NULL,2400),
 (N'MM41',N'MM4',N'已採未交明細',N'報表',N'已採未交明細',NULL,NULL,2410),
 (N'MM42',N'MM4',N'採購收退分析',N'報表',N'採購收退樞紐',NULL,NULL,2420),

 (N'IM'  ,NULL  ,N'IM 庫存模組' ,N'模組',NULL,NULL,NULL,3000),
 (N'IM1' ,N'IM' ,N'組織架構'    ,N'群組',NULL,NULL,NULL,3100),
 (N'IM11',N'IM1',N'工廠倉庫維護',N'主檔',N'工廠倉庫維護',NULL,NULL,3110),
 (N'IM2' ,N'IM' ,N'主數據'      ,N'群組',NULL,NULL,NULL,3200),
 (N'IM21',N'IM2',N'物料資料維護',N'主檔',N'物料資料維護',NULL,NULL,3210),
 (N'IM3' ,N'IM' ,N'交易數據'    ,N'群組',NULL,NULL,NULL,3300),
 (N'IM31',N'IM3',N'物料預留維護',N'單據',N'物料預留主檔',N'物料預留明細',N'RV',3310),
 (N'IM32',N'IM3',N'庫存領用維護',N'單據',N'庫存領用主檔',N'庫存領用明細',N'IS',3320),
 (N'IM33',N'IM3',N'庫存繳回維護',N'單據',N'庫存繳庫主檔',N'庫存繳庫明細',N'RC',3330),
 (N'IM4' ,N'IM' ,N'報表輸出'    ,N'群組',NULL,NULL,NULL,3400),
 (N'IM41',N'IM4',N'庫存異動明細',N'報表',N'庫存異動明細',NULL,NULL,3410),
 (N'IM42',N'IM4',N'每日庫存餘額',N'報表',N'每日庫存餘額',NULL,NULL,3420),
 (N'IM43',N'IM4',N'現有庫存查詢',N'報表',N'現有庫存',NULL,NULL,3430),

 (N'PP'  ,NULL  ,N'PP 生產模組' ,N'模組',NULL,NULL,NULL,4000),
 (N'PP1' ,N'PP' ,N'組織架構'    ,N'群組',NULL,NULL,NULL,4100),
 (N'PP11',N'PP1',N'工廠代碼維護',N'主檔',N'工廠代碼維護',NULL,NULL,4110),
 (N'PP2' ,N'PP' ,N'主數據'      ,N'群組',NULL,NULL,NULL,4200),
 (N'PP21',N'PP2',N'物管資料維護',N'主檔',N'物管資料維護',NULL,NULL,4210),
 (N'PP22',N'PP2',N'用量清單維護',N'主檔',N'用量清單維護',NULL,NULL,4220),
 (N'PP3' ,N'PP' ,N'交易數據'    ,N'群組',NULL,NULL,NULL,4300),
 (N'PP31',N'PP3',N'生產工單維護',N'單據',N'生產工單主檔',N'生產工單明細',N'MO',4310),
 (N'PP32',N'PP3',N'工單領料維護',N'單據',N'工單領料主檔',N'工單領料明細',N'MI',4320),
 (N'PP33',N'PP3',N'工單入庫維護',N'單據',N'工單入庫主檔',N'工單入庫明細',N'MR',4330),
 (N'PP4' ,N'PP' ,N'報表輸出'    ,N'群組',NULL,NULL,NULL,4400),
 (N'PP41',N'PP4',N'庫存在途明細',N'報表',N'庫存在途明細',NULL,NULL,4410),
 (N'PP42',N'PP4',N'每日供需餘額',N'報表',N'每日供需餘額',NULL,NULL,4420),

 (N'SY'  ,NULL  ,N'系統驗證'    ,N'模組',NULL,NULL,NULL,9000),
 (N'SY1' ,N'SY' ,N'驗證準則'    ,N'群組',NULL,NULL,NULL,9100),
 (N'SY11',N'SY1',N'過帳驗證結果',N'報表',N'驗證結果',NULL,NULL,9110);

-- 樞紐報表的列順序：依客戶/廠商，再依 數量、退回、合計
UPDATE api.功能表 SET 排序欄=N'[客戶編號], CHARINDEX([統計項目], N''出貨數量|退回數量|出貨+退回'')' WHERE 功能代碼=N'SD42';
UPDATE api.功能表 SET 排序欄=N'[廠商編號], CHARINDEX([統計項目], N''收貨數量|退回數量|收貨+退回'')' WHERE 功能代碼=N'MM42';

DELETE api.唯讀欄位;
INSERT api.唯讀欄位(表名,欄位) VALUES
 (N'客戶訂單明細',N'出貨數量'),(N'客戶訂單明細',N'退回數量'),
 (N'廠商採購明細',N'收貨數量'),(N'廠商採購明細',N'退回數量'),
 (N'生產工單主檔',N'入庫數量'),(N'生產工單明細',N'已領用量');
GO
