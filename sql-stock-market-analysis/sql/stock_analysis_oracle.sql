SET SERVEROUTPUT ON
SET DEFINE OFF

-- ===== SECTION 0: setup =====================================================
CREATE OR REPLACE PROCEDURE drop_if_exists(p_name VARCHAR2) AS
BEGIN
  EXECUTE IMMEDIATE 'DROP TABLE ' || p_name || ' PURGE';
EXCEPTION WHEN OTHERS THEN
  IF SQLCODE != -942 THEN RAISE; END IF;   -- ORA-00942: table does not exist
END;
/
EXEC drop_if_exists('bajaj_auto');
CREATE TABLE bajaj_auto (
  trade_date DATE PRIMARY KEY, open_price NUMBER(12,2), high_price NUMBER(12,2), low_price NUMBER(12,2),
  close_price NUMBER(12,2), wap NUMBER(16,4), no_of_shares NUMBER(14), no_of_trades NUMBER(12),
  total_turnover NUMBER(20,2), deliverable_qty NUMBER(14), pct_deli_qty NUMBER(6,2),
  spread_high_low NUMBER(12,2), spread_close_open NUMBER(12,2));
EXEC drop_if_exists('eicher_motors');
CREATE TABLE eicher_motors (
  trade_date DATE PRIMARY KEY, open_price NUMBER(12,2), high_price NUMBER(12,2), low_price NUMBER(12,2),
  close_price NUMBER(12,2), wap NUMBER(16,4), no_of_shares NUMBER(14), no_of_trades NUMBER(12),
  total_turnover NUMBER(20,2), deliverable_qty NUMBER(14), pct_deli_qty NUMBER(6,2),
  spread_high_low NUMBER(12,2), spread_close_open NUMBER(12,2));
EXEC drop_if_exists('hero_motocorp');
CREATE TABLE hero_motocorp (
  trade_date DATE PRIMARY KEY, open_price NUMBER(12,2), high_price NUMBER(12,2), low_price NUMBER(12,2),
  close_price NUMBER(12,2), wap NUMBER(16,4), no_of_shares NUMBER(14), no_of_trades NUMBER(12),
  total_turnover NUMBER(20,2), deliverable_qty NUMBER(14), pct_deli_qty NUMBER(6,2),
  spread_high_low NUMBER(12,2), spread_close_open NUMBER(12,2));
EXEC drop_if_exists('infosys');
CREATE TABLE infosys (
  trade_date DATE PRIMARY KEY, open_price NUMBER(12,2), high_price NUMBER(12,2), low_price NUMBER(12,2),
  close_price NUMBER(12,2), wap NUMBER(16,4), no_of_shares NUMBER(14), no_of_trades NUMBER(12),
  total_turnover NUMBER(20,2), deliverable_qty NUMBER(14), pct_deli_qty NUMBER(6,2),
  spread_high_low NUMBER(12,2), spread_close_open NUMBER(12,2));
EXEC drop_if_exists('tcs');
CREATE TABLE tcs (
  trade_date DATE PRIMARY KEY, open_price NUMBER(12,2), high_price NUMBER(12,2), low_price NUMBER(12,2),
  close_price NUMBER(12,2), wap NUMBER(16,4), no_of_shares NUMBER(14), no_of_trades NUMBER(12),
  total_turnover NUMBER(20,2), deliverable_qty NUMBER(14), pct_deli_qty NUMBER(6,2),
  spread_high_low NUMBER(12,2), spread_close_open NUMBER(12,2));
EXEC drop_if_exists('tvs_motors');
CREATE TABLE tvs_motors (
  trade_date DATE PRIMARY KEY, open_price NUMBER(12,2), high_price NUMBER(12,2), low_price NUMBER(12,2),
  close_price NUMBER(12,2), wap NUMBER(16,4), no_of_shares NUMBER(14), no_of_trades NUMBER(12),
  total_turnover NUMBER(20,2), deliverable_qty NUMBER(14), pct_deli_qty NUMBER(6,2),
  spread_high_low NUMBER(12,2), spread_close_open NUMBER(12,2));



-- ===== PART 1: get to know the data =========================================
-- Task 1: history available (889 days, 2015-01-01 to 2018-07-31)
SELECT COUNT(*) AS trading_days, MIN(trade_date) AS first_day, MAX(trade_date) AS last_day FROM bajaj_auto;

