/* =========================================================
   OAV ERP 庫存管理系統 － 01 資料表
   ========================================================= */
USE oav37;
GO

/* ---------------- 組織架構 ---------------- */
CREATE TABLE dbo.銷售組織維護(
  銷售組織 nvarchar(20) NOT NULL CONSTRAINT PK_銷售組織維護 PRIMARY KEY,
  備註說明 nvarchar(20) NULL);

CREATE TABLE dbo.採購組織維護(
  採購組織 nvarchar(20) NOT NULL CONSTRAINT PK_採購組織維護 PRIMARY KEY,
  備註說明 nvarchar(20) NULL);

CREATE TABLE dbo.工廠代碼維護(
  工廠代碼 nvarchar(20) NOT NULL CONSTRAINT PK_工廠代碼維護 PRIMARY KEY,
  備註說明 nvarchar(20) NULL);

CREATE TABLE dbo.工廠倉庫維護(
  工廠代碼 nvarchar(20) NOT NULL CONSTRAINT FK_工廠倉庫維護_工廠 REFERENCES dbo.工廠代碼維護(工廠代碼),
  倉庫代碼 nvarchar(20) NOT NULL CONSTRAINT PK_工廠倉庫維護 PRIMARY KEY,   -- 倉庫代碼唯一
  備註說明 nvarchar(20) NULL);

/* ---------------- 主數據 ---------------- */
CREATE TABLE dbo.客戶資料維護(
  客戶編號 nvarchar(20) NOT NULL CONSTRAINT PK_客戶資料維護 PRIMARY KEY,
  備註說明 nvarchar(20) NULL);

CREATE TABLE dbo.廠商資料維護(
  廠商編號 nvarchar(20) NOT NULL CONSTRAINT PK_廠商資料維護 PRIMARY KEY,
  備註說明 nvarchar(20) NULL);

CREATE TABLE dbo.物料資料維護(
  物料編號 nvarchar(20) NOT NULL CONSTRAINT PK_物料資料維護 PRIMARY KEY,
  備註說明 nvarchar(20) NULL);

CREATE TABLE dbo.物管資料維護(
  物管編號 nvarchar(20) NOT NULL CONSTRAINT PK_物管資料維護 PRIMARY KEY,
  備註說明 nvarchar(20) NULL);

CREATE TABLE dbo.用量清單維護(
  主階編號 nvarchar(20) NOT NULL CONSTRAINT FK_用量清單維護_主階 REFERENCES dbo.物料資料維護(物料編號),
  子階編號 nvarchar(20) NOT NULL CONSTRAINT FK_用量清單維護_子階 REFERENCES dbo.物料資料維護(物料編號),
  標準用量 int NOT NULL CONSTRAINT CK_用量清單維護_標準用量 CHECK (標準用量>0),
  備註說明 nvarchar(20) NULL,
  CONSTRAINT PK_用量清單維護 PRIMARY KEY(主階編號,子階編號),
  CONSTRAINT CK_用量清單維護_主子階 CHECK (主階編號<>子階編號));

/* ---------------- SD 訂單 ---------------- */
CREATE TABLE dbo.客戶訂單主檔(
  訂單編號 nvarchar(20) NOT NULL CONSTRAINT PK_客戶訂單主檔 PRIMARY KEY,
  訂單日期 date NOT NULL CONSTRAINT DF_客戶訂單主檔_日期 DEFAULT (CONVERT(date,GETDATE())),
  銷售組織 nvarchar(20) NOT NULL CONSTRAINT FK_客戶訂單主檔_銷售組織 REFERENCES dbo.銷售組織維護(銷售組織),
  客戶編號 nvarchar(20) NOT NULL CONSTRAINT FK_客戶訂單主檔_客戶 REFERENCES dbo.客戶資料維護(客戶編號),
  備註說明 nvarchar(20) NULL);

