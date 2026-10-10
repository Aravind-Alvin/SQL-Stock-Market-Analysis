"""All SQL used by the app (SQLite dialect; same logic as the Oracle file)."""
import io, json, zlib, base64, sqlite3, pandas as pd
from pathlib import Path

FILES = {"Bajaj Auto": "Bajaj_Auto", "Eicher Motors": "Eicher_Motors", "Hero Motocorp": "Hero_Motocorp",
         "Infosys": "Infosys", "TCS": "TCS", "TVS Motors": "TVS_Motors"}
TABLES = {k: k.lower().replace(" ", "_") for k in FILES}
TABLES["Bajaj Auto"] = "bajaj_auto"
EVENTS = {"TCS": "2018-05-31", "Infosys": "2015-06-15"}   # 1:1 bonus issues (factor 2)
COLS = ["trade_date", "open_price", "high_price", "low_price", "close_price", "wap", "no_of_shares",
        "no_of_trades", "total_turnover", "deliverable_qty", "pct_deli_qty", "spread_high_low", "spread_close_open"]

def _embedded():
    """CSV text for each stock from stock_data.py (fallback when the data/ folder is not in the repo)."""
    try:
        import stock_data
        return json.loads(zlib.decompress(base64.b64decode(stock_data.DATA)).decode())
    except Exception:
        return {}

def _find_csv(stem, search_dirs):
    """Find <stem>.csv (case-insensitive, also matching e.g. 'tcs' for 'TCS') in the given dirs, then anywhere in the repo."""
    want = stem.lower() + ".csv"
    for d in search_dirs:
        if d.is_dir():
            for p in d.iterdir():
                if p.is_file() and p.name.lower() == want:
                    return p
    here = Path(__file__).resolve().parent
    for root in (here, here.parent, Path.cwd()):
        for p in root.rglob("*.csv"):
            if p.name.lower() == want:
                return p
    return None

def build_db(data_dir=None):
    here = Path(__file__).resolve().parent
    dirs = [Path(data_dir)] if data_dir else []
    dirs += [here / "data", here, here.parent / "data", here.parent, Path.cwd() / "data", Path.cwd()]
    con = sqlite3.connect(":memory:", check_same_thread=False)
    missing = []
    for stock, f in FILES.items():
        p = _find_csv(f, dirs)
        if p is not None:
            df = pd.read_csv(p)
        else:
            emb = _embedded().get(f)
            if emb is None:
                missing.append(f"{f}.csv"); continue
            df = pd.read_csv(io.StringIO(emb))
        df.columns = COLS
        df["trade_date"] = pd.to_datetime(df["trade_date"], format="%d-%B-%Y").dt.strftime("%Y-%m-%d")
        df.sort_values("trade_date").to_sql(TABLES[stock], con, index=False)
    if missing:
        raise FileNotFoundError("CSV file(s) not found in the repository: " + ", ".join(missing) +
                                ". Put them in streamlit_app/data/ and push to GitHub.")
    return con

def prices_cte(adjusted=False):
    def px(stock):
        t, ev = TABLES[stock], EVENTS.get(stock)
        c = f"CASE WHEN trade_date < '{ev}' THEN close_price / 2.0 ELSE close_price END" if adjusted and ev else "close_price"
        return f"SELECT '{stock}' AS stock, trade_date, {c} AS close_price FROM {t}"
    return "prices AS (\n  " + "\n  UNION ALL ".join(px(s) for s in FILES) + "\n)"