-- Task 2: Eicher's five best closes (all in one month - see insights PDF)
SELECT trade_date, close_price FROM eicher_motors ORDER BY close_price DESC FETCH FIRST 5 ROWS ONLY;

-- Task 3: TCS yearly average close (2018 has only 7 months)
SELECT EXTRACT(YEAR FROM trade_date) AS year, ROUND(AVG(close_price), 2) AS avg_close
FROM tcs GROUP BY EXTRACT(YEAR FROM trade_date) ORDER BY year;

-- Task 4: NULL holes in deliverable_qty (one row per stock, same date -> exchange reporting gap)
SELECT 'bajaj_auto' AS stock, trade_date FROM bajaj_auto WHERE deliverable_qty IS NULL
UNION ALL SELECT 'eicher_motors', trade_date FROM eicher_motors WHERE deliverable_qty IS NULL
UNION ALL SELECT 'hero_motocorp', trade_date FROM hero_motocorp WHERE deliverable_qty IS NULL
UNION ALL SELECT 'infosys',       trade_date FROM infosys       WHERE deliverable_qty IS NULL
UNION ALL SELECT 'tcs',           trade_date FROM tcs           WHERE deliverable_qty IS NULL
UNION ALL SELECT 'tvs_motors',    trade_date FROM tvs_motors    WHERE deliverable_qty IS NULL;

-- ===== PART 2: the assignment ===============================================
-- Task 5: bajaj1 = 20/50-day moving averages (NULL until a full window exists)
EXEC drop_if_exists('bajaj1');
CREATE TABLE bajaj1 AS
SELECT trade_date, close_price,
  CASE WHEN ROW_NUMBER() OVER (ORDER BY trade_date) >= 20
       THEN ROUND(AVG(close_price) OVER (ORDER BY trade_date ROWS BETWEEN 19 PRECEDING AND CURRENT ROW), 2) END AS ma20,
  CASE WHEN ROW_NUMBER() OVER (ORDER BY trade_date) >= 50
       THEN ROUND(AVG(close_price) OVER (ORDER BY trade_date ROWS BETWEEN 49 PRECEDING AND CURRENT ROW), 2) END AS ma50
FROM bajaj_auto;
-- check: first ma20 = 2415.53 on 2015-01-29; first ma50 = 2283.80 on 2015-03-13; ma20 on 2018-07-31 = 2918.51
SELECT * FROM bajaj1 ORDER BY trade_date;

-- Task 6: master_table (closing prices side by side)
EXEC drop_if_exists('master_table');
CREATE TABLE master_table AS
SELECT b.trade_date,
       b.close_price AS bajaj, t.close_price AS tcs, v.close_price AS tvs,
       i.close_price AS infosys, e.close_price AS eicher, h.close_price AS hero
FROM bajaj_auto b
JOIN tcs t           ON t.trade_date = b.trade_date
JOIN tvs_motors v    ON v.trade_date = b.trade_date
JOIN infosys i       ON i.trade_date = b.trade_date
JOIN eicher_motors e ON e.trade_date = b.trade_date
JOIN hero_motocorp h ON h.trade_date = b.trade_date;

-- Task 7: bajaj2 = Buy / Sell / Hold golden-cross signals
EXEC drop_if_exists('bajaj2');
CREATE TABLE bajaj2 AS
WITH t AS (
  SELECT trade_date, close_price, ma20, ma50,
         LAG(ma20) OVER (ORDER BY trade_date) AS prev_ma20,
         LAG(ma50) OVER (ORDER BY trade_date) AS prev_ma50
  FROM bajaj1
)
SELECT trade_date, close_price,
  CASE WHEN ma20 IS NULL OR ma50 IS NULL OR prev_ma20 IS NULL OR prev_ma50 IS NULL THEN 'Hold'
       WHEN ma20 > ma50 AND prev_ma20 <= prev_ma50 THEN 'Buy'
       WHEN ma20 < ma50 AND prev_ma20 >= prev_ma50 THEN 'Sell'
       ELSE 'Hold' END AS signal
FROM t;