CREATE TABLE dbo.客戶訂單明細(
  訂單編號 nvarchar(20) NOT NULL CONSTRAINT FK_客戶訂單明細_主檔 REFERENCES dbo.客戶訂單主檔(訂單編號) ON DELETE CASCADE,
  訂單項次 nvarchar(4)  NOT NULL,
  物料編號 nvarchar(20) NOT NULL CONSTRAINT FK_客戶訂單明細_物料 REFERENCES dbo.物料資料維護(物料編號),
  工廠代碼 nvarchar(20) NOT NULL CONSTRAINT FK_客戶訂單明細_工廠 REFERENCES dbo.工廠代碼維護(工廠代碼),  -- 新增：出貨工廠（供需依工廠計算）
  訂單數量 int NOT NULL CONSTRAINT CK_客戶訂單明細_訂單數量 CHECK (訂單數量>0),
  出貨數量 int NOT NULL CONSTRAINT DF_客戶訂單明細_出貨 DEFAULT (0),
  退回數量 int NOT NULL CONSTRAINT DF_客戶訂單明細_退回 DEFAULT (0),
  預定交期 date NULL,
  備註說明 nvarchar(20) NULL,
  CONSTRAINT PK_客戶訂單明細 PRIMARY KEY(訂單編號,訂單項次));

CREATE TABLE dbo.訂單出貨主檔(
  出貨編號 nvarchar(20) NOT NULL CONSTRAINT PK_訂單出貨主檔 PRIMARY KEY,
  出貨日期 date NOT NULL CONSTRAINT DF_訂單出貨主檔_日期 DEFAULT (CONVERT(date,GETDATE())),
  銷售組織 nvarchar(20) NOT NULL CONSTRAINT FK_訂單出貨主檔_銷售組織 REFERENCES dbo.銷售組織維護(銷售組織),
  客戶編號 nvarchar(20) NOT NULL CONSTRAINT FK_訂單出貨主檔_客戶 REFERENCES dbo.客戶資料維護(客戶編號),
  備註說明 nvarchar(20) NULL);

CREATE TABLE dbo.訂單出貨明細(
  出貨編號 nvarchar(20) NOT NULL CONSTRAINT FK_訂單出貨明細_主檔 REFERENCES dbo.訂單出貨主檔(出貨編號) ON DELETE CASCADE,
  出貨項次 nvarchar(4)  NOT NULL,
  訂單編號 nvarchar(20) NOT NULL,
  訂單項次 nvarchar(4)  NOT NULL,
  物料編號 nvarchar(20) NULL CONSTRAINT FK_訂單出貨明細_物料 REFERENCES dbo.物料資料維護(物料編號),  -- 空白時由訂單帶入
  倉庫代碼 nvarchar(20) NOT NULL CONSTRAINT FK_訂單出貨明細_倉庫 REFERENCES dbo.工廠倉庫維護(倉庫代碼),
  出貨數量 int NOT NULL CONSTRAINT CK_訂單出貨明細_數量 CHECK (出貨數量>0),
  備註說明 nvarchar(20) NULL,
  CONSTRAINT PK_訂單出貨明細 PRIMARY KEY(出貨編號,出貨項次),
  CONSTRAINT FK_訂單出貨明細_訂單 FOREIGN KEY(訂單編號,訂單項次) REFERENCES dbo.客戶訂單明細(訂單編號,訂單項次));

CREATE TABLE dbo.出貨退回主檔(
  退回編號 nvarchar(20) NOT NULL CONSTRAINT PK_出貨退回主檔 PRIMARY KEY,
  退回日期 date NOT NULL CONSTRAINT DF_出貨退回主檔_日期 DEFAULT (CONVERT(date,GETDATE())),
  銷售組織 nvarchar(20) NOT NULL CONSTRAINT FK_出貨退回主檔_銷售組織 REFERENCES dbo.銷售組織維護(銷售組織),
  客戶編號 nvarchar(20) NOT NULL CONSTRAINT FK_出貨退回主檔_客戶 REFERENCES dbo.客戶資料維護(客戶編號),
  備註說明 nvarchar(20) NULL);

