"""資料庫連線設定：讀 config.local.json（不進 git），或環境變數 OAV_SERVER / OAV_DB / OAV_UID / OAV_PWD。"""
import json, os

_HERE = os.path.dirname(os.path.abspath(__file__))


def load():
    cfg = {'server': '', 'database': 'oav37', 'uid': '', 'pwd': '', 'driver': 'SQL Server'}
    path = os.path.join(_HERE, 'config.local.json')
    if os.path.exists(path):
        cfg.update(json.load(open(path, encoding='utf-8')))
    for k in cfg:
        cfg[k] = os.environ.get('OAV_' + k.upper(), cfg[k])
    if not cfg['server']:
        raise SystemExit('請先建立 config.local.json（參考 config.example.json）')
    return cfg


def conn_str(with_db=True):
    c = load()
    s = f"DRIVER={{{c['driver']}}};SERVER={c['server']};UID={c['uid']};PWD={c['pwd']}"
    return s + (f";DATABASE={c['database']}" if with_db else '')
