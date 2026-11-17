-- Samsung Summit (November) - single import query (Power BI "import mode" style)
-- Returns ONE row with ONE column `j` (compact JSON). Rows inside are "|"-delimited strings.
-- Summit has two targets per store:
--   Summit Device : master_data.target_summit_november.target_qty   = SAMSUNG Device qty EXCLUDING Tablet (Detail_Cat <> 'TABLET')
--   A Series      : master_data.target_aseries_samsung.target_Aseries = SAMSUNG Device, Detail_Cat = 'A SERIES' qty
--   Racing        : master_data.target_racing_samsung, 5 tiers per store = SAMSUNG Device, Detail_Cat in S SERIES / Z SERIES qty
--   Pesta Akhir Tahun : master_data.target_samsung_pesta_akhir_tahun, target_qty + target_value per store per month
--                   = ALL SAMSUNG Device (incl. Tablet). Program window: 16-30 Nov 2026 (15 days) and 1-31 Dec 2026.
--                   qty = SUM_quantity, value = SUM_total_nett_amount_with_tax; Dec estimate = SUM_month_est_quantity /
--                   SUM_month_est_nett_with_tax; Nov estimate is computed in the page: MTD / days passed x 15.
--                   Today (POS, sales_daily PAID): Quantity and `Total Amount`.
-- Store list = every store in the three target files (site codes are TRIMmed: the Racing file has ' F285')
--   PLUS every ACTIVE store in master_store_r5 (STATUS = 'Active') in BU_CATEGORY 1MULTIBRAND / 5JB / 6OS / 3NASA, even with no sales
--   PLUS every Region 5 site that sold SAMSUNG Device this month, last month or today and can sell Samsung:
--   BU_CATEGORY 1MULTIBRAND / 5JB / 6OS / 3NASA, or an exhibition (STATUS or CHANNEL = EXHIBITION). 7ERABLUE and DCs (4DEPO) are never added.
--   Those extra sites have no target, but their sales count in every total. Store attributes come from sales_b2c.master_store_r5.
-- Edit the period here (the target month/year is taken from the start date):
WITH p AS (SELECT DATE '2026-11-01' AS s, DATE '2026-11-30' AS e),
-- Pesta Akhir Tahun windows (n = November part, d = December part)
pp AS (SELECT DATE '2026-11-16' AS ns, DATE '2026-11-30' AS ne, DATE '2026-12-01' AS ds, DATE '2026-12-31' AS de),

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
t_p AS (
  SELECT TRIM(site_code) AS site,
         SUM(IF(month = 11, target_qty, 0)) AS pq11, SUM(IF(month = 11, target_value, 0)) AS pv11,
         SUM(IF(month = 12, target_qty, 0)) AS pq12, SUM(IF(month = 12, target_value, 0)) AS pv12
  FROM `e-smart-433113.master_data.target_samsung_pesta_akhir_tahun`, pp
  WHERE year = EXTRACT(YEAR FROM pp.ns)
  GROUP BY 1
),
tgt AS (
  SELECT site, IFNULL(td, 0) AS td, IFNULL(ta, 0) AS ta,
         IFNULL(pq11, 0) AS pq11, IFNULL(pv11, 0) AS pv11, IFNULL(pq12, 0) AS pq12, IFNULL(pv12, 0) AS pv12, IF(t_p.site IS NULL, 0, 1) AS in_p,
         -- in-file flags: 1 = store is in that target file (a store can be in Racing only, or have 0 targets)
         IF(t_sum.site IS NULL, 0, 1) AS in_s, IF(t_a.site IS NULL, 0, 1) AS in_a, IF(t_r.site IS NULL, 0, 1) AS in_r,
         IFNULL(r1, 0) AS r1, IFNULL(r2, 0) AS r2, IFNULL(r3, 0) AS r3, IFNULL(r4, 0) AS r4, IFNULL(r5, 0) AS r5
  FROM t_sum FULL JOIN t_a USING (site) FULL JOIN t_r USING (site) FULL JOIN t_p USING (site)
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
         SUM_quantity AS q, SUM_month_est_quantity AS est,
         SUM_total_nett_amount_with_tax AS v, SUM_month_est_nett_with_tax AS ev
  FROM `e-smart-433113.region_data.sales_vs_stock`, p, pp
  WHERE brandname = 'SAMSUNG' AND Product_Category = 'Device'
    -- sales: this period + the whole previous month (for Racing growth MoM) + the Pesta Akhir Tahun window (to 31 Dec)
    AND ((line = 'sales' AND order_date BETWEEN DATE_SUB(p.s, INTERVAL 1 MONTH) AND GREATEST(p.e, pp.de)) OR line IN ('stock', 'stock_dc'))
),
-- last completed sales day = latest sales date in the whole table (any brand)
asof AS (
  SELECT MAX(order_date) AS sales_asof FROM `e-smart-433113.region_data.sales_vs_stock` WHERE line = 'sales'
),
stk_date AS (SELECT MAX(d) AS stock_date FROM svs WHERE line = 'stock'),

