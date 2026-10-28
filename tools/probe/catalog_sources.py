"""Times catalog sources and saves samples (bounded, no retries)."""
import json, os, time, urllib.request
OUT = os.path.join(os.path.dirname(__file__), "out"); os.makedirs(OUT, exist_ok=True)
UA = {"User-Agent": "BookIt catalog probe (https://github.com/MohammedAnasAsif/BookIt)"}
res = {}
for name, url, keep in [
    ("pg_catalog_csv", "https://www.gutenberg.org/cache/epub/feeds/pg_catalog.csv", 4000),
    ("opds_popular", "https://www.gutenberg.org/ebooks/search.opds/?sort_order=downloads", 40000),
    ("opds_popular_p2", "https://www.gutenberg.org/ebooks/search.opds/?sort_order=downloads&start_index=26", 4000),
    ("opds_book", "https://www.gutenberg.org/ebooks/1342.opds", 20000),
    ("gutendex_search", "https://gutendex.com/books?search=austen", 4000),
    ("cover", "https://www.gutenberg.org/cache/epub/1342/pg1342.cover.medium.jpg", 0),
    ("epub", "https://www.gutenberg.org/ebooks/1342.epub3.images", 0),
]:
    t0 = time.time()
    try:
        data = urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=25).read()
        res[name] = {"s": round(time.time() - t0, 2), "bytes": len(data)}
        if keep:
            open(os.path.join(OUT, name + ".txt"), "wb").write(data[:keep])
    except Exception as e:
        res[name] = {"s": round(time.time() - t0, 2), "error": str(e)[:200]}
print(json.dumps(res, indent=1))
json.dump(res, open(os.path.join(OUT, "catalog_timings.json"), "w"), indent=1)
