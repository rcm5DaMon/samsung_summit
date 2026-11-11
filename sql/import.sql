-- Samsung Summit (November) - single import query (Power BI "import mode" style)
-- Returns ONE row with ONE column `j` (compact JSON). Rows inside are "|"-delimited strings.
-- Summit has two targets per store:
--   Summit Device : master_data.target_summit_november.target_qty   = all SAMSUNG Device qty
--   A Series      : master_data.target_aseries_samsung.target_Aseries = SAMSUNG Device, Detail_Cat = 'A SERIES' qty
--   Racing        : master_data.target_racing_samsung, 5 tiers per store = SAMSUNG Device, Detail_Cat in S SERIES / Z SERIES qty
-- Store list = every store in the three target files (site codes are TRIMmed: the Racing file has ' F285'). Store attributes come from sales_b2c.master_store_r5.
-- Edit the period here (the target month/year is taken from the start date):
WITH p AS (SELECT DATE '2026-11-01' AS s, DATE '2026-11-30' AS e),

t_sum AS (
  SELECT TRIM(site_code) AS site, SUM(target_qty) AS td
  FROM `e-smart-433113.master_data.target_summit_november`, p
  WHERE year = EXTRACT(YEAR FROM p.s) AND month = EXTRACT(MONTH FROM p.s)
  GROUP BY 1
),
t_a AS (
  SELECT TRIM(site_code) AS site, SUM(target_Aseries) AS ta
  FROM `e-smart-433113.master_data.target_aseries_samsung`, p
  WHERE year = EXTRACT(YEAR FROM p.s) AND month = EXTRACT(MONTH FROM p.s)
  GROUP BY 1
),
t_r AS (
  SELECT TRIM(site_code) AS site,
         SUM(IF(tier = 1, target, 0)) AS r1, SUM(IF(tier = 2, target, 0)) AS r2, SUM(IF(tier = 3, target, 0)) AS r3,
         SUM(IF(tier = 4, target, 0)) AS r4, SUM(IF(tier = 5, target, 0)) AS r5
  FROM `e-smart-433113.master_data.target_racing_samsung`, p
  WHERE year = EXTRACT(YEAR FROM p.s) AND month = EXTRACT(MONTH FROM p.s)
  GROUP BY 1
),
tgt AS (
  SELECT site, IFNULL(td, 0) AS td, IFNULL(ta, 0) AS ta,
         -- in-file flags: 1 = store is in that target file (a store can be in Racing only, or have 0 targets)
         IF(t_sum.site IS NULL, 0, 1) AS in_s, IF(t_a.site IS NULL, 0, 1) AS in_a, IF(t_r.site IS NULL, 0, 1) AS in_r,
         IFNULL(r1, 0) AS r1, IFNULL(r2, 0) AS r2, IFNULL(r3, 0) AS r3, IFNULL(r4, 0) AS r4, IFNULL(r5, 0) AS r5
  FROM t_sum FULL JOIN t_a USING (site) FULL JOIN t_r USING (site)
),
ms AS (
  SELECT TRIM(site_code) AS site, Store_Name AS name, BU_CATEGORY AS bu, LOB AS lob, TSH AS tsh, CHANNEL AS ch
  FROM `e-smart-433113.sales_b2c.master_store_r5`
),

-- Samsung Device rows only (sales in the period + every stock snapshot)
svs AS (
  SELECT line, order_date AS d, TRIM(site_code) AS site,
         IFNULL(NULLIF(Model_Type, ''), 'OTHER') AS model,
         -- variant = Model_Type_Detail + ' ' + Model_Category, e.g. 'A57 5G 8/256 GB'
         TRIM(CONCAT(IFNULL(Model_Type_Detail, ''), ' ', IFNULL(Model_Category, ''))) AS variant,
         CASE Detail_Cat WHEN 'A SERIES' THEN 'A' WHEN 'S SERIES' THEN 'S' WHEN 'Z SERIES' THEN 'Z'
                         WHEN 'TABLET' THEN 'T' ELSE 'X' END AS cat,
         SUM_quantity AS q, SUM_month_est_quantity AS est
  FROM `e-smart-433113.region_data.sales_vs_stock`, p
  WHERE brandname = 'SAMSUNG' AND Product_Category = 'Device'
    AND ((line = 'sales' AND order_date BETWEEN p.s AND p.e) OR line IN ('stock', 'stock_dc'))
),
-- last completed sales day = latest sales date in the whole table (any brand)
asof AS (
  SELECT MAX(order_date) AS sales_asof FROM `e-smart-433113.region_data.sales_vs_stock` WHERE line = 'sales'
),
stk_date AS (SELECT MAX(d) AS stock_date FROM svs WHERE line = 'stock'),