-- today intraday POS (PAID). Only used when its date is after the last completed day in sales_vs_stock.
sd AS (
  SELECT PARSE_DATE('%Y/%m/%d', `Date`) AS d, TRIM(`Site Code`) AS site, brandname, product_category,
         detail_cat, model_type, model_type_detail, model_category, Quantity AS q, `Total Amount` AS amt, `Time` AS tm, `Order Number` AS ord
  FROM `e-smart-433113.region_data.sales_daily`
  WHERE `Order Status` = 'PAID'
),
sd_meta AS (SELECT d AS sd_date, MAX(tm) AS sd_last_time FROM sd GROUP BY d ORDER BY d DESC LIMIT 1),
today_meta AS (
  SELECT IF(m.sd_date > a.sales_asof AND (m.sd_date BETWEEN p.s AND p.e OR m.sd_date BETWEEN pp.ns AND pp.de), m.sd_date, NULL) AS today_date,
         IF(m.sd_date > a.sales_asof AND (m.sd_date BETWEEN p.s AND p.e OR m.sd_date BETWEEN pp.ns AND pp.de), m.sd_last_time, NULL) AS today_last_time
  FROM sd_meta m, asof a, p, pp
),
-- every site that sold SAMSUNG Device this month, last month or today
sold AS (
  SELECT site FROM svs WHERE line = 'sales' AND q > 0
  UNION DISTINCT
  SELECT sd.site FROM sd, today_meta tm
  WHERE sd.d = tm.today_date AND sd.brandname = 'SAMSUNG' AND sd.product_category = 'Device' AND sd.q > 0
),
-- ...that belong to a business unit that sells Samsung, or are exhibitions (never 7ERABLUE, never DCs)
sellers AS (
  SELECT DISTINCT sold.site
  FROM sold JOIN `e-smart-433113.sales_b2c.master_store_r5` m ON TRIM(m.site_code) = sold.site
  WHERE (m.BU_CATEGORY IN ('1MULTIBRAND', '5JB', '6OS', '3NASA') OR m.STATUS = 'EXHIBITION' OR m.CHANNEL = 'EXHIBITION')
    AND m.BU_CATEGORY <> '7ERABLUE' AND IFNULL(m.STORE_LOCATION, '') <> '4DEPO'
),
-- every ACTIVE store of a business unit that sells Samsung (included even with no sales, so it shows as inactive)
active AS (
  SELECT TRIM(site_code) AS site FROM `e-smart-433113.sales_b2c.master_store_r5`
  WHERE STATUS = 'Active' AND BU_CATEGORY IN ('1MULTIBRAND', '5JB', '6OS', '3NASA') AND IFNULL(STORE_LOCATION, '') <> '4DEPO'
),
in_scope AS (SELECT site FROM sellers UNION DISTINCT SELECT site FROM active),
-- the dashboard's store list: target-file stores + active Samsung-BU stores + Samsung sellers
-- (seller = 1 when the store is in scope for every view: sold Samsung Device in the window, or is an active Samsung-BU store)
stores AS (
  SELECT site, IFNULL(td, 0) AS td, IFNULL(ta, 0) AS ta, IFNULL(in_s, 0) AS in_s, IFNULL(in_a, 0) AS in_a, IFNULL(in_r, 0) AS in_r,
         IFNULL(pq11, 0) AS pq11, IFNULL(pv11, 0) AS pv11, IFNULL(pq12, 0) AS pq12, IFNULL(pv12, 0) AS pv12, IFNULL(in_p, 0) AS in_p,
         IFNULL(r1, 0) AS r1, IFNULL(r2, 0) AS r2, IFNULL(r3, 0) AS r3, IFNULL(r4, 0) AS r4, IFNULL(r5, 0) AS r5,
         IF(in_scope.site IS NULL, 0, 1) AS seller
  FROM tgt FULL JOIN in_scope USING (site)
),


