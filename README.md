# Samsung Summit · November dashboard (Erajaya Region 5)

A static web dashboard (GitHub Pages) using **import mode** like Power BI. One BigQuery query pulls a small,
pre-aggregated extract (`data/summit.json`, about 75 KB). Every filter, drill-down and hover then runs in the
browser at **zero BigQuery cost**. Data only changes when you press **Run workflow**.

It works the same way as `sbd_vivo` and `ip18-vs-ip17`.

| File | What it is |
|---|---|
| `index.html` | The dashboard (no external libraries) |
| `data/summit.json` | The imported extract |
| `sql/import.sql` | The single import query. **Edit the period here** (`DATE '2026-11-01'` / `DATE '2026-11-30'`) |
| `scripts/refresh.py` | Dry-runs the query (cost check), runs it with a 1 GB billing cap, writes `data/summit.json` |
| `.github/workflows/refresh.yml` | The "Refresh data" workflow + Pages deploy |

**Cost per refresh:** about 0.18 GB scanned. That's roughly Rp 20 on demand, or free within BigQuery's 1 TB/month free tier.
You can refresh many times a day.

---

## One-time setup (about 10 minutes)

1. Create a new repo `rcm5DaMon/samsung_summit` and upload **all** files in this folder. Include the hidden `.github` folder.
2. **Settings → Secrets and variables → Actions → New repository secret.** Name: `GCP_SA_KEY`. Value: the same service-account
   JSON key you use for `sbd_vivo` (it needs **BigQuery Data Viewer** + **BigQuery Job User** on `e-smart-433113`).
3. **Settings → Pages → Build and deployment → Source: GitHub Actions.**
4. If your repo has a different name, change `const GITHUB_REPO = "rcm5DaMon/samsung_summit";` near the top of the script in `index.html`.
5. **Actions → Refresh data → Run workflow.** After about 1 minute the site is live at
   `https://rcm5damon.github.io/samsung_summit/`.

## Daily use
- **Refresh:** click **Refresh data ↗** on the page, then **Run workflow**. Wait about 1 minute and reload.
  Each refresh picks up the latest `sales_vs_stock` day, the latest stock snapshot, and today's POS from `sales_daily`.
- **Automatic refresh:** uncomment the `schedule` block in `.github/workflows/refresh.yml`. Cron is in UTC, so
  `"0 1,5,9 * * *"` = 08:00, 12:00 and 16:00 WIB.
- **New targets or a new month:** update the two target tables in BigQuery, change the two dates in `sql/import.sql`,
  then run the workflow.

## What's on the page
- **Target switch:** Summit Device or A Series. **Filters:** Business unit → LOB → TSH (cascading) and store search.
- **KPI cards:**
  - Achievement for both targets: MTD, estimate, and incl. today.
  - Stores on track (MTD and estimate).
  - Today so far.
  - Inactive stores today: no Samsung sale yet, and no transaction at all.
  - Store stock.

  Click any count to list those stores.
- **Cumulative sales vs target pace** and **Achievement by TSH**.
- **Breakdown table** (like iP18 vs iP17): by Business unit, Channel, LOB or TSH, with Summit Device and A Series side by side
  (target, MTD, achievement, today, estimate, stores on track), plus stores with no Samsung sale today, store stock and a TOTAL row.
  Click a row to filter the page, click a column to sort.
- **Review table:** LOB → TSH → Store, collapsible. The "Show down to" buttons set the level. Click a store to focus the whole page on it.
- **Stock analysis:** grouped by Detail_Cat (A / S / Z Series, Tablet), broken down by Model_Type_Detail + Model_Category
  (e.g. "A57 5G 8/256 GB"). Shows MTD, today, month estimate, store stock, days of cover, DC stock, stores that sold it but now
  hold none, and stock health. Click a category row to open or close it.
- **DC stock:** Erafone DCs (serve Multibrand, Channel Store and Joint Business stores) and NASA DCs (serve Samsung stores).
- **Save PNG / Copy image** for WhatsApp.

## Definitions
- **Store list:** every store in `master_data.target_summit_november` and `master_data.target_aseries_samsung` (151 stores).
  Business unit (`BU_CATEGORY`), LOB, TSH and channel come from `sales_b2c.master_store_r5`.
- **Summit Device:** `brandname = SAMSUNG`, `Product_Category = Device`. **A Series:** the same with `Detail_Cat = A SERIES`.
- **MTD:** `SUM_quantity` from `region_data.sales_vs_stock` for completed days, 1 Nov to the last loaded day.
- **Month-end estimate:** `SUM_month_est_quantity` from the same table. It equals MTD ÷ completed days × 30.
- **On track (MTD):** MTD ≥ target × completed days ÷ 30. Status colours: on track ≥ 100% of pace, slightly behind 80–99%, behind < 80%.
- **On track (estimate):** estimate ≥ target. Because the estimate is a straight run-rate, this count always equals the MTD count.
- **Today:** PAID POS orders in `region_data.sales_daily`, used only when its date is after the last completed day, so nothing is counted twice.
  **No sale** = no Summit/A Series unit today. **No trx** = no PAID transaction of any product today.
- **Gap:** target − (MTD + today). **Need / day:** gap ÷ days left including today.
- **Stock:** latest `stock` snapshot per store and `stock_dc` per DC (Samsung Device).
  **Cover (days):** (stock ÷ month-end estimate qty) × 30.42, where the estimate is `SUM_month_est_quantity` and 30.42 = average days per month.
  Group rows (TSH, LOB, total, model) use their summed stock ÷ summed estimate.
  Stock is flagged when it runs out before month-end, under 7 days is low, and over 60 days is overstock.
  **Stock vs gap:** whether store stock covers its remaining gap.
- **Top-5 OOS:** of the 5 best-selling models in the current view, the ones the store has zero stock of.

## ⚠ Visibility
GitHub Pages sites are **public** unless your org has GitHub Enterprise Cloud with private Pages.
Anyone with the URL can see store names and figures.
