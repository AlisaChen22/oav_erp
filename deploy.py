"""建立 oav37 資料庫並依序執行 sql/*.sql。
用法：python deploy.py            （資料庫不存在才建立）
      python deploy.py --reset    （刪除重建，資料全部清空）
"""
import glob, json, os, re, sys
import pyodbc
import db_config

SERVER = db_config.conn_str(with_db=False)
DB = db_config.load()['database']
HERE = os.path.dirname(os.path.abspath(__file__))


def batches(path):
    text = open(path, encoding='utf-8-sig').read()
    for b in re.split(r'^\s*GO\s*$', text, flags=re.M | re.I):
        if b.strip():
            yield b


def main():
    c = pyodbc.connect(SERVER, autocommit=True, timeout=15)
    if '--reset' in sys.argv and c.execute('SELECT DB_ID(?)', DB).fetchone()[0]:
        print('刪除資料庫', DB)
        c.execute(f'ALTER DATABASE [{DB}] SET SINGLE_USER WITH ROLLBACK IMMEDIATE')
        c.execute(f'DROP DATABASE [{DB}]')
    if not c.execute('SELECT DB_ID(?)', DB).fetchone()[0]:
        print('建立資料庫', DB)
        c.execute(f'CREATE DATABASE [{DB}] COLLATE Chinese_Taiwan_Stroke_CI_AS')
    elif '--reset' not in sys.argv:
        print(f'資料庫 {DB} 已存在；如需重建請加 --reset')
        return
    fails = 0
    for f in sorted(glob.glob(os.path.join(HERE, 'sql', '*.sql'))):
        print('執行', os.path.basename(f))
        for b in batches(f):
            try:
                cur = c.execute(b)
            except pyodbc.Error as e:
                print('  批次失敗：', b.strip()[:120].replace('\n', ' '))
                raise
            while True:
                if cur.description:
                    for row in cur.fetchall():
                        r = json.loads(row[0]) if isinstance(row[0], str) and row[0].startswith('{') else None
                        if r and not r.get('ok'):
                            fails += 1
                            print('  ✗', r.get('錯誤'))
                if not cur.nextset():
                    break
    print('完成' if not fails else f'完成，但有 {fails} 筆 API 呼叫失敗')


if __name__ == '__main__':
    main()