sales AS (
  SELECT d, site, cat, model, variant, SUM(q) AS q, SUM(est) AS est
  FROM svs, p WHERE line = 'sales' AND d BETWEEN p.s AND p.e AND site IN (SELECT site FROM stores)
  GROUP BY ALL
),
-- Pesta Akhir Tahun: all Samsung Device (incl. Tablet), 16 Nov - 31 Dec, qty + value (nett with tax) + month estimates
psales AS (
  SELECT d, site, cat, model, variant, SUM(q) AS q, SUM(v) AS v, SUM(est) AS eq, SUM(ev) AS ev
  FROM svs, pp WHERE line = 'sales' AND d BETWEEN pp.ns AND pp.de AND site IN (SELECT site FROM stores)
  GROUP BY ALL
),
pdaily AS (SELECT d, site, SUM(q) AS q, SUM(v) AS v FROM psales GROUP BY d, site),
-- December month estimate per store (sum of the December rows, as for Summit)
pest AS (SELECT site, SUM(eq) AS eq, SUM(ev) AS ev FROM psales, pp WHERE d >= pp.ds GROUP BY site),
ptoday AS (
  SELECT sd.site, SUM(sd.q) AS tq, SUM(sd.amt) AS tv
  FROM sd, today_meta tm, pp
  WHERE sd.d = tm.today_date AND sd.d BETWEEN pp.ns AND pp.de AND sd.brandname = 'SAMSUNG' AND sd.product_category = 'Device'
    AND sd.site IN (SELECT site FROM stores)
  GROUP BY sd.site
  HAVING SUM(sd.q) <> 0 OR SUM(sd.amt) <> 0
),
-- last month S+Z qty per store (Racing growth index = month estimate / last month)
lm AS (
  SELECT site, SUM(q) AS lm_r
  FROM svs, p WHERE line = 'sales' AND d < p.s AND cat IN ('S', 'Z') AND site IN (SELECT site FROM stores)
  GROUP BY site
),
-- daily units per store: all Samsung Device, and A Series
daily AS (
  SELECT d, site, SUM(IF(cat <> 'T', q, 0)) AS q_all, SUM(IF(cat = 'A', q, 0)) AS q_a, SUM(IF(cat IN ('S', 'Z'), q, 0)) AS q_r
  FROM sales GROUP BY d, site
),
-- month estimate per store = SUM(SUM_month_est_quantity) from sales_vs_stock
est AS (
  SELECT site, SUM(IF(cat <> 'T', est, 0)) AS e_all, SUM(IF(cat = 'A', est, 0)) AS e_a, SUM(IF(cat IN ('S', 'Z'), est, 0)) AS e_r
  FROM sales GROUP BY site
),
stk AS (
  SELECT * FROM (
    SELECT line, site, cat, model, variant, SUM(q) AS q
    FROM svs, stk_date
    WHERE line IN ('stock', 'stock_dc') AND d = stk_date.stock_date
      AND (line = 'stock_dc' OR site IN (SELECT site FROM stores))
    GROUP BY ALL)
  WHERE q <> 0
),
dcs AS (
  SELECT DISTINCT s.site, IFNULL(m.name, s.site) AS name, IFNULL(m.bu, '') AS bu
  FROM stk s LEFT JOIN ms m USING (site) WHERE s.line = 'stock_dc'
),