CREATE TABLE dbo.出貨退回明細(
  退回編號 nvarchar(20) NOT NULL CONSTRAINT FK_出貨退回明細_主檔 REFERENCES dbo.出貨退回主檔(退回編號) ON DELETE CASCADE,
  退回項次 nvarchar(4)  NOT NULL,
  訂單編號 nvarchar(20) NOT NULL,
  訂單項次 nvarchar(4)  NOT NULL,
  物料編號 nvarchar(20) NULL CONSTRAINT FK_出貨退回明細_物料 REFERENCES dbo.物料資料維護(物料編號),
  倉庫代碼 nvarchar(20) NOT NULL CONSTRAINT FK_出貨退回明細_倉庫 REFERENCES dbo.工廠倉庫維護(倉庫代碼),
  退回數量 int NOT NULL CONSTRAINT CK_出貨退回明細_數量 CHECK (退回數量>0),
  備註說明 nvarchar(20) NULL,
  CONSTRAINT PK_出貨退回明細 PRIMARY KEY(退回編號,退回項次),
  CONSTRAINT FK_出貨退回明細_訂單 FOREIGN KEY(訂單編號,訂單項次) REFERENCES dbo.客戶訂單明細(訂單編號,訂單項次));

/* ---------------- MM 採購 ---------------- */
CREATE TABLE dbo.廠商採購主檔(
  採購編號 nvarchar(20) NOT NULL CONSTRAINT PK_廠商採購主檔 PRIMARY KEY,
  採購日期 date NOT NULL CONSTRAINT DF_廠商採購主檔_日期 DEFAULT (CONVERT(date,GETDATE())),
  採購組織 nvarchar(20) NOT NULL CONSTRAINT FK_廠商採購主檔_採購組織 REFERENCES dbo.採購組織維護(採購組織),
  廠商編號 nvarchar(20) NOT NULL CONSTRAINT FK_廠商採購主檔_廠商 REFERENCES dbo.廠商資料維護(廠商編號),
  備註說明 nvarchar(20) NULL);

CREATE TABLE dbo.廠商採購明細(
  採購編號 nvarchar(20) NOT NULL CONSTRAINT FK_廠商採購明細_主檔 REFERENCES dbo.廠商採購主檔(採購編號) ON DELETE CASCADE,
  採購項次 nvarchar(4)  NOT NULL,
  物料編號 nvarchar(20) NOT NULL CONSTRAINT FK_廠商採購明細_物料 REFERENCES dbo.物料資料維護(物料編號),
  工廠代碼 nvarchar(20) NOT NULL CONSTRAINT FK_廠商採購明細_工廠 REFERENCES dbo.工廠代碼維護(工廠代碼),  -- 新增：收貨工廠（供需依工廠計算）
  採購數量 int NOT NULL CONSTRAINT CK_廠商採購明細_採購數量 CHECK (採購數量>0),
  收貨數量 int NOT NULL CONSTRAINT DF_廠商採購明細_收貨 DEFAULT (0),
  退回數量 int NOT NULL CONSTRAINT DF_廠商採購明細_退回 DEFAULT (0),
  預定交期 date NULL,
  備註說明 nvarchar(20) NULL,
  CONSTRAINT PK_廠商採購明細 PRIMARY KEY(採購編號,採購項次));

CREATE TABLE dbo.採購收貨主檔(
  收貨編號 nvarchar(20) NOT NULL CONSTRAINT PK_採購收貨主檔 PRIMARY KEY,
  收貨日期 date NOT NULL CONSTRAINT DF_採購收貨主檔_日期 DEFAULT (CONVERT(date,GETDATE())),
  採購組織 nvarchar(20) NOT NULL CONSTRAINT FK_採購收貨主檔_採購組織 REFERENCES dbo.採購組織維護(採購組織),
  廠商編號 nvarchar(20) NOT NULL CONSTRAINT FK_採購收貨主檔_廠商 REFERENCES dbo.廠商資料維護(廠商編號),
  備註說明 nvarchar(20) NULL);

CREATE TABLE dbo.採購收貨明細(
  收貨編號 nvarchar(20) NOT NULL CONSTRAINT FK_採購收貨明細_主檔 REFERENCES dbo.採購收貨主檔(收貨編號) ON DELETE CASCADE,
  收貨項次 nvarchar(4)  NOT NULL,
  採購編號 nvarchar(20) NOT NULL,
  採購項次 nvarchar(4)  NOT NULL,
  物料編號 nvarchar(20) NULL CONSTRAINT FK_採購收貨明細_物料 REFERENCES dbo.物料資料維護(物料編號),
  倉庫代碼 nvarchar(20) NOT NULL CONSTRAINT FK_採購收貨明細_倉庫 REFERENCES dbo.工廠倉庫維護(倉庫代碼),
  收貨數量 int NOT NULL CONSTRAINT CK_採購收貨明細_數量 CHECK (收貨數量>0),
  備註說明 nvarchar(20) NULL,
  CONSTRAINT PK_採購收貨明細 PRIMARY KEY(收貨編號,收貨項次),
  CONSTRAINT FK_採購收貨明細_採購 FOREIGN KEY(採購編號,採購項次) REFERENCES dbo.廠商採購明細(採購編號,採購項次));

