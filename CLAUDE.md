# CLAUDE.md — OAV ERP 庫存管理系統

## 最高原則
**極大化 SQL Server，極少化前端。能用 T-SQL 物件（資料表、條件約束、觸發程序、視圖、函數、預存程序）解決的，就絕不寫在前端或 Python。**
- `web/app.js` 只做兩件事：依 `api.呼叫 {"動作":"定義"}` 回傳的中繼資料畫表單/列表，以及離線佇列。不可在前端寫商業規則、計算或檢核。
- `server.py` 只轉送 JSON 給 `EXEC api.呼叫`，不可加任何邏輯。
- 新功能 = 新 SQL 物件 + `api.功能表` 一列。前端通常不用改。

## 常用指令
```
python deploy.py --reset   # 重建 oav37（清空資料）並跑 sql/*.sql（依檔名順序）
python verify.py           # 驗證準則，必須全部「通過」
python server.py           # http://localhost:8000
```
連線設定在 `config.local.json`（不進 git；範本 `config.example.json`）。

## 架構重點
- 唯一 API：`api.呼叫 @請求 nvarchar(max)` → 單一欄位 `結果` 的 JSON `{"ok":true,"資料":...}` / `{"ok":false,"錯誤":"..."}`。
- 欄位中繼資料：`api.欄位資訊(@表)` 取自 sys.columns / 主鍵 / 外鍵 / 預設值；`api.唯讀欄位` 標記系統維護欄位。
- 存檔：`api.p_存列`（依主鍵 upsert）、`api.p_存明細`（明細同步，空白項次自動 0010、0020…）、`api.p_存單據`（空白編號自動取號 前綴+yyMMdd+3 碼）。
- 報表若是資料表函數，參數取自 sys.parameters，前端自動出現輸入框；`api.功能表.排序欄` 可設 ORDER BY。
- 多層鑽取：`api.鑽取層級`（功能代碼, 層次, 物件, 對應 {"本層欄":"上層欄"}, 排序欄）；`查詢` 帶 `層次`、`上層`。
- 單據拷貝：`api.拷貝來源`（來源物件、來源鍵、篩選對應、表頭對應、明細對應）+ `api.p_拷貝`；動作 `拷貝來源`（列出）、`拷貝`（回傳表頭值與明細列，不寫入資料庫）。
- 冪等：寫入帶 `請求編號`，`api.請求紀錄` 保證只執行一次。
- 庫存帳：所有庫存單據 → `dbo.庫存異動來源`（視圖）→ `dbo.同步庫存異動`（MERGE）→ `庫存異動明細` → 觸發重算 `每日庫存餘額`、禁止負庫存。
- 供需：`dbo.庫存在途來源`（視圖）→ `dbo.重算供需 @料`（MERGE）→ `庫存在途明細`、`每日供需餘額`（依 物料+工廠）。
- 所有觸發程序都要處理多列（set-based），並同時考慮 inserted 與 deleted。

## 撰寫 T-SQL 的注意事項
- `EXEC` 參數只能是常數或變數，不能是運算式（`@x=JSON_VALUE(...)` 會失敗）。
- 動態 SQL 中 JSON 路徑一律 `N'$."中文欄位"'`；物件名一律 `QUOTENAME`。
- 觸發程序中 `THROW` 前一句要有分號；錯誤訊息用中文並帶出單號/項次。
- `OPENJSON` 的 key/value 是 Latin1_General_BIN2，和欄位名稱比較時要加 `COLLATE DATABASE_DEFAULT`。
- 範例資料要依日期順序過帳，否則會觸發「庫存不足」（檢核是依日期逐日計算的）。

## 驗證準則（每次修改後都要跑 `python verify.py`）
出貨/退回/收貨/退回/入庫/領料 六項累加、每日庫存餘額 `期初+入-出=期末`、每日供需餘額 `在手+供給-需求=可用`、庫存帳與單據一致、在途與未結單據一致。

## 工作流程（使用者要求）
- 每開發到一個段落就 commit 並推到 GitHub（https://github.com/AlisaChen22/oav_erp），並用 `gh release create` 建立發佈，把連結給使用者。
- 每次任務完成都要更新 README.md、CLAUDE.md、SKILL.md、AGENT.md。
- 不可把 `config.local.json` 或任何密碼推上 GitHub。
