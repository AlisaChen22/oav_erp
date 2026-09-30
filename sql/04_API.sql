/* =========================================================
   04 API：前端唯一入口 api.呼叫 ＋ 由系統目錄驅動的通用 CRUD
   前端只送 JSON、只收 JSON；欄位、型別、主鍵、參照、唯讀全部由 SQL Server 提供。
   ========================================================= */
USE oav37;
GO
CREATE SCHEMA api;
GO

CREATE TABLE api.功能表(
  功能代碼 nvarchar(20) NOT NULL CONSTRAINT PK_功能表 PRIMARY KEY,
  上層代碼 nvarchar(20) NULL CONSTRAINT FK_功能表_上層 REFERENCES api.功能表(功能代碼),
  名稱     nvarchar(40) NOT NULL,
  類型     nvarchar(10) NOT NULL CONSTRAINT CK_功能表_類型 CHECK (類型 IN (N'模組',N'群組',N'主檔',N'單據',N'報表')),
  物件     sysname NULL,          -- 主檔/報表：資料表或視圖；單據：主檔資料表
  明細     sysname NULL,          -- 單據：明細資料表
  前綴     nvarchar(5) NULL,      -- 單據：自動編號前綴
  排序欄   nvarchar(200) NULL,    -- 報表：自訂 ORDER BY（伺服器端設定，非使用者輸入）
  排序     int NOT NULL);

/* 由系統維護、使用者不可輸入的欄位 */
CREATE TABLE api.唯讀欄位(
  表名 sysname NOT NULL,
  欄位 sysname NOT NULL,
  CONSTRAINT PK_唯讀欄位 PRIMARY KEY(表名,欄位));

/* 離線重傳的冪等紀錄：同一請求編號只執行一次，重送時直接回傳第一次的結果 */
CREATE TABLE api.請求紀錄(
  請求編號 nvarchar(50) NOT NULL CONSTRAINT PK_請求紀錄 PRIMARY KEY,
  動作     nvarchar(10) NOT NULL,
  功能代碼 nvarchar(20) NULL,
  請求內容 nvarchar(max) NULL,
  回應內容 nvarchar(max) NULL,
  建立時間 datetime2(0) NOT NULL CONSTRAINT DF_請求紀錄_時間 DEFAULT (SYSDATETIME()));
GO

/* ---------- 欄位中繼資料（取自系統目錄） ---------- */
CREATE FUNCTION api.欄位資訊(@表 sysname) RETURNS TABLE AS RETURN
SELECT c.column_id AS 序, c.name AS 欄位, t.name AS 型別,
       CASE WHEN t.name IN ('nvarchar','nchar') THEN c.max_length/2
            WHEN t.name IN ('varchar','char')   THEN c.max_length END AS 長度,
       c.is_nullable AS 可空,
       CAST(IIF(pk.column_id IS NULL,0,1) AS bit) AS 主鍵,
       CAST(IIF(c.is_identity=1 OR c.is_computed=1 OR r.欄位 IS NOT NULL OR o.type IN ('V','IF','TF'),1,0) AS bit) AS 唯讀,
       fk.參照表, fk.參照欄,
       dc.definition AS 預設值,
       CASE WHEN t.name IN ('nvarchar','nchar','varchar','char')
                 THEN t.name+'('+IIF(c.max_length=-1,'max',CAST(IIF(t.name LIKE 'n%',c.max_length/2,c.max_length) AS varchar(10)))+')'
            WHEN t.name IN ('decimal','numeric')
                 THEN t.name+'('+CAST(c.precision AS varchar(3))+','+CAST(c.scale AS varchar(3))+')'
            ELSE t.name END AS 宣告
FROM sys.columns c
JOIN sys.objects o ON o.object_id=c.object_id
JOIN sys.types   t ON t.user_type_id=c.user_type_id
LEFT JOIN (SELECT ic.object_id, ic.column_id FROM sys.indexes i
             JOIN sys.index_columns ic ON ic.object_id=i.object_id AND ic.index_id=i.index_id
            WHERE i.is_primary_key=1) pk ON pk.object_id=c.object_id AND pk.column_id=c.column_id
