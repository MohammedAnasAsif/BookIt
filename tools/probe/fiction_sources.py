"""Checks candidate sources for the new shelves (Standard Ebooks, Open Library
trending, Creative Commons novels) and saves samples. Bounded, no retries."""
import json, os, re, time, urllib.request
OUT = os.path.join(os.path.dirname(__file__), "out"); os.makedirs(OUT, exist_ok=True)
UA = {"User-Agent": "BookIt source check (https://github.com/MohammedAnasAsif/BookIt)"}
res = {}

def get(name, url, keep=0, grep=None):
    t0 = time.time()
    try:
        r = urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=30)
        data = r.read()
        info = {"s": round(time.time() - t0, 2), "bytes": len(data), "type": r.headers.get("Content-Type"), "final": r.geturl()}
        if grep:
            text = data.decode("utf-8", "replace")
            info["matches"] = sorted(set(re.findall(grep, text)))[:40]
        if keep:
            open(os.path.join(OUT, "fs_" + name + ".txt"), "wb").write(data[:keep])
        res[name] = info
        return data
    except Exception as e:
        res[name] = {"s": round(time.time() - t0, 2), "error": str(e)[:300]}
        return None

# Standard Ebooks
get("se_feeds", "https://standardebooks.org/feeds", 20000)
get("se_opds", "https://standardebooks.org/feeds/opds", 20000)
get("se_opds_all", "https://standardebooks.org/feeds/opds/all", 30000)
get("se_atom_new", "https://standardebooks.org/feeds/atom/new-releases", 30000)
get("se_rss_new", "https://standardebooks.org/feeds/rss/new-releases", 30000)
get("se_ebooks_page", "https://standardebooks.org/ebooks?per-page=48", 4000, r'href="(/ebooks/[^"]+)"')
get("se_book", "https://standardebooks.org/ebooks/jane-austen/pride-and-prejudice", 4000, r'href="([^"]+\.(?:epub|kepub|azw3)[^"]*)"')
get("se_epub", "https://standardebooks.org/ebooks/jane-austen/pride-and-prejudice/downloads/jane-austen_pride-and-prejudice.epub")
get("se_epub_q", "https://standardebooks.org/ebooks/jane-austen/pride-and-prejudice/downloads/jane-austen_pride-and-prejudice.epub?source=download")
get("se_cover", "https://standardebooks.org/images/covers/jane-austen_pride-and-prejudice-cover.jpg")
get("se_github_org", "https://api.github.com/orgs/standardebooks", 3000)
get("se_github_repos", "https://api.github.com/orgs/standardebooks/repos?per_page=5&sort=pushed", 6000)
get("se_raw_content_opf", "https://raw.githubusercontent.com/standardebooks/jane-austen_pride-and-prejudice/master/src/epub/content.opf", 6000)

# Open Library trending + covers
get("ol_trending_daily", "https://openlibrary.org/trending/daily.json?limit=20", 20000)
get("ol_trending_weekly", "https://openlibrary.org/trending/weekly.json?limit=50", 30000)
get("ol_trending_monthly", "https://openlibrary.org/trending/monthly.json?limit=50", 30000)
get("ol_search_iewu", "https://openlibrary.org/search.json?q=it+ends+with+us&limit=3&fields=key,title,author_name,cover_i,first_publish_year,isbn,subject", 20000)
get("ol_subject_romance", "https://openlibrary.org/subjects/romance.json?limit=10&published_in=2015-2026", 20000)
get("ol_subject_thriller", "https://openlibrary.org/subjects/thrillers.json?limit=10&published_in=2015-2026", 20000)
get("ol_cover", "https://covers.openlibrary.org/b/id/12547191-M.jpg")

# Creative Commons novels: candidate pages / files
for name, url, grep in [
    ("unglue_opds", "https://unglue.it/api/opds/", None),
    ("unglue_opds_cc", "https://unglue.it/api/opds/creative_commons/", None),
    ("unglue_free_sf", "https://unglue.it/free/kw.Science%20Fiction/by-nc-sa", r'href="(/work/\d+/)"'),
    ("unglue_free_all", "https://unglue.it/free/?order_by=popular", r'href="(/work/\d+/)"'),
    ("unglue_littlebrother", "https://unglue.it/work/82034/", r'href="([^"]+\.epub[^"]*)"'),
    ("craphound_lb", "https://craphound.com/littlebrother/download/", r'href="([^"]+\.(?:epub|txt|html|zip)[^"]*)"'),
    ("craphound_down", "https://craphound.com/down/download/", r'href="([^"]+\.(?:epub|txt|html|zip)[^"]*)"'),
    ("rifters_blindsight", "https://www.rifters.com/real/Blindsight.htm", r'(creativecommons\.org/licenses/[^"\' ]+)'),
    ("rifters_starfish", "https://www.rifters.com/real/STARFISH.htm", r'(creativecommons\.org/licenses/[^"\' ]+)'),
    ("archive_lb", "https://archive.org/advancedsearch.php?q=creator%3A%22Cory+Doctorow%22+AND+mediatype%3Atexts&fl%5B%5D=identifier&fl%5B%5D=title&fl%5B%5D=licenseurl&rows=50&output=json", None),
    ("feedbooks_original", "https://catalog.feedbooks.com/publicdomain/browse/top.atom", None),
]:
    get(name, url, 40000, grep)

print(json.dumps(res, indent=1))
json.dump(res, open(os.path.join(OUT, "fiction_sources.json"), "w"), indent=1)
