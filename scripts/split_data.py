"""Split the single import-query result into one data file per dashboard page.

Each page only gets its own target and sales data:
  data/summit.json   Summit Device (Samsung Device excl. Tablet)
  data/aseries.json  A Series
  data/racing.json   Racing (S+Z, tiers, last month)
  data/pesta.json    Pesta Akhir Tahun (all Samsung Device incl. Tablet, qty + value, 16-30 Nov and December)

The row formats stay the same as in sql/import.sql; numbers that belong to another page are set to 0
or the rows are left out, so a page never carries another page's figures.

Run on its own to re-split an existing combined file:  python scripts/split_data.py data/all.json
"""
import json
import pathlib
import sys

PAGES = ("summit", "aseries", "racing", "pesta")
# targets columns: 0 site 1 name 2 bu 3 lob 4 tsh 5 ch 6 td 7 ta 8-12 r1..r5 13 in_s 14 in_a 15 in_r 16 seller
#                  17 pq11 18 pv11 19 pq12 20 pv12 21 in_p
KEEP_T = {"summit": {6, 13}, "aseries": {7, 14}, "racing": {8, 9, 10, 11, 12, 15}, "pesta": {17, 18, 19, 20, 21}}
FLAG = {"summit": 13, "aseries": 14, "racing": 15, "pesta": 21}
CATS = {"summit": set("ASZX"), "aseries": {"A"}, "racing": {"S", "Z"}, "pesta": set("ASZTX")}
DAILY_COL = {"summit": 2, "aseries": 3, "racing": 4}       # daily: yyyymmdd|site|q_all|q_a|q_r
EST_COL = {"summit": 1, "aseries": 2, "racing": 3}         # est: site|e_all|e_a|e_r


def _num(x):
    try:
        return float(x)
    except ValueError:
        return 0.0


def split(data):
    out = {}
    for page in PAGES:
        d = {k: data.get(k) for k in ("period_start", "period_end", "sales_asof", "stock_date", "today_date",
                                         "today_last_time", "refreshed_at")}
        d["page"] = page
        cats = CATS[page]

        # stores: in this page's target file, or in scope for every view (sold Samsung / active Samsung-BU store)
        rows = []
        for r in data["targets"]:
            c = r.split("|")
            c += ["0"] * (22 - len(c))
            if c[FLAG[page]] != "1" and c[16] != "1":
                continue
            for i in range(6, 22):
                if i != 16 and i not in KEEP_T[page]:
                    c[i] = "0"
            rows.append("|".join(c))
        d["targets"] = rows
        sites = {r.split("|")[0] for r in rows}

        if page in DAILY_COL:
            i = DAILY_COL[page]
            d["daily"] = [f"{c[0]}|{c[1]}|{c[2] if i == 2 else 0}|{c[3] if i == 3 else 0}|{c[4] if i == 4 else 0}"
                          for c in (r.split("|") for r in data["daily"]) if c[1] in sites and _num(c[i]) != 0]
            j = EST_COL[page]
            d["est"] = [f"{c[0]}|{c[1] if j == 1 else 0}|{c[2] if j == 2 else 0}|{c[3] if j == 3 else 0}"
                        for c in (r.split("|") for r in data["est"]) if c[0] in sites and _num(c[j]) != 0]
        else:
            d["daily"], d["est"] = [], []

        # store x variant mix: only this page's categories; Summit pages drop the Pesta columns, Pesta drops the Summit-month ones
        mix = []
        for r in data["mix"]:
            c = r.split("|")
            c += ["0"] * (11 - len(c))
            if c[0] not in sites or c[1] not in cats:
                continue
            if page == "pesta":
                c[4], c[7] = "0", "0"
                keep = any(_num(c[k]) != 0 for k in (5, 6, 8, 9))
            else:
                c[8], c[9], c[10] = "0", "0", "0"
                keep = any(_num(c[k]) != 0 for k in (4, 5, 6))
            if keep:
                mix.append("|".join(c))
        d["mix"] = mix

        d["lm"] = [r for r in data.get("lm", []) if r.split("|")[0] in sites] if page == "racing" else []
        if page == "pesta":
            d["pesta_periods"] = data.get("pesta_periods")
            d["pdaily"] = [r for r in data.get("pdaily", []) if r.split("|")[1] in sites]
            d["pest"] = [r for r in data.get("pest", []) if r.split("|")[0] in sites]
            d["ptoday"] = [r for r in data.get("ptoday", []) if r.split("|")[0] in sites]
        d["today_any"] = [r for r in data.get("today_any", []) if r.split("|")[0] in sites]
        d["dc_stock"] = [r for r in data.get("dc_stock", []) if r.split("|")[1] in cats]
        dc_sites = {r.split("|")[0] for r in d["dc_stock"]}
        d["dcs"] = [r for r in data.get("dcs", []) if r.split("|")[0] in dc_sites]
        out[page] = d
    return out


def write_all(data, folder):
    folder = pathlib.Path(folder)
    folder.mkdir(parents=True, exist_ok=True)
    for page, d in split(data).items():
        f = folder / f"{page}.json"
        f.write_text(json.dumps(d, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
        print(f"Wrote {f} ({f.stat().st_size / 1024:.1f} KB, {len(d['targets'])} stores)")


if __name__ == "__main__":
    src = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "data/all.json")
    write_all(json.loads(src.read_text(encoding="utf-8")), src.parent)