LEFT JOIN api.唯讀欄位 r ON r.表名=o.name AND r.欄位=c.name
LEFT JOIN sys.default_constraints dc ON dc.parent_object_id=c.object_id AND dc.parent_column_id=c.column_id
OUTER APPLY (SELECT TOP 1 OBJECT_NAME(f.referenced_object_id) AS 參照表,
                    COL_NAME(f.referenced_object_id,f.referenced_column_id) AS 參照欄
               FROM sys.foreign_key_columns f
              WHERE f.parent_object_id=c.object_id AND f.parent_column_id=c.column_id
              ORDER BY f.constraint_object_id) fk
WHERE c.object_id=OBJECT_ID(N'dbo.'+QUOTENAME(@表));
GO

/* ---------- 由中繼資料組出存檔用的動態 SQL 片段 ---------- */
CREATE FUNCTION api.存檔語句(@表 sysname) RETURNS TABLE AS RETURN
SELECT
  STRING_AGG(CAST(QUOTENAME(欄位)+N' '+宣告+N' N''$."'+欄位+N'"''' AS nvarchar(max)), N',') WITHIN GROUP (ORDER BY 序) AS 結構,
  STRING_AGG(CASE WHEN 主鍵=1 THEN CAST(N't.'+QUOTENAME(欄位)+N'=s.'+QUOTENAME(欄位) AS nvarchar(max)) END, N' AND ') WITHIN GROUP (ORDER BY 序) AS 對應,
  STRING_AGG(CASE WHEN 主鍵=0 THEN CAST(QUOTENAME(欄位)+N'=s.'+QUOTENAME(欄位) AS nvarchar(max)) END, N',') WITHIN GROUP (ORDER BY 序) AS 更新,
  STRING_AGG(CAST(QUOTENAME(欄位) AS nvarchar(max)), N',') WITHIN GROUP (ORDER BY 序) AS 欄位,
  STRING_AGG(CAST(CASE WHEN 可空=0 AND 預設值 IS NOT NULL THEN N'ISNULL(s.'+QUOTENAME(欄位)+N','+預設值+N')'
                       ELSE N's.'+QUOTENAME(欄位) END AS nvarchar(max)), N',') WITHIN GROUP (ORDER BY 序) AS 值
FROM api.欄位資訊(@表)
WHERE 唯讀=0 OR 主鍵=1;
GO

/* ---------- 單列新增/修改（依主鍵 upsert） ---------- */
CREATE PROC api.p_存列 @表 sysname, @j nvarchar(max) AS
BEGIN
  SET NOCOUNT ON;
  DECLARE @結構 nvarchar(max), @對應 nvarchar(max), @更新 nvarchar(max), @欄位 nvarchar(max), @值 nvarchar(max), @sql nvarchar(max);
  SELECT @結構=結構, @對應=對應, @更新=更新, @欄位=欄位, @值=值 FROM api.存檔語句(@表);
  IF @對應 IS NULL THROW 50100, N'資料表不存在或沒有主鍵', 1;
  SET @sql = CASE WHEN @更新 IS NULL THEN N'IF NOT EXISTS(SELECT 1 FROM dbo.'+QUOTENAME(@表)+N' t JOIN OPENJSON(@j) WITH ('+@結構+N') s ON '+@對應+N')'
                  ELSE N'UPDATE t SET '+@更新+N' FROM dbo.'+QUOTENAME(@表)+N' t JOIN OPENJSON(@j) WITH ('+@結構+N') s ON '+@對應+N';
IF @@ROWCOUNT=0' END + N'
  INSERT dbo.'+QUOTENAME(@表)+N'('+@欄位+N') SELECT '+@值+N' FROM OPENJSON(@j) WITH ('+@結構+N') s;';
  EXEC sp_executesql @sql, N'@j nvarchar(max)', @j=@j;
END
GO