CREATE TABLE dbo.收貨退回主檔(
  退回編號 nvarchar(20) NOT NULL CONSTRAINT PK_收貨退回主檔 PRIMARY KEY,
  退回日期 date NOT NULL CONSTRAINT DF_收貨退回主檔_日期 DEFAULT (CONVERT(date,GETDATE())),
  採購組織 nvarchar(20) NOT NULL CONSTRAINT FK_收貨退回主檔_採購組織 REFERENCES dbo.採購組織維護(採購組織),
  廠商編號 nvarchar(20) NOT NULL CONSTRAINT FK_收貨退回主檔_廠商 REFERENCES dbo.廠商資料維護(廠商編號),
  備註說明 nvarchar(20) NULL);

CREATE TABLE dbo.收貨退回明細(
  退回編號 nvarchar(20) NOT NULL CONSTRAINT FK_收貨退回明細_主檔 REFERENCES dbo.收貨退回主檔(退回編號) ON DELETE CASCADE,
  退回項次 nvarchar(4)  NOT NULL,
  採購編號 nvarchar(20) NOT NULL,
  採購項次 nvarchar(4)  NOT NULL,
  物料編號 nvarchar(20) NULL CONSTRAINT FK_收貨退回明細_物料 REFERENCES dbo.物料資料維護(物料編號),
  倉庫代碼 nvarchar(20) NOT NULL CONSTRAINT FK_收貨退回明細_倉庫 REFERENCES dbo.工廠倉庫維護(倉庫代碼),
  退回數量 int NOT NULL CONSTRAINT CK_收貨退回明細_數量 CHECK (退回數量>0),
  備註說明 nvarchar(20) NULL,
  CONSTRAINT PK_收貨退回明細 PRIMARY KEY(退回編號,退回項次),
  CONSTRAINT FK_收貨退回明細_採購 FOREIGN KEY(採購編號,採購項次) REFERENCES dbo.廠商採購明細(採購編號,採購項次));

/* ---------------- IM 庫存 ---------------- */
CREATE TABLE dbo.物料預留主檔(
  預留編號 nvarchar(20) NOT NULL CONSTRAINT PK_物料預留主檔 PRIMARY KEY,
  預留日期 date NOT NULL CONSTRAINT DF_物料預留主檔_日期 DEFAULT (CONVERT(date,GETDATE())),
  工廠代碼 nvarchar(20) NOT NULL CONSTRAINT FK_物料預留主檔_工廠 REFERENCES dbo.工廠代碼維護(工廠代碼),
  物管編號 nvarchar(20) NULL CONSTRAINT FK_物料預留主檔_物管 REFERENCES dbo.物管資料維護(物管編號),
  備註說明 nvarchar(20) NULL);

CREATE TABLE dbo.物料預留明細(
  預留編號 nvarchar(20) NOT NULL CONSTRAINT FK_物料預留明細_主檔 REFERENCES dbo.物料預留主檔(預留編號) ON DELETE CASCADE,
  預留項次 nvarchar(4)  NOT NULL,
  物料編號 nvarchar(20) NOT NULL CONSTRAINT FK_物料預留明細_物料 REFERENCES dbo.物料資料維護(物料編號),
  預留數量 int NOT NULL CONSTRAINT CK_物料預留明細_數量 CHECK (預留數量>0),
  預定交期 date NULL,
  備註說明 nvarchar(20) NULL,
  CONSTRAINT PK_物料預留明細 PRIMARY KEY(預留編號,預留項次));