-- Task 8: signal counts (Bajaj: 12 Buy, 11 Sell, 866 Hold)
SELECT signal, COUNT(*) AS days FROM bajaj2 GROUP BY signal ORDER BY signal;

-- Task 9: signal on a given day, as a function
CREATE OR REPLACE FUNCTION bajaj_signal(p_date DATE) RETURN VARCHAR2 IS
  v_signal VARCHAR2(4);
BEGIN
  SELECT signal INTO v_signal FROM bajaj2 WHERE trade_date = p_date;
  RETURN v_signal;
EXCEPTION WHEN NO_DATA_FOUND THEN RETURN NULL;   -- market closed that day
END;
/
SELECT bajaj_signal(DATE '2018-06-21') AS signal_2018_06_21, bajaj_signal(DATE '2015-05-18') AS check_buy FROM dual;

-- Task 10: all six stocks in one query (unrounded averages; every window PARTITIONed by stock)
WITH prices AS (
  SELECT 'Bajaj Auto' AS stock, trade_date, close_price FROM bajaj_auto
  UNION ALL SELECT 'Eicher Motors', trade_date, close_price FROM eicher_motors
  UNION ALL SELECT 'Hero Motocorp', trade_date, close_price FROM hero_motocorp
  UNION ALL SELECT 'Infosys',       trade_date, close_price FROM infosys
  UNION ALL SELECT 'TCS',           trade_date, close_price FROM tcs
  UNION ALL SELECT 'TVS Motors',    trade_date, close_price FROM tvs_motors
),
ma AS (
  SELECT stock, trade_date, close_price,
    CASE WHEN ROW_NUMBER() OVER (PARTITION BY stock ORDER BY trade_date) >= 20
         THEN AVG(close_price) OVER (PARTITION BY stock ORDER BY trade_date ROWS BETWEEN 19 PRECEDING AND CURRENT ROW) END AS ma20,
    CASE WHEN ROW_NUMBER() OVER (PARTITION BY stock ORDER BY trade_date) >= 50
         THEN AVG(close_price) OVER (PARTITION BY stock ORDER BY trade_date ROWS BETWEEN 49 PRECEDING AND CURRENT ROW) END AS ma50
  FROM prices
),
lagged AS (
  SELECT ma.*,
    LAG(ma20) OVER (PARTITION BY stock ORDER BY trade_date) AS prev_ma20,
    LAG(ma50) OVER (PARTITION BY stock ORDER BY trade_date) AS prev_ma50
  FROM ma
),
sig AS (
  SELECT stock, trade_date, close_price,
    CASE WHEN ma20 IS NULL OR ma50 IS NULL OR prev_ma20 IS NULL OR prev_ma50 IS NULL THEN 'Hold'
         WHEN ma20 > ma50 AND prev_ma20 <= prev_ma50 THEN 'Buy'
         WHEN ma20 < ma50 AND prev_ma20 >= prev_ma50 THEN 'Sell'
         ELSE 'Hold' END AS signal
  FROM lagged
),
latest AS (
  SELECT stock, trade_date, signal,
         ROW_NUMBER() OVER (PARTITION BY stock ORDER BY trade_date DESC) AS rn
  FROM sig WHERE signal <> 'Hold'
)
SELECT s.stock,
       SUM(CASE WHEN s.signal = 'Buy'  THEN 1 ELSE 0 END) AS buys,
       SUM(CASE WHEN s.signal = 'Sell' THEN 1 ELSE 0 END) AS sells,
       MAX(l.trade_date) AS last_signal_date,
       MAX(l.signal)     AS last_signal
FROM sig s JOIN latest l ON l.stock = s.stock AND l.rn = 1
GROUP BY s.stock
ORDER BY s.stock;
-- check: 56 Buys and 57 Sells in total

-- ===== PART 3: question the result ==========================================
-- Task 11: who went up? (raw prices)
WITH prices AS (
  SELECT 'Bajaj Auto' AS stock, trade_date, close_price FROM bajaj_auto
  UNION ALL SELECT 'Eicher Motors', trade_date, close_price FROM eicher_motors
  UNION ALL SELECT 'Hero Motocorp', trade_date, close_price FROM hero_motocorp
  UNION ALL SELECT 'Infosys',       trade_date, close_price FROM infosys
  UNION ALL SELECT 'TCS',           trade_date, close_price FROM tcs
  UNION ALL SELECT 'TVS Motors',    trade_date, close_price FROM tvs_motors
),
ends AS (SELECT stock, MIN(trade_date) AS first_day, MAX(trade_date) AS last_day FROM prices GROUP BY stock)
SELECT e.stock, pf.close_price AS first_close, pl.close_price AS last_close,
       ROUND(100 * (pl.close_price - pf.close_price) / pf.close_price, 1) AS pct_change