/* ---------- 單據明細同步（新增/修改/刪除項次，空白項次自動編號） ---------- */
CREATE PROC api.p_存明細 @表 sysname, @父欄 sysname, @父值 nvarchar(20), @arr nvarchar(max) AS
BEGIN
  SET NOCOUNT ON;
  DECLARE @結構 nvarchar(max), @對應 nvarchar(max), @更新 nvarchar(max), @欄位 nvarchar(max), @值 nvarchar(max), @sql nvarchar(max), @項 sysname;
  SELECT @結構=結構, @對應=對應, @更新=更新, @欄位=欄位, @值=值 FROM api.存檔語句(@表);
  SELECT TOP 1 @項=QUOTENAME(欄位) FROM api.欄位資訊(@表) WHERE 主鍵=1 AND 欄位<>@父欄 ORDER BY 序;
  DECLARE @T nvarchar(300) = N'dbo.'+QUOTENAME(@表), @P sysname = QUOTENAME(@父欄);
  SET @sql = N'
SELECT CAST(j.[key] AS int) AS [#序], s.* INTO #s
  FROM OPENJSON(@arr) j CROSS APPLY OPENJSON(j.value) WITH ('+@結構+N') s;
UPDATE #s SET '+@P+N'=@父值;
DECLARE @m int = (SELECT MAX(n) FROM (SELECT TRY_CAST('+@項+N' AS int) n FROM '+@T+N' WHERE '+@P+N'=@父值
                                      UNION ALL SELECT TRY_CAST('+@項+N' AS int) FROM #s) x);
WITH b AS (SELECT '+@項+N', ROW_NUMBER() OVER (ORDER BY [#序]) AS rn FROM #s WHERE ISNULL('+@項+N',N'''')=N'''')
UPDATE b SET '+@項+N'=RIGHT(N''000''+CAST(ISNULL(@m,0)+rn*10 AS nvarchar(10)),4);
DELETE t FROM '+@T+N' t WHERE t.'+@P+N'=@父值 AND NOT EXISTS(SELECT 1 FROM #s s WHERE '+@對應+N');'
  + ISNULL(N'
UPDATE t SET '+@更新+N' FROM '+@T+N' t JOIN #s s ON '+@對應+N';', N'') + N'
INSERT '+@T+N'('+@欄位+N') SELECT '+@值+N' FROM #s s WHERE NOT EXISTS(SELECT 1 FROM '+@T+N' t WHERE '+@對應+N') ORDER BY s.[#序];';
  EXEC sp_executesql @sql, N'@arr nvarchar(max), @父值 nvarchar(20)', @arr=@arr, @父值=@父值;
END
GO

/* ---------- 單據存檔（主檔＋明細，空白編號自動取號：前綴+yyMMdd+流水3碼） ---------- */
CREATE PROC api.p_存單據 @功能 nvarchar(20), @j nvarchar(max), @o nvarchar(max) OUTPUT AS
BEGIN
  SET NOCOUNT ON;
  DECLARE @主 sysname, @明 sysname, @前綴 nvarchar(5), @鍵 sysname, @日期欄 sysname, @編號 nvarchar(20), @sql nvarchar(max), @新 bit = 0, @n int;
  SELECT @主=物件, @明=明細, @前綴=前綴 FROM api.功能表 WHERE 功能代碼=@功能;
  SELECT TOP 1 @鍵=欄位 FROM api.欄位資訊(@主) WHERE 主鍵=1 ORDER BY 序;
  SELECT TOP 1 @日期欄=欄位 FROM api.欄位資訊(@主) WHERE 型別='date' ORDER BY 序;
  SET @編號 = NULLIF(LTRIM(RTRIM(JSON_VALUE(@j, N'$."'+@鍵+N'"'))),N'');

  IF @編號 IS NULL
  BEGIN
    DECLARE @d date = ISNULL(TRY_CAST(JSON_VALUE(@j, N'$."'+@日期欄+N'"') AS date), CAST(GETDATE() AS date));
    DECLARE @p nvarchar(20) = ISNULL(@前綴,N'') + FORMAT(@d,'yyMMdd'), @max nvarchar(20);
    SET @sql = N'SELECT @max=MAX('+QUOTENAME(@鍵)+N') FROM dbo.'+QUOTENAME(@主)+N' WITH (UPDLOCK,HOLDLOCK) WHERE '
             + QUOTENAME(@鍵)+N' LIKE @p+N''[0-9][0-9][0-9]'' AND LEN('+QUOTENAME(@鍵)+N')=LEN(@p)+3';
    EXEC sp_executesql @sql, N'@p nvarchar(20), @max nvarchar(20) OUTPUT', @p=@p, @max=@max OUTPUT;
    SET @編號 = @p + RIGHT(N'00'+CAST(ISNULL(CAST(RIGHT(@max,3) AS int),0)+1 AS nvarchar(10)),3);
    SET @j = JSON_MODIFY(@j, N'$."'+@鍵+N'"', @編號);
    SET @新 = 1;
  END
  ELSE
  BEGIN
    SET @sql = N'SELECT @n=COUNT(*) FROM dbo.'+QUOTENAME(@主)+N' WHERE '+QUOTENAME(@鍵)+N'=@v';
    EXEC sp_executesql @sql, N'@v nvarchar(20), @n int OUTPUT', @v=@編號, @n=@n OUTPUT;
    SET @新 = IIF(@n=0,1,0);
  END

  EXEC api.p_存列 @主, @j;

  DECLARE @arr nvarchar(max) = JSON_QUERY(@j, N'$."明細"');
  -- 新單據且未帶明細時不處理明細（保留觸發程序自動產生的明細，例如工單展開用量清單）
  IF @arr IS NOT NULL AND NOT (@新=1 AND NOT EXISTS(SELECT 1 FROM OPENJSON(@arr)))
    EXEC api.p_存明細 @明, @鍵, @編號, @arr;

  SET @o = (SELECT @鍵 AS 鍵欄, @編號 AS 編號, @新 AS 新增 FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
END
GO

/* ---------- 依主鍵刪除（單據主檔刪除時，明細以 ON DELETE CASCADE 連動並觸發回沖） ---------- */
CREATE PROC api.p_刪除 @表 sysname, @k nvarchar(max) AS
BEGIN
  SET NOCOUNT ON;
  DECLARE @結構 nvarchar(max), @對應 nvarchar(max), @sql nvarchar(max);
  SELECT @結構 = STRING_AGG(CAST(QUOTENAME(欄位)+N' '+宣告+N' N''$."'+欄位+N'"''' AS nvarchar(max)), N','),
         @對應 = STRING_AGG(CAST(N't.'+QUOTENAME(欄位)+N'=s.'+QUOTENAME(欄位) AS nvarchar(max)), N' AND ')
    FROM api.欄位資訊(@表) WHERE 主鍵=1;
  SET @sql = N'DELETE t FROM dbo.'+QUOTENAME(@表)+N' t JOIN OPENJSON(@k) WITH ('+@結構+N') s ON '+@對應+N';
IF @@ROWCOUNT=0 THROW 50101, N''資料不存在（可能已被刪除）'', 1;';
  EXEC sp_executesql @sql, N'@k nvarchar(max)', @k=@k;
END
GO

/* ---------- 列表查詢（關鍵字比對所有文字欄位；資料表函數的參數由 sys.parameters 決定） ---------- */
CREATE PROC api.p_查詢 @物件 sysname, @類型 nvarchar(10), @關鍵字 nvarchar(100), @參數 nvarchar(max), @排序 nvarchar(200),
                       @o nvarchar(max) OUTPUT AS
BEGIN
  SET NOCOUNT ON;
  DECLARE @w nvarchar(max), @ob nvarchar(max), @args nvarchar(max) = N'', @sql nvarchar(max), @id int = OBJECT_ID(N'dbo.'+QUOTENAME(@物件));
  IF EXISTS(SELECT 1 FROM sys.objects WHERE object_id=@id AND type IN ('IF','TF'))
    SELECT @args = N'(' + ISNULL(STRING_AGG(CAST(N'TRY_CAST(JSON_VALUE(@參數,N''$."'+STUFF(p.name,1,1,N'')+N'"'') AS '
                   + TYPE_NAME(p.user_type_id) + IIF(TYPE_NAME(p.user_type_id) LIKE N'%char',N'('+CAST(p.max_length/IIF(TYPE_NAME(p.user_type_id) LIKE N'n%',2,1) AS nvarchar(10))+N')',N'')
                   + N')' AS nvarchar(max)), N',') WITHIN GROUP (ORDER BY p.parameter_id), N'') + N')'
      FROM sys.parameters p WHERE p.object_id=@id AND p.parameter_id>0;
  SELECT @w = STRING_AGG(CAST(QUOTENAME(欄位)+N' LIKE @q' AS nvarchar(max)), N' OR ')
    FROM api.欄位資訊(@物件) WHERE 型別 IN ('nvarchar','varchar','nchar','char');
  SELECT @ob = STRING_AGG(CAST(QUOTENAME(欄位)+IIF(@類型=N'單據' OR 型別 IN ('bigint'),N' DESC',N'') AS nvarchar(max)), N',') WITHIN GROUP (ORDER BY 序)
    FROM api.欄位資訊(@物件) WHERE 主鍵=1;
  IF @ob IS NULL
    SELECT @ob = STRING_AGG(CAST(QUOTENAME(欄位) AS nvarchar(max)), N',') WITHIN GROUP (ORDER BY 序)
      FROM api.欄位資訊(@物件) WHERE 序<=3;
  SET @ob = ISNULL(@排序, @ob);
  SET @sql = N'SET @o=(SELECT TOP (500) * FROM dbo.'+QUOTENAME(@物件)+@args
           + IIF(NULLIF(@關鍵字,N'') IS NULL OR @w IS NULL, N'', N' WHERE '+@w)
           + N' ORDER BY '+@ob+N' FOR JSON PATH, INCLUDE_NULL_VALUES)';
  DECLARE @q nvarchar(102) = N'%'+ISNULL(@關鍵字,N'')+N'%';
  EXEC sp_executesql @sql, N'@q nvarchar(102), @參數 nvarchar(max), @o nvarchar(max) OUTPUT', @q=@q, @參數=@參數, @o=@o OUTPUT;
  SET @o = ISNULL(@o, N'[]');
END
GO
/* ---------- 讀取單據（主檔＋明細） ---------- */
CREATE PROC api.p_讀取 @功能 nvarchar(20), @k nvarchar(max), @o nvarchar(max) OUTPUT AS
BEGIN
  SET NOCOUNT ON;
  DECLARE @主 sysname, @明 sysname, @鍵 sysname, @項 sysname, @sql nvarchar(max);
  SELECT @主=物件, @明=明細 FROM api.功能表 WHERE 功能代碼=@功能;
  SELECT TOP 1 @鍵=欄位 FROM api.欄位資訊(@主) WHERE 主鍵=1 ORDER BY 序;
  SELECT TOP 1 @項=欄位 FROM api.欄位資訊(@明) WHERE 主鍵=1 AND 欄位<>@鍵 ORDER BY 序;
  SET @sql = N'SET @o=(SELECT h.*, JSON_QUERY(ISNULL((SELECT d.* FROM dbo.'+QUOTENAME(@明)+N' d WHERE d.'+QUOTENAME(@鍵)+N'=h.'+QUOTENAME(@鍵)
           + N' ORDER BY d.'+QUOTENAME(@項)+N' FOR JSON PATH, INCLUDE_NULL_VALUES),N''[]'')) AS 明細 FROM dbo.'+QUOTENAME(@主)+N' h WHERE h.'
           + QUOTENAME(@鍵)+N'=@v FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES)';
  DECLARE @v nvarchar(20) = JSON_VALUE(@k, N'$."'+@鍵+N'"');
  EXEC sp_executesql @sql, N'@v nvarchar(20), @o nvarchar(max) OUTPUT', @v=@v, @o=@o OUTPUT;
  IF @o IS NULL THROW 50102, N'單據不存在', 1;
END
GO

/* ---------- 下拉選項：依外鍵自動找參照表；複合外鍵以前面欄位的值過濾 ---------- */
CREATE PROC api.p_選項 @表 sysname, @欄 sysname, @列 nvarchar(max), @o nvarchar(max) OUTPUT AS
BEGIN
  SET NOCOUNT ON;
  DECLARE @fk int, @ord int, @rt sysname, @rc sysname, @w nvarchar(max), @d nvarchar(max), @sql nvarchar(max);
  SELECT TOP 1 @fk=f.constraint_object_id, @ord=f.constraint_column_id,
         @rt=OBJECT_NAME(f.referenced_object_id), @rc=COL_NAME(f.referenced_object_id,f.referenced_column_id)
    FROM sys.foreign_key_columns f
   WHERE f.parent_object_id=OBJECT_ID(N'dbo.'+QUOTENAME(@表)) AND COL_NAME(f.parent_object_id,f.parent_column_id)=@欄
   ORDER BY f.constraint_object_id;
  IF @rt IS NULL BEGIN SET @o=N'[]'; RETURN; END

  SELECT @w = STRING_AGG(CAST(N'(JSON_VALUE(@列,N''$."'+COL_NAME(f.parent_object_id,f.parent_column_id)+N'"'') IS NULL OR '
                         + QUOTENAME(COL_NAME(f.referenced_object_id,f.referenced_column_id))
                         + N'=JSON_VALUE(@列,N''$."'+COL_NAME(f.parent_object_id,f.parent_column_id)+N'"''))' AS nvarchar(max)), N' AND ')
    FROM sys.foreign_key_columns f WHERE f.constraint_object_id=@fk AND f.constraint_column_id<@ord;

  SET @d = CASE WHEN @rc<>N'物料編號' AND COL_LENGTH(N'dbo.'+QUOTENAME(@rt),N'物料編號') IS NOT NULL
                THEN N'CONCAT([物料編號],N'' '',[備註說明])'
                WHEN COL_LENGTH(N'dbo.'+QUOTENAME(@rt),N'備註說明') IS NOT NULL THEN N'[備註說明]'
                ELSE N'N''''' END;
  SET @sql = N'SET @o=(SELECT TOP (300) 值, MAX(說明) AS 說明 FROM (SELECT '+QUOTENAME(@rc)+N' AS 值, '+@d+N' AS 說明 FROM dbo.'+QUOTENAME(@rt)
           + ISNULL(N' WHERE '+@w, N'') + N') x GROUP BY 值 ORDER BY 值 FOR JSON PATH)';
  EXEC sp_executesql @sql, N'@列 nvarchar(max), @o nvarchar(max) OUTPUT', @列=@列, @o=@o OUTPUT;
  SET @o = ISNULL(@o, N'[]');
END
GO

/* =========================================================
   api.呼叫：前端唯一入口
   請求：{"動作":"功能表|定義|查詢|讀取|存檔|刪除|選項", "功能":"...", "請求編號":"uuid",
          "資料":{...}, "鍵":{...}, "關鍵字":"...", "表":"...", "欄":"...", "列":{...}}
   回應：{"ok":true,"資料":...} 或 {"ok":false,"錯誤":"..."}
   ========================================================= */
CREATE PROC api.呼叫 @請求 nvarchar(max) AS
BEGIN
  SET NOCOUNT ON; SET XACT_ABORT ON;
  DECLARE @動作 nvarchar(10) = JSON_VALUE(@請求,N'$."動作"'),
          @功能 nvarchar(20) = JSON_VALUE(@請求,N'$."功能"'),
          @id   nvarchar(50) = JSON_VALUE(@請求,N'$."請求編號"'),
          @資料 nvarchar(max) = JSON_QUERY(@請求,N'$."資料"'),
          @鍵   nvarchar(max) = JSON_QUERY(@請求,N'$."鍵"'),
          @關鍵字 nvarchar(100) = JSON_VALUE(@請求,N'$."關鍵字"'),
          @表 sysname = JSON_VALUE(@請求,N'$."表"'), @欄 sysname = JSON_VALUE(@請求,N'$."欄"'),
          @列 nvarchar(max) = JSON_QUERY(@請求,N'$."列"'),
          @參數 nvarchar(max) = ISNULL(JSON_QUERY(@請求,N'$."參數"'),N'{}'),
          @o nvarchar(max), @r nvarchar(max),
          @類型 nvarchar(10), @物件 sysname, @明細 sysname, @名稱 nvarchar(40), @排序 nvarchar(200);
  SELECT @類型=類型, @物件=物件, @明細=明細, @名稱=名稱, @排序=排序欄 FROM api.功能表 WHERE 功能代碼=@功能;

  -- 重送：已處理過的請求直接回覆原結果
  IF @id IS NOT NULL
  BEGIN
    SELECT @r=回應內容 FROM api.請求紀錄 WHERE 請求編號=@id;
    IF @r IS NOT NULL BEGIN SELECT JSON_MODIFY(@r,N'$."重送"',CAST(1 AS bit)) AS 結果; RETURN; END
  END

  BEGIN TRY
    BEGIN TRAN;
    IF @動作=N'功能表'
      SET @o = (SELECT 功能代碼,上層代碼,名稱,類型 FROM api.功能表 ORDER BY 排序 FOR JSON PATH);
    ELSE IF @功能 IS NOT NULL AND @類型 IS NULL
      THROW 50110, N'功能代碼不存在', 1;
    ELSE IF @動作=N'定義'
      SET @o = (SELECT @功能 AS 功能, @名稱 AS 名稱, @類型 AS 類型, @物件 AS 物件, @明細 AS 明細表,
                       JSON_QUERY((SELECT * FROM api.欄位資訊(@物件) ORDER BY 序 FOR JSON PATH)) AS 欄位,
                       JSON_QUERY((SELECT * FROM api.欄位資訊(@明細) ORDER BY 序 FOR JSON PATH)) AS 明細欄位,
                       JSON_QUERY((SELECT STUFF(p.name,1,1,N'') AS 參數, TYPE_NAME(p.user_type_id) AS 型別,
                                          IIF(p.name LIKE N'%年度', CAST(YEAR(GETDATE()) AS nvarchar(10)), NULL) AS 預設
                                     FROM sys.parameters p WHERE p.object_id=OBJECT_ID(N'dbo.'+QUOTENAME(@物件)) AND p.parameter_id>0
                                    ORDER BY p.parameter_id FOR JSON PATH)) AS 參數
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    ELSE IF @動作=N'查詢'
      EXEC api.p_查詢 @物件, @類型, @關鍵字, @參數, @排序, @o OUTPUT;
    ELSE IF @動作=N'讀取'
      EXEC api.p_讀取 @功能, @鍵, @o OUTPUT;
    ELSE IF @動作=N'選項'
      EXEC api.p_選項 @表, @欄, @列, @o OUTPUT;
    ELSE IF @動作 IN (N'存檔',N'刪除')
    BEGIN
      IF @類型 NOT IN (N'主檔',N'單據') THROW 50111, N'此功能為唯讀', 1;
      EXEC sp_getapplock @Resource=@功能, @LockMode='Exclusive', @LockOwner='Transaction';
      IF @動作=N'存檔' AND @類型=N'單據' EXEC api.p_存單據 @功能, @資料, @o OUTPUT;
      ELSE IF @動作=N'存檔' BEGIN EXEC api.p_存列 @物件, @資料; SET @o=@資料; END
      ELSE EXEC api.p_刪除 @物件, @鍵;
    END
    ELSE THROW 50112, N'未知的動作', 1;

    SET @r = N'{"ok":true,"資料":'+ISNULL(@o,N'null')+N'}';
    IF @id IS NOT NULL AND @動作 IN (N'存檔',N'刪除')
      INSERT api.請求紀錄(請求編號,動作,功能代碼,請求內容,回應內容) VALUES(@id,@動作,@功能,@請求,@r);
    COMMIT;
  END TRY
  BEGIN CATCH
    IF @@TRANCOUNT>0 ROLLBACK;
    -- 同一請求併發重送：以先完成者的結果回覆
    IF @id IS NOT NULL AND ERROR_NUMBER() IN (2627,2601)
    BEGIN
      SELECT @r=回應內容 FROM api.請求紀錄 WHERE 請求編號=@id;
      IF @r IS NOT NULL BEGIN SELECT JSON_MODIFY(@r,N'$."重送"',CAST(1 AS bit)) AS 結果; RETURN; END
    END
    DECLARE @e int = ERROR_NUMBER(), @m nvarchar(2048) = ERROR_MESSAGE();
    SET @m = CASE @e WHEN 547  THEN N'資料關聯檢查失敗（參照的資料不存在，或此資料已被其他單據使用）。' + @m
                     WHEN 2627 THEN N'資料重複（主鍵或唯一值已存在）。' + @m
                     WHEN 2601 THEN N'資料重複（主鍵或唯一值已存在）。' + @m
                     WHEN 515  THEN N'必填欄位未輸入。' + @m
                     ELSE @m END;
    SET @r = (SELECT CAST(0 AS bit) AS ok, @m AS 錯誤, @e AS 錯誤碼 FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
  END CATCH
  SELECT @r AS 結果;
END
GO