CREATE TABLE dbo.庫存領用主檔(
  領用編號 nvarchar(20) NOT NULL CONSTRAINT PK_庫存領用主檔 PRIMARY KEY,
  領用日期 date NOT NULL CONSTRAINT DF_庫存領用主檔_日期 DEFAULT (CONVERT(date,GETDATE())),
  工廠代碼 nvarchar(20) NOT NULL CONSTRAINT FK_庫存領用主檔_工廠 REFERENCES dbo.工廠代碼維護(工廠代碼),
  物管編號 nvarchar(20) NULL CONSTRAINT FK_庫存領用主檔_物管 REFERENCES dbo.物管資料維護(物管編號),
  備註說明 nvarchar(20) NULL);

CREATE TABLE dbo.庫存領用明細(
  領用編號 nvarchar(20) NOT NULL CONSTRAINT FK_庫存領用明細_主檔 REFERENCES dbo.庫存領用主檔(領用編號) ON DELETE CASCADE,
  領用項次 nvarchar(4)  NOT NULL,
  物料編號 nvarchar(20) NOT NULL CONSTRAINT FK_庫存領用明細_物料 REFERENCES dbo.物料資料維護(物料編號),
  倉庫代碼 nvarchar(20) NOT NULL CONSTRAINT FK_庫存領用明細_倉庫 REFERENCES dbo.工廠倉庫維護(倉庫代碼),
  領用數量 int NOT NULL CONSTRAINT CK_庫存領用明細_數量 CHECK (領用數量>0),
  備註說明 nvarchar(20) NULL,
  CONSTRAINT PK_庫存領用明細 PRIMARY KEY(領用編號,領用項次));

CREATE TABLE dbo.庫存繳庫主檔(
  繳庫編號 nvarchar(20) NOT NULL CONSTRAINT PK_庫存繳庫主檔 PRIMARY KEY,
  繳庫日期 date NOT NULL CONSTRAINT DF_庫存繳庫主檔_日期 DEFAULT (CONVERT(date,GETDATE())),
  工廠代碼 nvarchar(20) NOT NULL CONSTRAINT FK_庫存繳庫主檔_工廠 REFERENCES dbo.工廠代碼維護(工廠代碼),
  物管編號 nvarchar(20) NULL CONSTRAINT FK_庫存繳庫主檔_物管 REFERENCES dbo.物管資料維護(物管編號),
  備註說明 nvarchar(20) NULL);

CREATE TABLE dbo.庫存繳庫明細(
  繳庫編號 nvarchar(20) NOT NULL CONSTRAINT FK_庫存繳庫明細_主檔 REFERENCES dbo.庫存繳庫主檔(繳庫編號) ON DELETE CASCADE,
  繳庫項次 nvarchar(4)  NOT NULL,
  物料編號 nvarchar(20) NOT NULL CONSTRAINT FK_庫存繳庫明細_物料 REFERENCES dbo.物料資料維護(物料編號),
  倉庫代碼 nvarchar(20) NOT NULL CONSTRAINT FK_庫存繳庫明細_倉庫 REFERENCES dbo.工廠倉庫維護(倉庫代碼),
  繳庫數量 int NOT NULL CONSTRAINT CK_庫存繳庫明細_數量 CHECK (繳庫數量>0),
  備註說明 nvarchar(20) NULL,
  CONSTRAINT PK_庫存繳庫明細 PRIMARY KEY(繳庫編號,繳庫項次));

/* ---------------- PP 生產 ---------------- */
CREATE TABLE dbo.生產工單主檔(
  工單編號 nvarchar(20) NOT NULL CONSTRAINT PK_生產工單主檔 PRIMARY KEY,
  工單日期 date NOT NULL CONSTRAINT DF_生產工單主檔_日期 DEFAULT (CONVERT(date,GETDATE())),
  工廠代碼 nvarchar(20) NOT NULL CONSTRAINT FK_生產工單主檔_工廠 REFERENCES dbo.工廠代碼維護(工廠代碼),
  物料編號 nvarchar(20) NOT NULL CONSTRAINT FK_生產工單主檔_物料 REFERENCES dbo.物料資料維護(物料編號),  -- 新增：生產料號（展開用量清單用）
  預定完工 date NULL,
  生產數量 int NOT NULL CONSTRAINT CK_生產工單主檔_生產數量 CHECK (生產數量>0),
  入庫數量 int NOT NULL CONSTRAINT DF_生產工單主檔_入庫 DEFAULT (0),
  物管編號 nvarchar(20) NULL CONSTRAINT FK_生產工單主檔_物管 REFERENCES dbo.物管資料維護(物管編號),
  備註說明 nvarchar(20) NULL);