sales AS (
  SELECT d, site, cat, model, variant, SUM(q) AS q, SUM(est) AS est
  FROM svs WHERE line = 'sales' AND site IN (SELECT site FROM tgt)
  GROUP BY ALL
),
-- daily units per store: all Samsung Device, and A Series
daily AS (
  SELECT d, site, SUM(q) AS q_all, SUM(IF(cat = 'A', q, 0)) AS q_a, SUM(IF(cat IN ('S', 'Z'), q, 0)) AS q_r
  FROM sales GROUP BY d, site
),
-- month estimate per store = SUM(SUM_month_est_quantity) from sales_vs_stock
est AS (
  SELECT site, SUM(est) AS e_all, SUM(IF(cat = 'A', est, 0)) AS e_a, SUM(IF(cat IN ('S', 'Z'), est, 0)) AS e_r
  FROM sales GROUP BY site
),
stk AS (
  SELECT * FROM (
    SELECT line, site, cat, model, variant, SUM(q) AS q
    FROM svs, stk_date
    WHERE line IN ('stock', 'stock_dc') AND d = stk_date.stock_date
      AND (line = 'stock_dc' OR site IN (SELECT site FROM tgt))
    GROUP BY ALL)
  WHERE q <> 0
),
dcs AS (
  SELECT DISTINCT s.site, IFNULL(m.name, s.site) AS name, IFNULL(m.bu, '') AS bu
  FROM stk s LEFT JOIN ms m USING (site) WHERE s.line = 'stock_dc'
),

-- today intraday POS (PAID). Only used when its date is after the last completed day in sales_vs_stock.
sd AS (
  SELECT PARSE_DATE('%Y/%m/%d', `Date`) AS d, TRIM(`Site Code`) AS site, brandname, product_category,
         detail_cat, model_type, model_type_detail, model_category, Quantity AS q, `Time` AS tm, `Order Number` AS ord
  FROM `e-smart-433113.region_data.sales_daily`
  WHERE `Order Status` = 'PAID'
),
sd_meta AS (SELECT d AS sd_date, MAX(tm) AS sd_last_time FROM sd GROUP BY d ORDER BY d DESC LIMIT 1),
today_meta AS (
  SELECT IF(m.sd_date > a.sales_asof AND m.sd_date BETWEEN p.s AND p.e, m.sd_date, NULL) AS today_date,
         IF(m.sd_date > a.sales_asof AND m.sd_date BETWEEN p.s AND p.e, m.sd_last_time, NULL) AS today_last_time
  FROM sd_meta m, asof a, p
),
today AS (
  SELECT sd.site,
         CASE sd.detail_cat WHEN 'A SERIES' THEN 'A' WHEN 'S SERIES' THEN 'S' WHEN 'Z SERIES' THEN 'Z'
                            WHEN 'TABLET' THEN 'T' ELSE 'X' END AS cat,
         IFNULL(NULLIF(sd.model_type, ''), 'OTHER') AS model,
         TRIM(CONCAT(IFNULL(sd.model_type_detail, ''), ' ', IFNULL(sd.model_category, ''))) AS variant, SUM(sd.q) AS units
  FROM sd, today_meta tm
  WHERE sd.d = tm.today_date AND sd.brandname = 'SAMSUNG' AND sd.product_category = 'Device'
    AND sd.site IN (SELECT site FROM tgt)
  GROUP BY ALL
  HAVING units <> 0
),
-- any PAID transaction today (all brands, all products) per target store
today_any AS (
  SELECT sd.site, COUNT(DISTINCT sd.ord) AS orders
  FROM sd, today_meta tm
  WHERE sd.d = tm.today_date AND sd.site IN (SELECT site FROM tgt)
  GROUP BY sd.site
),
-- store x model x variant: MTD (completed days), today, store stock, month estimate
mix AS (
  SELECT site, cat, model, variant, SUM(mtd) AS mtd, SUM(tod) AS tod, SUM(stock) AS stock, SUM(est) AS est FROM (
    SELECT site, cat, model, variant, q AS mtd, 0 AS tod, 0 AS stock, est FROM sales
    UNION ALL SELECT site, cat, model, variant, 0, CAST(units AS INT64), 0, 0 FROM today
    UNION ALL SELECT site, cat, model, variant, 0, 0, q, 0 FROM stk WHERE line = 'stock')
  GROUP BY site, cat, model, variant
)