today AS (
  SELECT sd.site,
         CASE sd.detail_cat WHEN 'A SERIES' THEN 'A' WHEN 'S SERIES' THEN 'S' WHEN 'Z SERIES' THEN 'Z'
                            WHEN 'TABLET' THEN 'T' ELSE 'X' END AS cat,
         IFNULL(NULLIF(sd.model_type, ''), 'OTHER') AS model,
         TRIM(CONCAT(IFNULL(sd.model_type_detail, ''), ' ', IFNULL(sd.model_category, ''))) AS variant, SUM(sd.q) AS units
  FROM sd, today_meta tm
  WHERE sd.d = tm.today_date AND sd.brandname = 'SAMSUNG' AND sd.product_category = 'Device'
    AND sd.site IN (SELECT site FROM stores)
  GROUP BY ALL
  HAVING units <> 0
),
-- any PAID transaction today (all brands, all products) per store
today_any AS (
  SELECT sd.site, COUNT(DISTINCT sd.ord) AS orders
  FROM sd, today_meta tm
  WHERE sd.d = tm.today_date AND sd.site IN (SELECT site FROM stores)
  GROUP BY sd.site
),
-- store x model x variant: MTD (completed days), today, store stock, month estimate,
-- + Pesta qty 16-30 Nov, Pesta qty December, December month estimate qty
mix AS (
  SELECT site, cat, model, variant, SUM(mtd) AS mtd, SUM(tod) AS tod, SUM(stock) AS stock, SUM(est) AS est,
         SUM(p11) AS p11, SUM(p12) AS p12, SUM(e12) AS e12 FROM (
    SELECT site, cat, model, variant, q AS mtd, 0 AS tod, 0 AS stock, est, 0 AS p11, 0 AS p12, 0 AS e12 FROM sales
    UNION ALL SELECT site, cat, model, variant, 0, CAST(units AS INT64), 0, 0, 0, 0, 0 FROM today
    UNION ALL SELECT site, cat, model, variant, 0, 0, q, 0, 0, 0, 0 FROM stk WHERE line = 'stock'
    UNION ALL SELECT site, cat, model, variant, 0, 0, 0, 0, IF(d <= pp.ne, q, 0), IF(d >= pp.ds, q, 0), IF(d >= pp.ds, eq, 0) FROM psales, pp)
  GROUP BY site, cat, model, variant
)