def signals_cte(adjusted=False):
    return f"""WITH {prices_cte(adjusted)},
ma AS (
  SELECT stock, trade_date, close_price,
    CASE WHEN ROW_NUMBER() OVER (PARTITION BY stock ORDER BY trade_date) >= 20
         THEN AVG(close_price) OVER (PARTITION BY stock ORDER BY trade_date ROWS BETWEEN 19 PRECEDING AND CURRENT ROW) END AS ma20,
    CASE WHEN ROW_NUMBER() OVER (PARTITION BY stock ORDER BY trade_date) >= 50
         THEN AVG(close_price) OVER (PARTITION BY stock ORDER BY trade_date ROWS BETWEEN 49 PRECEDING AND CURRENT ROW) END AS ma50
  FROM prices
),
lagged AS (
  SELECT ma.*, LAG(ma20) OVER (PARTITION BY stock ORDER BY trade_date) AS prev_ma20,
               LAG(ma50) OVER (PARTITION BY stock ORDER BY trade_date) AS prev_ma50
  FROM ma
),
sig AS (
  SELECT stock, trade_date, close_price, ma20, ma50,
    CASE WHEN ma20 IS NULL OR ma50 IS NULL OR prev_ma20 IS NULL OR prev_ma50 IS NULL THEN 'Hold'
         WHEN ma20 > ma50 AND prev_ma20 <= prev_ma50 THEN 'Buy'
         WHEN ma20 < ma50 AND prev_ma20 >= prev_ma50 THEN 'Sell'
         ELSE 'Hold' END AS signal
  FROM lagged
)"""

def q_signal_rows(stock, adjusted=False):
    return signals_cte(adjusted) + f"\nSELECT trade_date, close_price, ma20, ma50, signal FROM sig WHERE stock = '{stock}' ORDER BY trade_date"

def q_summary(adjusted=False):
    return signals_cte(adjusted) + """,
latest AS (SELECT stock, trade_date, signal, ROW_NUMBER() OVER (PARTITION BY stock ORDER BY trade_date DESC) AS rn
           FROM sig WHERE signal <> 'Hold'),
ends AS (SELECT stock, MIN(trade_date) AS f, MAX(trade_date) AS l FROM prices GROUP BY stock),
ret AS (SELECT e.stock, ROUND(100.0 * (pl.close_price - pf.close_price) / pf.close_price, 1) AS pct_change
        FROM ends e JOIN prices pf ON pf.stock = e.stock AND pf.trade_date = e.f
                    JOIN prices pl ON pl.stock = e.stock AND pl.trade_date = e.l)
SELECT s.stock, SUM(s.signal = 'Buy') AS buys, SUM(s.signal = 'Sell') AS sells,
       MAX(l.trade_date) AS last_signal_date, MAX(l.signal) AS last_signal, MAX(r.pct_change) AS pct_change
FROM sig s JOIN latest l ON l.stock = s.stock AND l.rn = 1 JOIN ret r ON r.stock = s.stock
GROUP BY s.stock ORDER BY s.stock"""

def q_worst_days():
    return f"""WITH {prices_cte(False)},
moves AS (SELECT stock, trade_date, close_price,
          100.0 * (close_price / LAG(close_price) OVER (PARTITION BY stock ORDER BY trade_date) - 1) AS pct_move FROM prices),
ranked AS (SELECT *, ROW_NUMBER() OVER (PARTITION BY stock ORDER BY pct_move) AS rn FROM moves WHERE pct_move IS NOT NULL)
SELECT stock, trade_date, close_price, ROUND(pct_move, 1) AS pct_move FROM ranked WHERE rn = 1 ORDER BY pct_move"""

def q_trades(adjusted=False):
    """Closed Buy->Sell round trips (buy at Buy close, sell at the next Sell close)."""
    return signals_cte(adjusted) + """,
x AS (SELECT stock, trade_date, close_price, signal,
        LEAD(signal) OVER (PARTITION BY stock ORDER BY trade_date) AS nxt,
        LEAD(trade_date) OVER (PARTITION BY stock ORDER BY trade_date) AS nxt_date,
        LEAD(close_price) OVER (PARTITION BY stock ORDER BY trade_date) AS nxt_close
      FROM sig WHERE signal <> 'Hold')
SELECT stock, trade_date AS buy_date, nxt_date AS sell_date, close_price AS buy_close, nxt_close AS sell_close,
       ROUND(100.0 * (nxt_close / close_price - 1), 1) AS return_pct,
       CAST(julianday(nxt_date) - julianday(trade_date) AS INTEGER) AS days_held
FROM x WHERE signal = 'Buy' AND nxt = 'Sell' ORDER BY stock, trade_date"""