SELECT TO_JSON_STRING(STRUCT(
  (SELECT CAST(s AS STRING) FROM p) AS period_start,
  (SELECT CAST(e AS STRING) FROM p) AS period_end,
  (SELECT CAST(sales_asof AS STRING) FROM asof) AS sales_asof,
  (SELECT CAST(stock_date AS STRING) FROM stk_date) AS stock_date,
  (SELECT CAST(today_date AS STRING) FROM today_meta) AS today_date,
  (SELECT today_last_time FROM today_meta) AS today_last_time,
  CAST(CURRENT_DATETIME('Asia/Jakarta') AS STRING) AS refreshed_at,
  -- site|store name|business unit|LOB|TSH|channel|target Summit Device|target A Series|Racing tier 1..5|in Summit|in A Series|in Racing
  ARRAY(SELECT CONCAT(t.site, '|', IFNULL(m.name, ''), '|', IFNULL(m.bu, ''), '|', IFNULL(m.lob, ''), '|', IFNULL(m.tsh, ''), '|',
                      IFNULL(m.ch, ''), '|', CAST(t.td AS STRING), '|', CAST(t.ta AS STRING), '|',
                      CAST(t.r1 AS STRING), '|', CAST(t.r2 AS STRING), '|', CAST(t.r3 AS STRING), '|', CAST(t.r4 AS STRING), '|', CAST(t.r5 AS STRING), '|',
                      CAST(t.in_s AS STRING), '|', CAST(t.in_a AS STRING), '|', CAST(t.in_r AS STRING))
        FROM tgt t LEFT JOIN ms m USING (site) ORDER BY t.site) AS targets,
  -- yyyymmdd|site|units all Samsung Device|units A Series|units S+Z (Racing)   (completed days, sales_vs_stock)
  ARRAY(SELECT CONCAT(FORMAT_DATE('%Y%m%d', d), '|', site, '|', CAST(q_all AS STRING), '|', CAST(q_a AS STRING), '|', CAST(q_r AS STRING))
        FROM daily WHERE q_all <> 0 OR q_a <> 0 OR q_r <> 0 ORDER BY d, site) AS daily,
  -- site|month est all Device|month est A Series|month est S+Z   (SUM_month_est_quantity)
  ARRAY(SELECT CONCAT(site, '|', CAST(ROUND(e_all, 1) AS STRING), '|', CAST(ROUND(e_a, 1) AS STRING), '|', CAST(ROUND(e_r, 1) AS STRING)) FROM est ORDER BY site) AS est,
  -- site|cat|model|variant|MTD units|today units|store stock|month est units   (cat: A=A Series, S, Z, T=Tablet, X=other)
  ARRAY(SELECT CONCAT(site, '|', cat, '|', model, '|', variant, '|', CAST(mtd AS STRING), '|', CAST(tod AS STRING), '|', CAST(stock AS STRING), '|', CAST(ROUND(est, 1) AS STRING))
        FROM mix WHERE mtd <> 0 OR tod <> 0 OR stock <> 0 ORDER BY site, cat, model, variant) AS mix,
  -- site|PAID orders today (any brand, any product)
  ARRAY(SELECT CONCAT(site, '|', CAST(orders AS STRING)) FROM today_any ORDER BY site) AS today_any,
  -- DC site|cat|model|variant|stock units
  ARRAY(SELECT CONCAT(site, '|', cat, '|', model, '|', variant, '|', CAST(q AS STRING)) FROM stk WHERE line = 'stock_dc' ORDER BY site, cat, model, variant) AS dc_stock,
  -- DC site|DC name|business unit
  ARRAY(SELECT CONCAT(site, '|', name, '|', bu) FROM dcs ORDER BY bu, site) AS dcs
)) AS j