SELECT TO_JSON_STRING(STRUCT(
  (SELECT CAST(s AS STRING) FROM p) AS period_start,
  (SELECT CAST(e AS STRING) FROM p) AS period_end,
  (SELECT [CAST(ns AS STRING), CAST(ne AS STRING), CAST(ds AS STRING), CAST(de AS STRING)] FROM pp) AS pesta_periods,
  (SELECT CAST(sales_asof AS STRING) FROM asof) AS sales_asof,
  (SELECT CAST(stock_date AS STRING) FROM stk_date) AS stock_date,
  (SELECT CAST(today_date AS STRING) FROM today_meta) AS today_date,
  (SELECT today_last_time FROM today_meta) AS today_last_time,
  CAST(CURRENT_DATETIME('Asia/Jakarta') AS STRING) AS refreshed_at,
  -- site|store name|business unit|LOB|TSH|channel|target Summit Device|target A Series|Racing tier 1..5|in Summit|in A Series|in Racing|sold Samsung
  --   |Pesta Nov qty|Pesta Nov value|Pesta Dec qty|Pesta Dec value|in Pesta
  ARRAY(SELECT CONCAT(t.site, '|', IFNULL(m.name, ''), '|', IFNULL(m.bu, ''), '|', IFNULL(m.lob, ''), '|', IFNULL(m.tsh, ''), '|',
                      IFNULL(m.ch, ''), '|', CAST(t.td AS STRING), '|', CAST(t.ta AS STRING), '|',
                      CAST(t.r1 AS STRING), '|', CAST(t.r2 AS STRING), '|', CAST(t.r3 AS STRING), '|', CAST(t.r4 AS STRING), '|', CAST(t.r5 AS STRING), '|',
                      CAST(t.in_s AS STRING), '|', CAST(t.in_a AS STRING), '|', CAST(t.in_r AS STRING), '|', CAST(t.seller AS STRING), '|',
                      CAST(t.pq11 AS STRING), '|', CAST(t.pv11 AS STRING), '|', CAST(t.pq12 AS STRING), '|', CAST(t.pv12 AS STRING), '|', CAST(t.in_p AS STRING))
        FROM stores t LEFT JOIN ms m USING (site) ORDER BY t.site) AS targets,
  -- yyyymmdd|site|units Summit (Device excl. Tablet)|units A Series|units S+Z (Racing)   (completed days, sales_vs_stock)
  ARRAY(SELECT CONCAT(FORMAT_DATE('%Y%m%d', d), '|', site, '|', CAST(q_all AS STRING), '|', CAST(q_a AS STRING), '|', CAST(q_r AS STRING))
        FROM daily WHERE q_all <> 0 OR q_a <> 0 OR q_r <> 0 ORDER BY d, site) AS daily,
  -- site|month est Summit (excl. Tablet)|month est A Series|month est S+Z   (SUM_month_est_quantity)
  ARRAY(SELECT CONCAT(site, '|', CAST(ROUND(e_all, 1) AS STRING), '|', CAST(ROUND(e_a, 1) AS STRING), '|', CAST(ROUND(e_r, 1) AS STRING)) FROM est ORDER BY site) AS est,
  -- site|cat|model|variant|MTD units|today units|store stock|month est units|Pesta 16-30 Nov units|Pesta Dec units|Dec month est units
  --   (cat: A=A Series, S, Z, T=Tablet, X=other)
  ARRAY(SELECT CONCAT(site, '|', cat, '|', model, '|', variant, '|', CAST(mtd AS STRING), '|', CAST(tod AS STRING), '|', CAST(stock AS STRING), '|', CAST(ROUND(est, 1) AS STRING),
                      '|', CAST(p11 AS STRING), '|', CAST(p12 AS STRING), '|', CAST(ROUND(e12, 1) AS STRING))
        FROM mix WHERE mtd <> 0 OR tod <> 0 OR stock <> 0 OR p11 <> 0 OR p12 <> 0 ORDER BY site, cat, model, variant) AS mix,
  -- Pesta: yyyymmdd|site|units|value (nett with tax, Rp)   all Samsung Device incl. Tablet, 16 Nov - 31 Dec, completed days
  ARRAY(SELECT CONCAT(FORMAT_DATE('%Y%m%d', d), '|', site, '|', CAST(q AS STRING), '|', CAST(CAST(ROUND(v) AS INT64) AS STRING))
        FROM pdaily WHERE q <> 0 OR v <> 0 ORDER BY d, site) AS pdaily,
  -- Pesta: site|December month est units|December month est value
  ARRAY(SELECT CONCAT(site, '|', CAST(ROUND(eq, 1) AS STRING), '|', CAST(CAST(ROUND(ev) AS INT64) AS STRING)) FROM pest WHERE eq <> 0 OR ev <> 0 ORDER BY site) AS pest,
  -- Pesta: site|today units|today value (POS `Total Amount`)
  ARRAY(SELECT CONCAT(site, '|', CAST(CAST(ROUND(tq) AS INT64) AS STRING), '|', CAST(CAST(ROUND(tv) AS INT64) AS STRING)) FROM ptoday ORDER BY site) AS ptoday,
  -- site|last month S+Z qty
  ARRAY(SELECT CONCAT(site, '|', CAST(lm_r AS STRING)) FROM lm WHERE lm_r <> 0 ORDER BY site) AS lm,
  -- site|PAID orders today (any brand, any product)
  ARRAY(SELECT CONCAT(site, '|', CAST(orders AS STRING)) FROM today_any ORDER BY site) AS today_any,
  -- DC site|cat|model|variant|stock units
  ARRAY(SELECT CONCAT(site, '|', cat, '|', model, '|', variant, '|', CAST(q AS STRING)) FROM stk WHERE line = 'stock_dc' ORDER BY site, cat, model, variant) AS dc_stock,
  -- DC site|DC name|business unit
  ARRAY(SELECT CONCAT(site, '|', name, '|', bu) FROM dcs ORDER BY bu, site) AS dcs
)) AS j