CREATE TABLE dbo.生產工單明細(
  工單編號 nvarchar(20) NOT NULL CONSTRAINT FK_生產工單明細_主檔 REFERENCES dbo.生產工單主檔(工單編號) ON DELETE CASCADE,
  工單項次 nvarchar(4)  NOT NULL,
  物料編號 nvarchar(20) NOT NULL CONSTRAINT FK_生產工單明細_物料 REFERENCES dbo.物料資料維護(物料編號),
  應領用量 int NOT NULL CONSTRAINT CK_生產工單明細_應領 CHECK (應領用量>=0),
  已領用量 int NOT NULL CONSTRAINT DF_生產工單明細_已領 DEFAULT (0),
  預定領料 date NULL,
  備註說明 nvarchar(20) NULL,
  CONSTRAINT PK_生產工單明細 PRIMARY KEY(工單編號,工單項次),
  CONSTRAINT UQ_生產工單明細_物料 UNIQUE(工單編號,物料編號));

CREATE TABLE dbo.工單入庫主檔(
  入庫編號 nvarchar(20) NOT NULL CONSTRAINT PK_工單入庫主檔 PRIMARY KEY,
  入庫日期 date NOT NULL CONSTRAINT DF_工單入庫主檔_日期 DEFAULT (CONVERT(date,GETDATE())),
  工廠代碼 nvarchar(20) NOT NULL CONSTRAINT FK_工單入庫主檔_工廠 REFERENCES dbo.工廠代碼維護(工廠代碼),
  物管編號 nvarchar(20) NULL CONSTRAINT FK_工單入庫主檔_物管 REFERENCES dbo.物管資料維護(物管編號),
  備註說明 nvarchar(20) NULL);

CREATE TABLE dbo.工單入庫明細(
  入庫編號 nvarchar(20) NOT NULL CONSTRAINT FK_工單入庫明細_主檔 REFERENCES dbo.工單入庫主檔(入庫編號) ON DELETE CASCADE,
  入庫項次 nvarchar(4)  NOT NULL,
  工單編號 nvarchar(20) NOT NULL CONSTRAINT FK_工單入庫明細_工單 REFERENCES dbo.生產工單主檔(工單編號),
  物料編號 nvarchar(20) NULL CONSTRAINT FK_工單入庫明細_物料 REFERENCES dbo.物料資料維護(物料編號),  -- 空白時由工單帶入
  倉庫代碼 nvarchar(20) NOT NULL CONSTRAINT FK_工單入庫明細_倉庫 REFERENCES dbo.工廠倉庫維護(倉庫代碼),
  入庫數量 int NOT NULL CONSTRAINT CK_工單入庫明細_數量 CHECK (入庫數量>0),
  備註說明 nvarchar(20) NULL,
  CONSTRAINT PK_工單入庫明細 PRIMARY KEY(入庫編號,入庫項次));

CREATE TABLE dbo.工單領料主檔(
  領料編號 nvarchar(20) NOT NULL CONSTRAINT PK_工單領料主檔 PRIMARY KEY,
  領料日期 date NOT NULL CONSTRAINT DF_工單領料主檔_日期 DEFAULT (CONVERT(date,GETDATE())),
  工廠代碼 nvarchar(20) NOT NULL CONSTRAINT FK_工單領料主檔_工廠 REFERENCES dbo.工廠代碼維護(工廠代碼),
  物管編號 nvarchar(20) NULL CONSTRAINT FK_工單領料主檔_物管 REFERENCES dbo.物管資料維護(物管編號),
  備註說明 nvarchar(20) NULL);

CREATE TABLE dbo.工單領料明細(
  領料編號 nvarchar(20) NOT NULL CONSTRAINT FK_工單領料明細_主檔 REFERENCES dbo.工單領料主檔(領料編號) ON DELETE CASCADE,
  領料項次 nvarchar(4)  NOT NULL,
  工單編號 nvarchar(20) NOT NULL,
  物料編號 nvarchar(20) NOT NULL,
  倉庫代碼 nvarchar(20) NOT NULL CONSTRAINT FK_工單領料明細_倉庫 REFERENCES dbo.工廠倉庫維護(倉庫代碼),
  領料數量 int NOT NULL CONSTRAINT CK_工單領料明細_數量 CHECK (領料數量>0),
  備註說明 nvarchar(20) NULL,
  CONSTRAINT PK_工單領料明細 PRIMARY KEY(領料編號,領料項次),
  CONSTRAINT FK_工單領料明細_工單 FOREIGN KEY(工單編號,物料編號) REFERENCES dbo.生產工單明細(工單編號,物料編號));