FROM ends e
JOIN prices pf ON pf.stock = e.stock AND pf.trade_date = e.first_day
JOIN prices pl ON pl.stock = e.stock AND pl.trade_date = e.last_day
ORDER BY pct_change DESC;

-- Task 12: the data trap - each stock's worst single day
WITH prices AS (
  SELECT 'Bajaj Auto' AS stock, trade_date, close_price FROM bajaj_auto
  UNION ALL SELECT 'Eicher Motors', trade_date, close_price FROM eicher_motors
  UNION ALL SELECT 'Hero Motocorp', trade_date, close_price FROM hero_motocorp
  UNION ALL SELECT 'Infosys',       trade_date, close_price FROM infosys
  UNION ALL SELECT 'TCS',           trade_date, close_price FROM tcs
  UNION ALL SELECT 'TVS Motors',    trade_date, close_price FROM tvs_motors
),
moves AS (
  SELECT stock, trade_date, close_price,
         100 * (close_price / LAG(close_price) OVER (PARTITION BY stock ORDER BY trade_date) - 1) AS pct_move
  FROM prices
),
ranked AS (
  SELECT m.*, ROW_NUMBER() OVER (PARTITION BY stock ORDER BY pct_move) AS rn
  FROM moves m WHERE pct_move IS NOT NULL
)
SELECT stock, trade_date, close_price, ROUND(pct_move, 1) AS pct_move
FROM ranked WHERE rn = 1 ORDER BY pct_move;
-- TCS 2018-05-31 (-50.4%) and Infosys 2015-06-15 (-49.9%) are 1:1 BONUS ISSUES, not real losses.

-- Task 13: fix it - adjust pre-event prices by the factor 2
WITH prices AS (
  SELECT 'Bajaj Auto' AS stock, trade_date, close_price FROM bajaj_auto
  UNION ALL SELECT 'Eicher Motors', trade_date, close_price FROM eicher_motors
  UNION ALL SELECT 'Hero Motocorp', trade_date, close_price FROM hero_motocorp
  UNION ALL SELECT 'Infosys', trade_date,
         CASE WHEN trade_date < DATE '2015-06-15' THEN close_price / 2 ELSE close_price END FROM infosys   -- 1:1 bonus
  UNION ALL SELECT 'TCS', trade_date,
         CASE WHEN trade_date < DATE '2018-05-31' THEN close_price / 2 ELSE close_price END FROM tcs       -- 1:1 bonus
  UNION ALL SELECT 'TVS Motors', trade_date, close_price FROM tvs_motors
),
ends AS (SELECT stock, MIN(trade_date) AS first_day, MAX(trade_date) AS last_day FROM prices GROUP BY stock)
SELECT p.stock,
       ROUND(100 * (MAX(CASE WHEN p.trade_date = e.last_day  THEN p.close_price END) /
                    MAX(CASE WHEN p.trade_date = e.first_day THEN p.close_price END) - 1), 1) AS adjusted_pct_change
FROM prices p JOIN ends e ON e.stock = p.stock
WHERE p.trade_date BETWEEN DATE '2015-01-01' AND DATE '2018-07-31'
GROUP BY p.stock ORDER BY p.stock;
-- check: TCS +52.4, Infosys +38.2 (others unchanged)

