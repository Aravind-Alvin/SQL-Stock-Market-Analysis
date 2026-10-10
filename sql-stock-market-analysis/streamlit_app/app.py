import pandas as pd, streamlit as st
import matplotlib.pyplot as plt
import queries as Q

st.set_page_config(page_title="SQL Stock Market Analysis", page_icon="📈", layout="wide")

@st.cache_resource
def get_db():
    return Q.build_db()

con = get_db()
def run(sql): return pd.read_sql(sql, con)

st.sidebar.title("📈 SQL Stock Analysis")
page = st.sidebar.radio("Page", ["Summary", "Stock explorer", "The data trap", "Round-trip trades", "SQL playground"])
adjusted = st.sidebar.toggle("Use bonus-adjusted prices (TCS, Infosys)", value=True,
                             help="TCS 1:1 bonus on 2018-05-31 and Infosys 1:1 bonus on 2015-06-15: earlier prices are divided by 2.")
st.sidebar.caption("Six NSE stocks, 2015-01-01 to 2018-07-31 · 889 trading days each · 20/50-day golden-cross signals")

def show_sql(sql, label="Show the SQL"):
    with st.expander(label): st.code(sql, language="sql")

if page == "Summary":
    st.title("Signals, returns and latest trend")
    sql = Q.q_summary(adjusted); df = run(sql)
    df["trend_now"] = df.last_signal.map({"Buy": "⬆ shifting up", "Sell": "⬇ shifting down"})
    df = df.rename(columns={"pct_change": "change_%", "last_signal_date": "last_signal_on"})
    c = st.columns(3)
    best = df.sort_values("change_%").iloc[-1]; worst = df.sort_values("change_%").iloc[0]
    c[0].metric("Best performer", best.stock, f"{best['change_%']:+.1f}%")
    c[1].metric("Weakest performer", worst.stock, f"{worst['change_%']:+.1f}%")
    c[2].metric("Total Buy / Sell signals", f"{int(df.buys.sum())} / {int(df.sells.sum())}")
    st.dataframe(df[["stock", "buys", "sells", "last_signal_on", "last_signal", "trend_now", "change_%"]],
                 use_container_width=True, hide_index=True)
    st.caption("Prices: " + ("bonus-adjusted (TCS, Infosys)." if adjusted else "RAW - TCS and Infosys are distorted by bonus issues."))
    show_sql(sql)
    st.subheader("Rebased closing prices (first day = 100)")
    px = run(f"WITH {Q.prices_cte(adjusted)} SELECT * FROM prices")
    px["rebased"] = px.groupby("stock").close_price.transform(lambda s: 100 * s / s.iloc[0])
    st.line_chart(px.pivot(index="trade_date", columns="stock", values="rebased"))

elif page == "Stock explorer":
    stock = st.selectbox("Stock", list(Q.FILES))
    sql = Q.q_signal_rows(stock, adjusted); df = run(sql); df["trade_date"] = pd.to_datetime(df.trade_date)
    fig, ax = plt.subplots(figsize=(11, 4.5))
    ax.plot(df.trade_date, df.close_price, color="#9aa5b1", lw=1, label="Close")
    ax.plot(df.trade_date, df.ma20, color="#1f77b4", lw=1.4, label="20-day MA")
    ax.plot(df.trade_date, df.ma50, color="#ff7f0e", lw=1.4, label="50-day MA")
    b, s = df[df.signal == "Buy"], df[df.signal == "Sell"]
    ax.scatter(b.trade_date, b.close_price, marker="^", color="green", s=70, zorder=5, label=f"Buy ({len(b)})")
    ax.scatter(s.trade_date, s.close_price, marker="v", color="red", s=70, zorder=5, label=f"Sell ({len(s)})")
    ax.set_ylabel("₹"); ax.legend(ncol=5, loc="upper center", bbox_to_anchor=(0.5, 1.12), frameon=False)
    ax.spines[["top", "right"]].set_visible(False)
    st.pyplot(fig)
    st.subheader("Signal days")
    st.dataframe(df[df.signal != "Hold"].assign(trade_date=lambda d: d.trade_date.dt.date), use_container_width=True, hide_index=True)
    show_sql(sql)

elif page == "The data trap":
    st.title("Each stock's single worst day")
    sql = Q.q_worst_days(); df = run(sql); st.dataframe(df, use_container_width=True, hide_index=True)
    st.warning("TCS (2018-05-31) and Infosys (2015-06-15) fall about 50% in one day. These are **1:1 bonus issues**: "
               "share count doubles, price halves, no value is lost. Raw prices make TCS look like a loser, "
               "create a false Sell for TCS on 2018-06-05, and turn Infosys's return from +38.2% into -30.9%.")
    show_sql(sql)
    stock = st.selectbox("See the cliff and the fix", ["TCS", "Infosys"])
    raw = run(f"WITH {Q.prices_cte(False)} SELECT trade_date, close_price AS raw FROM prices WHERE stock='{stock}'").set_index("trade_date")
    adj = run(f"WITH {Q.prices_cte(True)} SELECT trade_date, close_price AS adjusted FROM prices WHERE stock='{stock}'").set_index("trade_date")
    st.line_chart(raw.join(adj))
    st.subheader("Signals: raw vs adjusted")
    a, b = run(Q.q_summary(False)), run(Q.q_summary(True))
    m = a.merge(b, on="stock", suffixes=("_raw", "_adj"))
    st.dataframe(m[["stock", "buys_raw", "sells_raw", "last_signal_date_raw", "pct_change_raw",
                    "buys_adj", "sells_adj", "last_signal_date_adj", "pct_change_adj"]], use_container_width=True, hide_index=True)

elif page == "Round-trip trades":
    st.title("What would following the signals have returned?")
    st.caption("Buy at the close on a Buy day, sell at the close of the next Sell day. No brokerage, taxes or dividends. A final unclosed Buy is excluded.")
    sql = Q.q_trades(adjusted); t = run(sql)
    agg = t.groupby("stock").agg(trades=("return_pct", "size"), win_rate_pct=("return_pct", lambda s: round(100 * (s > 0).mean())),
                                 avg_return_pct=("return_pct", "mean"), short_trades_le_30d=("days_held", lambda s: int((s <= 30).sum()))).round(1)
    st.dataframe(agg.reset_index(), use_container_width=True, hide_index=True)
    stock = st.selectbox("Trade list", list(Q.FILES))
    st.dataframe(t[t.stock == stock].drop(columns="stock"), use_container_width=True, hide_index=True)
    show_sql(sql)

else:
    st.title("SQL playground")
    st.caption("Tables: " + ", ".join(Q.TABLES.values()) + " · columns: " + ", ".join(Q.COLS) + " (SQLite dialect, read-only queries)")
    default = "SELECT trade_date, close_price FROM eicher_motors ORDER BY close_price DESC LIMIT 5"
    sql = st.text_area("Query", default, height=140)
    if st.button("Run"):
        if not sql.strip().lower().startswith(("select", "with")):
            st.error("Only SELECT / WITH queries are allowed.")
        else:
            try: st.dataframe(run(sql), use_container_width=True)
            except Exception as e: st.error(str(e))
