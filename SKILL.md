---
name: oav-erp
description: 在 OAV ERP（PWA + SQL Server，邏輯全在 T-SQL）中新增或修改功能：主檔、單據、報表、樞紐、過帳規則、驗證準則。
---

# OAV ERP 開發技能

先讀 CLAUDE.md 的最高原則：**能用 T-SQL 解決就不寫前端。**

## 新增一個主檔維護
1. `sql/01_資料表.sql` 建資料表，必須有主鍵；外鍵會自動變成下拉選項。
2. `sql/05_功能表.sql` 加一列：`(功能代碼, 上層代碼, 名稱, N'主檔', N'資料表名', NULL, NULL, 排序)`。
3. `python deploy.py --reset` → 畫面自動出現，無需改前端。

## 新增一個單據（主檔＋明細）
1. 主檔：單一主鍵（編號）＋一個 date 欄位（自動編號用它的日期）。
2. 明細：主鍵 = (編號, 項次 nvarchar(4))，外鍵到主檔 `ON DELETE CASCADE`。
3. 功能表：類型 `N'單據'`，物件 = 主檔、明細 = 明細表、前綴 = 2 碼英文。
4. 若影響庫存：在 `dbo.庫存異動來源` 加一段 UNION ALL（含 工廠代碼），明細觸發程序呼叫 `dbo.同步庫存異動 N'類別', @k`，主檔 AFTER UPDATE 觸發程序也要呼叫。
5. 若影響供需：在 `dbo.庫存在途來源` 加一段，相關觸發程序呼叫 `dbo.重算供需 @料`。

## 新增一個過帳（回寫來源數量）
在來源明細的 AFTER INSERT,UPDATE,DELETE 觸發程序中：
```sql
UPDATE o SET 目標數量=ISNULL(x.數量,0)
  FROM dbo.目標表 o
  JOIN (SELECT 鍵1,鍵2 FROM inserted UNION SELECT 鍵1,鍵2 FROM deleted) k ON ...
  OUTER APPLY (SELECT SUM(s.數量) AS 數量 FROM dbo.來源表 s WHERE ...) x;
```
被回寫的欄位加進 `api.唯讀欄位`，並在目標表觸發程序加上限檢核（THROW 中文訊息）。
最後在 `sql/07_驗證.sql` 的 `dbo.驗證結果` 加一條驗證。

## 新增報表
- 一般報表：建 VIEW，功能表類型 `N'報表'`。
- 需要輸入條件：建 inline 資料表函數 `dbo.X(@參數 型別)`，前端自動出現輸入框（名稱以「年度」結尾者預設今年）。
- 樞紐：`CROSS APPLY (VALUES ...)` 展開統計項目 + `PIVOT (SUM(數量) FOR 月 IN ([1]..[12]))`；列順序用 `api.功能表.排序欄`。

## 新增多層鑽取報表
在 `api.鑽取層級` 為該功能加入各層：第 1 層 `對應` 為 NULL；第 n 層 `對應` = `{"本層欄位":"上層欄位"}`（例如 `{"異動日期":"日期"}`）。不必改前端。

## 新增單據拷貝來源
在 `api.拷貝來源` 加一列：
- `來源物件`：視圖（例如 已訂未出明細），`來源鍵`：`["訂單編號","訂單項次"]`
- `篩選對應`：`{"來源欄":"表頭欄"}`，`表頭對應`：`{"表頭欄":"來源欄"}`，`明細對應`：`{"明細欄":"來源欄"}`
單據畫面會自動出現「名稱」按鈕。欄位名稱都會對照系統目錄驗證。

## 完成檢查
1. `python deploy.py --reset` 無錯誤。
2. `python verify.py` 全部通過。
3. 用手機寬度瀏覽器實際點過新畫面。
4. 更新 README.md / CLAUDE.md / SKILL.md / AGENT.md，commit、push、建立 release。
