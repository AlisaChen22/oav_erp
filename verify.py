"""列出 dbo.驗證結果（驗證準則）。全部「通過」回傳 0，否則回傳 1。
用法：python verify.py
"""
import sys
import pyodbc
import db_config


def main():
    c = pyodbc.connect(db_config.conn_str(), autocommit=True, timeout=15)
    rows = c.execute('SELECT 序, 結果, 檢查筆數, 不符筆數, 驗證項目 FROM dbo.驗證結果 ORDER BY 序').fetchall()
    for r in rows:
        print(f'{r.序:>2}  {r.結果}  檢查 {r.檢查筆數:>4}  不符 {r.不符筆數:>3}  {r.驗證項目}')
    bad = sum(1 for r in rows if r.不符筆數)
    print('全部通過' if not bad else f'{bad} 項不符')
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main())