-- Stretch: signals rebuilt on ADJUSTED prices (TCS loses its false Sell on 2018-06-05; Infosys gains 1 Buy/Sell pair)
WITH prices AS (
  SELECT 'Bajaj Auto' AS stock, trade_date, close_price FROM bajaj_auto
  UNION ALL SELECT 'Eicher Motors', trade_date, close_price FROM eicher_motors
  UNION ALL SELECT 'Hero Motocorp', trade_date, close_price FROM hero_motocorp
  UNION ALL SELECT 'Infosys', trade_date,
         CASE WHEN trade_date < DATE '2015-06-15' THEN close_price / 2 ELSE close_price END FROM infosys   -- 1:1 bonus
  UNION ALL SELECT 'TCS', trade_date,
         CASE WHEN trade_date < DATE '2018-05-31' THEN close_price / 2 ELSE close_price END FROM tcs       -- 1:1 bonus
  UNION ALL SELECT 'TVS Motors', trade_date, close_price FROM tvs_motors
),
ma AS (
  SELECT stock, trade_date, close_price,
    CASE WHEN ROW_NUMBER() OVER (PARTITION BY stock ORDER BY trade_date) >= 20
         THEN AVG(close_price) OVER (PARTITION BY stock ORDER BY trade_date ROWS BETWEEN 19 PRECEDING AND CURRENT ROW) END AS ma20,
    CASE WHEN ROW_NUMBER() OVER (PARTITION BY stock ORDER BY trade_date) >= 50
         THEN AVG(close_price) OVER (PARTITION BY stock ORDER BY trade_date ROWS BETWEEN 49 PRECEDING AND CURRENT ROW) END AS ma50
  FROM prices
),
lagged AS (
  SELECT ma.*,
    LAG(ma20) OVER (PARTITION BY stock ORDER BY trade_date) AS prev_ma20,
    LAG(ma50) OVER (PARTITION BY stock ORDER BY trade_date) AS prev_ma50
  FROM ma
),
sig AS (
  SELECT stock, trade_date, close_price,
    CASE WHEN ma20 IS NULL OR ma50 IS NULL OR prev_ma20 IS NULL OR prev_ma50 IS NULL THEN 'Hold'
         WHEN ma20 > ma50 AND prev_ma20 <= prev_ma50 THEN 'Buy'
         WHEN ma20 < ma50 AND prev_ma20 >= prev_ma50 THEN 'Sell'
         ELSE 'Hold' END AS signal
  FROM lagged
),
latest AS (
  SELECT stock, trade_date, signal,
         ROW_NUMBER() OVER (PARTITION BY stock ORDER BY trade_date DESC) AS rn
  FROM sig WHERE signal <> 'Hold'
)
SELECT s.stock,
       SUM(CASE WHEN s.signal = 'Buy'  THEN 1 ELSE 0 END) AS buys,
       SUM(CASE WHEN s.signal = 'Sell' THEN 1 ELSE 0 END) AS sells,
       MAX(l.trade_date) AS last_signal_date,
       MAX(l.signal)     AS last_signal
FROM sig s JOIN latest l ON l.stock = s.stock AND l.rn = 1
GROUP BY s.stock
ORDER BY s.stock;

-- Final report table: per stock - return, signals, latest trend (adjusted prices)
WITH prices AS (
  SELECT 'Bajaj Auto' AS stock, trade_date, close_price FROM bajaj_auto
  UNION ALL SELECT 'Eicher Motors', trade_date, close_price FROM eicher_motors
  UNION ALL SELECT 'Hero Motocorp', trade_date, close_price FROM hero_motocorp
  UNION ALL SELECT 'Infosys', trade_date,
         CASE WHEN trade_date < DATE '2015-06-15' THEN close_price / 2 ELSE close_price END FROM infosys   -- 1:1 bonus
  UNION ALL SELECT 'TCS', trade_date,
         CASE WHEN trade_date < DATE '2018-05-31' THEN close_price / 2 ELSE close_price END FROM tcs       -- 1:1 bonus
  UNION ALL SELECT 'TVS Motors', trade_date, close_price FROM tvs_motors
),
ends AS (SELECT stock, MIN(trade_date) AS first_day, MAX(trade_date) AS last_day FROM prices GROUP BY stock),
ret AS (
  SELECT p.stock,
    ROUND(100 * (MAX(CASE WHEN p.trade_date = e.last_day  THEN p.close_price END) /
                 MAX(CASE WHEN p.trade_date = e.first_day THEN p.close_price END) - 1), 1) AS adj_pct_change
  FROM prices p JOIN ends e ON e.stock = p.stock GROUP BY p.stock
)
SELECT stock, adj_pct_change FROM ret ORDER BY adj_pct_change DESC;
