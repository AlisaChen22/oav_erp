# AGENT.md — 給 AI 代理的工作說明

本專案規則以 **CLAUDE.md** 為準，擴充做法見 **SKILL.md**。以下是代理執行任務時的流程與分工。

## 任務流程
1. **理解**：讀 CLAUDE.md、相關 sql/*.sql。確認需求能否完全用 T-SQL 物件達成（通常可以）。
2. **資料庫優先**：先改 sql/*.sql（資料表 → 視圖/函數 → 觸發程序 → API → 功能表 → 範例資料 → 驗證）。
3. **部署**：`python deploy.py --reset`；任何 `✗` 都要處理。
4. **驗證**：`python verify.py` 必須「全部通過」；新規則要加進 `dbo.驗證結果`。
5. **畫面**：只有在 SQL 無法表達時才改 `web/app.js`；改了就把 `web/sw.js` 的快取版本號 +1。
6. **文件**：更新 README.md、CLAUDE.md、SKILL.md、AGENT.md。
7. **發佈**：commit → push → `gh release create`，把 release 連結給使用者。

## 分工建議（多代理時）
| 代理 | 負責 | 不可做 |
|---|---|---|
| 資料庫代理 | sql/*.sql、觸發程序、驗證準則 | 改前端 |
| 前端代理 | web/（只限通用渲染與離線佇列） | 寫商業邏輯 |
| 驗證代理 | 跑 deploy / verify / 瀏覽器測試，回報不符 | 為了通過而修改驗證規則 |

## 安全
- 連線資訊只放 `config.local.json`（.gitignore 已排除），絕不 commit 密碼。
- `deploy.py --reset` 會刪除整個資料庫，只在開發用。
