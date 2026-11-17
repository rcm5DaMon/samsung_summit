"""Build the site: one page per target from dashboard.html, index.html (= Summit Device) and the data files.

    python scripts/build_pages.py _site

writes _site/summit.html, aseries.html, racing.html, pesta.html (dashboard.html with its page set),
_site/index.html (= the HOME dashboard, so the main link opens it straight away) and _site/data/<page>.json.
Used by the deploy job in .github/workflows/refresh.yml.
"""
import pathlib
import shutil
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
PAGES = ("summit", "aseries", "racing", "pesta")
HOME = "summit"            # the dashboard the main link (…/samsung_summit/) opens

out = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "_site")
(out / "data").mkdir(parents=True, exist_ok=True)
tpl = (ROOT / "dashboard.html").read_text(encoding="utf-8")
assert '"__PAGE__"' in tpl, "dashboard.html must contain the __PAGE__ placeholder"
for page in PAGES:
    (out / f"{page}.html").write_text(tpl.replace('"__PAGE__"', f'"{page}"'), encoding="utf-8")
    shutil.copy(ROOT / "data" / f"{page}.json", out / "data" / f"{page}.json")
shutil.copy(out / f"{HOME}.html", out / "index.html")
print(f"Built {len(PAGES)} dashboard pages into {out} (index.html = {HOME})")
