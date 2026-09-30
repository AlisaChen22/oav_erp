"""極薄中介層：靜態檔 + 把 POST /api 的 JSON 原封不動交給 EXEC api.呼叫。
所有商業邏輯都在 SQL Server。
用法：python server.py [port]    （預設 8000）
"""
import os, sys, json
from http.server import ThreadingHTTPServer, SimpleHTTPRequestHandler
import pyodbc
import db_config

CONN = db_config.conn_str()
WEB = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'web')
pyodbc.pooling = True


class Handler(SimpleHTTPRequestHandler):
    extensions_map = {**SimpleHTTPRequestHandler.extensions_map,
                      '.webmanifest': 'application/manifest+json', '.js': 'text/javascript', '.svg': 'image/svg+xml'}

    def __init__(self, *a, **k):
        super().__init__(*a, directory=WEB, **k)

    def end_headers(self):
        self.send_header('Cache-Control', 'no-cache')
        super().end_headers()

    def do_POST(self):
        if self.path.rstrip('/') != '/api':
            return self.send_error(404)
        status = 200
        try:
            body = self.rfile.read(int(self.headers.get('Content-Length') or 0)).decode('utf-8')
        except UnicodeDecodeError:
            return self.reply(400, json.dumps({'ok': False, '錯誤': '請求必須是 UTF-8 JSON'}, ensure_ascii=False))
        for attempt in (1, 2):  # 連線池中的連線可能已失效（例如資料庫重建），重試一次
            try:
                conn = pyodbc.connect(CONN, autocommit=True, timeout=10)
                try:
                    cur = conn.execute('EXEC api.呼叫 @請求=?', body)
                    while cur.description is None and cur.nextset():
                        pass
                    out = cur.fetchone()[0]
                finally:
                    conn.close()
                status = 200
                break
            except Exception as e:  # 資料庫連不上 → 503，前端會保留在待上傳佇列稍後重送
                status = 503
                out = json.dumps({'ok': False, '錯誤': f'資料庫連線失敗：{e}'}, ensure_ascii=False)
        self.reply(status, out)

    def reply(self, status, out):
        data = out.encode('utf-8')
        self.send_response(status)
        self.send_header('Content-Type', 'application/json; charset=utf-8')
        self.send_header('Content-Length', str(len(data)))
        self.end_headers()
        self.wfile.write(data)


if __name__ == '__main__':
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8000
    print(f'OAV ERP  http://localhost:{port}')
    ThreadingHTTPServer(('0.0.0.0', port), Handler).serve_forever()