/* ---------------- 庫存帳（由觸發程序自動維護，不可手動輸入） ---------------- */
CREATE TABLE dbo.庫存異動明細(
  異動序號 bigint IDENTITY(1,1) NOT NULL CONSTRAINT PK_庫存異動明細 PRIMARY KEY,
  異動日期 date NOT NULL,
  單據類別 nvarchar(10) NOT NULL,
  單據編號 nvarchar(20) NOT NULL,
  單據項次 nvarchar(4)  NOT NULL,
  物料編號 nvarchar(20) NOT NULL,
  倉庫代碼 nvarchar(20) NOT NULL,
  異動數量 int NOT NULL,           -- 正：入庫　負：出庫
  建立時間 datetime2(0) NOT NULL CONSTRAINT DF_庫存異動明細_時間 DEFAULT (SYSDATETIME()),
  CONSTRAINT UQ_庫存異動明細_單據 UNIQUE(單據類別,單據編號,單據項次));
CREATE INDEX IX_庫存異動明細_料倉 ON dbo.庫存異動明細(倉庫代碼,物料編號,異動日期) INCLUDE(異動數量);

/* 每日庫存餘額：逐列 期初數量 + 本期入庫 - 本期出庫 = 期末數量（CHECK 強制） */
CREATE TABLE dbo.每日庫存餘額(
  物料編號 nvarchar(20) NOT NULL,
  倉庫代碼 nvarchar(20) NOT NULL,
  日期     date NOT NULL,
  期初數量 int NOT NULL,
  本期入庫 int NOT NULL,
  本期出庫 int NOT NULL,
  期末數量 int NOT NULL,
  CONSTRAINT PK_每日庫存餘額 PRIMARY KEY(物料編號,倉庫代碼,日期),
  CONSTRAINT CK_每日庫存餘額_平衡 CHECK (期初數量+本期入庫-本期出庫=期末數量));

/* 庫存在途明細：未結的供給(+)與需求(-)，由觸發程序自 dbo.庫存在途來源 同步 */
CREATE TABLE dbo.庫存在途明細(
  來源     nvarchar(10) NOT NULL,
  單據編號 nvarchar(20) NOT NULL,
  單據項次 nvarchar(4)  NOT NULL,
  工廠代碼 nvarchar(20) NOT NULL,
  物料編號 nvarchar(20) NOT NULL,
  預計日期 date NOT NULL,
  供給數量 int NOT NULL,
  需求數量 int NOT NULL,
  CONSTRAINT PK_庫存在途明細 PRIMARY KEY(來源,單據編號,單據項次));
CREATE INDEX IX_庫存在途明細_料 ON dbo.庫存在途明細(物料編號,工廠代碼,預計日期);

/* 每日供需餘額：逐列 在手數量 + 供給入庫 - 需求入庫 = 可用數量（CHECK 強制） */
CREATE TABLE dbo.每日供需餘額(
  物料編號 nvarchar(20) NOT NULL,
  工廠代碼 nvarchar(20) NOT NULL,
  日期     date NOT NULL,
  在手數量 int NOT NULL,
  供給入庫 int NOT NULL,
  需求入庫 int NOT NULL,
  可用數量 int NOT NULL,
  CONSTRAINT PK_每日供需餘額 PRIMARY KEY(物料編號,工廠代碼,日期),
  CONSTRAINT CK_每日供需餘額_平衡 CHECK (在手數量+供給入庫-需求入庫=可用數量));
GO

CREATE TYPE dbo.物料鍵 AS TABLE(物料編號 nvarchar(20) NOT NULL PRIMARY KEY);
GO
CREATE TYPE dbo.單據鍵 AS TABLE(
  單據編號 nvarchar(20) NOT NULL,
  單據項次 nvarchar(4)  NOT NULL,
  PRIMARY KEY(單據編號,單據項次));
GO
