# SQL Stock Market Analysis

| File | What it is |
|---|---|
| `stock_analysis_oracle.sql` | Oracle SQL for Tasks 1-13 plus the bonus-adjusted rerun. Run top to bottom (SQL Developer: Run Script). Re-runnable. |
| `00_load_data.sql` | INSERTs for the six tables (5,334 rows). Run after the CREATE TABLE section, before Part 1. |
| `SQL_Stock_Analysis_Insights.pdf` | Insights report (claim / evidence / caveat). |
| `streamlit_app/` | Streamlit app running the same SQL (SQLite engine) on the CSVs in `data/`. |

## Run the app
```
cd streamlit_app
pip install -r requirements.txt
streamlit run app.py
```

## Oracle notes
- `DATE` is a reserved word in Oracle, so the date column is `trade_date`.
- `EXEC drop_if_exists('x')` makes every table creation re-runnable (Oracle has no `DROP TABLE IF EXISTS` before 23c).
- Needs Oracle 12c+ for `FETCH FIRST n ROWS ONLY`.
- The Oracle script was not executed on an Oracle server in my environment; the identical logic was validated on SQLite against the guide's checkpoints (889 rows, first ma20 2415.53 on 2015-01-29, first Buy 2015-05-18, 56 Buys / 57 Sells total).
